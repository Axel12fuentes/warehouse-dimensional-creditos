# -*- coding: utf-8 -*-
"""Escribe las medidas DAX dentro del modelo semantico del proyecto .pbip.

    python scripts/agregar_medidas.py

Power BI Desktop debe estar CERRADO: si esta abierto, sobrescribe los
archivos al guardar y se pierde lo escrito.

Por que se puede hacer esto: un .pbip guarda el modelo como TMDL, que es
texto. Eso convierte al modelo en codigo: se versiona, se revisa en un pull
request y se despliega. Un .pbix es un binario y no permite nada de eso.

El script es idempotente: si una medida ya existe, la reemplaza.

OJO con los nombres: en Power BI una medida NO puede llamarse igual que una
columna de su tabla. Por eso la medida sobre la columna `gestiones` se llama
"Total gestiones" y no "Gestiones".
"""
import io
import os
import re
import uuid

RAIZ = os.path.join("powerbi", "dashboard.SemanticModel", "definition", "tables")

PESOS   = '#,##0'
SOLES   = '"S/ "#,##0'
PCT     = '0.0%'
DECIMAL = '#,##0.0'

# (nombre, expresion DAX, formato, carpeta)
MEDIDAS = {
    "dw fact_gestion.tmdl": [
        ("Total gestiones",
         "SUM('dw fact_gestion'[gestiones])", PESOS, "01 Volumen"),
        ("Contactos efectivos",
         "SUM('dw fact_gestion'[es_contacto])", PESOS, "01 Volumen"),
        ("Cierres",
         "SUM('dw fact_gestion'[es_desembolso])", PESOS, "01 Volumen"),
        ("Rechazos",
         "SUM('dw fact_gestion'[es_rechazo])", PESOS, "01 Volumen"),
        ("Leads trabajados",
         "DISTINCTCOUNT('dw fact_gestion'[sk_cliente])", PESOS, "01 Volumen"),

        ("Tasa de cierre",
         "DIVIDE([Cierres], [Total gestiones])", PCT, "02 Efectividad"),
        ("Contactabilidad",
         "DIVIDE([Contactos efectivos], [Total gestiones])", PCT, "02 Efectividad"),
        ("Tasa de rechazo",
         "DIVIDE([Rechazos], [Contactos efectivos])", PCT, "02 Efectividad"),
        ("Gestiones por cierre",
         "DIVIDE([Total gestiones], [Cierres])", DECIMAL, "02 Efectividad"),
        ("Duracion promedio min",
         "DIVIDE(AVERAGE('dw fact_gestion'[duracion_seg]), 60)", DECIMAL,
         "02 Efectividad"),
    ],
    "dw fact_desembolso.tmdl": [
        ("Total desembolsos",
         "SUM('dw fact_desembolso'[desembolsos])", PESOS, "03 Colocacion"),
        ("Monto colocado",
         "SUM('dw fact_desembolso'[monto_pen])", SOLES, "03 Colocacion"),
        ("Monto aprobado",
         "SUM('dw fact_desembolso'[monto_aprobado])", SOLES, "03 Colocacion"),
        ("Ticket promedio",
         "DIVIDE([Monto colocado], [Total desembolsos])", SOLES, "03 Colocacion"),
        ("Tasa de utilizacion",
         "DIVIDE([Monto colocado], [Monto aprobado])", PCT, "03 Colocacion"),
        ("Plazo promedio meses",
         "AVERAGE('dw fact_desembolso'[plazo_meses])", DECIMAL, "03 Colocacion"),

        ("Monto colocado YTD",
         "TOTALYTD([Monto colocado], 'dw dim_tiempo'[fecha])", SOLES, "04 Tiempo"),
        ("Monto mes anterior",
         "CALCULATE([Monto colocado], DATEADD('dw dim_tiempo'[fecha], -1, MONTH))",
         SOLES, "04 Tiempo"),
        ("Variacion vs mes anterior",
         "DIVIDE([Monto colocado] - [Monto mes anterior], [Monto mes anterior])",
         PCT, "04 Tiempo"),
    ],
}


def bloque(nombre, dax, formato, carpeta):
    """Un measure en TMDL. La indentacion es con tabulaciones, no espacios."""
    return (
        f"\n\tmeasure '{nombre}' = {dax}\n"
        f"\t\tformatString: {formato}\n"
        f"\t\tdisplayFolder: {carpeta}\n"
        f"\t\tlineageTag: {uuid.uuid4()}\n"
    )


def quitar_existente(texto, nombre):
    """Borra la medida si ya estaba, para poder volver a correr el script."""
    patron = re.compile(
        r"\n\tmeasure '" + re.escape(nombre) + r"'[\s\S]*?(?=\n\t(?:measure|column|partition|hierarchy|annotation) |\n\tannotation |\Z)",
        re.M)
    return patron.sub("", texto)


# Nombres que el script uso antes y ya no. Hay que borrarlos igual, o al
# renombrar una medida quedarian las dos versiones conviviendo.
OBSOLETAS = ["Gestiones", "Desembolsos"]


def main():
    if not os.path.isdir(RAIZ):
        raise SystemExit(f"No encuentro {RAIZ}. Corre el script desde la raiz del proyecto.")

    total = 0
    for archivo, lista in MEDIDAS.items():
        ruta = os.path.join(RAIZ, archivo)
        texto = io.open(ruta, encoding="utf-8").read()

        for nombre in [n for n, *_ in lista] + OBSOLETAS:
            texto = quitar_existente(texto, nombre)

        # las medidas van despues de la ultima columna y antes de la particion
        corte = texto.find("\n\tpartition ")
        if corte == -1:
            corte = len(texto)

        nuevas = "".join(bloque(n, d, f, c) for n, d, f, c in lista)
        texto = texto[:corte] + nuevas + texto[corte:]

        io.open(ruta, "w", encoding="utf-8", newline="\r\n").write(texto)
        print(f"  {archivo:32s} {len(lista):>2} medidas")
        total += len(lista)

    print(f"\n{total} medidas escritas. Abre dashboard.pbip en Power BI.")


if __name__ == "__main__":
    main()
