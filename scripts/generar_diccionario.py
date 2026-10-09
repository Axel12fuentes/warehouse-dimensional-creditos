# -*- coding: utf-8 -*-
"""Genera el diccionario de datos leyendo los metadatos de la base.

    python scripts/generar_diccionario.py

Escribe docs/02-diccionario-datos.md.

Por que generarlo y no escribirlo: un diccionario en un documento aparte se
desactualiza la primera semana. Este sale de los COMMENT ON que viven en la
base, asi que cambia cuando cambia la tabla.
"""
import io
import os
from datetime import date

import psycopg2

SALIDA = os.path.join("docs", "02-diccionario-datos.md")
ESQUEMAS = ("dw", "staging")

SQL_TABLAS = """
SELECT n.nspname                                   AS esquema,
       c.relname                                   AS tabla,
       obj_description(c.oid, 'pg_class')          AS descripcion,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS tamano,
       c.reltuples::BIGINT                         AS filas_aprox
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = ANY(%s) AND c.relkind = 'r'
ORDER BY n.nspname, c.relname;
"""

SQL_COLUMNAS = """
SELECT a.attname                                       AS columna,
       format_type(a.atttypid, a.atttypmod)            AS tipo,
       NOT a.attnotnull                                AS admite_nulo,
       col_description(c.oid, a.attnum)                AS descripcion,
       EXISTS (SELECT 1 FROM pg_index i
                WHERE i.indrelid = c.oid AND i.indisprimary
                  AND a.attnum = ANY(i.indkey))        AS es_pk,
       (SELECT cl2.relname FROM pg_constraint con
          JOIN pg_class cl2 ON cl2.oid = con.confrelid
         WHERE con.conrelid = c.oid AND con.contype = 'f'
           AND a.attnum = ANY(con.conkey) LIMIT 1)     AS apunta_a
FROM pg_attribute a
JOIN pg_class c      ON c.oid = a.attrelid
JOIN pg_namespace n  ON n.oid = c.relnamespace
WHERE n.nspname = %s AND c.relname = %s
  AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY a.attnum;
"""


def conectar():
    return psycopg2.connect(
        host=os.getenv("PGHOST", "localhost"),
        port=os.getenv("PGPORT", "5433"),
        dbname=os.getenv("POSTGRES_DB", "wh_creditos"),
        user=os.getenv("POSTGRES_USER"),
        password=os.getenv("POSTGRES_PASSWORD"),
    )


def escapar(texto):
    return (texto or "").replace("|", "\\|").replace("\n", " ").strip()


def main():
    partes = [
        "# Diccionario de datos",
        "",
        "> Generado automaticamente desde los metadatos de la base.",
        "> No se edita a mano: se editan los `COMMENT ON` en "
        "[`sql/09_diccionario.sql`](../sql/09_diccionario.sql) y se vuelve a correr",
        "> `python scripts/generar_diccionario.py`.",
        "",
        f"Ultima generacion: {date.today().isoformat()}",
        "",
    ]

    with conectar() as con, con.cursor() as cur:
        cur.execute(SQL_TABLAS, (list(ESQUEMAS),))
        tablas = cur.fetchall()

        # indice
        partes += ["## Tablas", "",
                   "| Esquema | Tabla | Filas aprox. | Tamano | Que contiene |",
                   "|---|---|---:|---:|---|"]
        for esq, tab, desc, tam, filas in tablas:
            ancla = f"{esq}{tab}".replace("_", "")
            partes.append(
                f"| `{esq}` | [`{tab}`](#{ancla}) | {filas:,} | {tam} | {escapar(desc)} |")
        partes.append("")

        # detalle
        for esq, tab, desc, tam, filas in tablas:
            partes += ["---", "", f"## {esq}.{tab}", ""]
            if desc:
                partes += [f"{desc}", ""]
            partes += [f"*{filas:,} filas aproximadas · {tam}*", "",
                       "| Columna | Tipo | Nulo | Llave | Descripcion |",
                       "|---|---|:-:|---|---|"]
            cur.execute(SQL_COLUMNAS, (esq, tab))
            for col, tipo, nulo, cdesc, es_pk, apunta in cur.fetchall():
                llave = "PK" if es_pk else (f"FK a `{apunta}`" if apunta else "")
                partes.append(
                    f"| `{col}` | {tipo} | {'si' if nulo else 'no'} | {llave} | "
                    f"{escapar(cdesc)} |")
            partes.append("")

    os.makedirs("docs", exist_ok=True)
    io.open(SALIDA, "w", encoding="utf-8").write("\n".join(partes) + "\n")

    sin_doc = sum(1 for p in partes if p.endswith("|  |"))
    print(f"{SALIDA} generado · {len(tablas)} tablas · "
          f"{sin_doc} columna(s) sin descripcion")


if __name__ == "__main__":
    main()
