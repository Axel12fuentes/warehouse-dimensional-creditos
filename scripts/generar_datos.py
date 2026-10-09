# -*- coding: utf-8 -*-
"""Genera datos de prueba para el esquema operacional.

    python scripts/generar_datos.py              # carga todo
    python scripts/generar_datos.py --traslados  # solo mueve asesores de oficina

La semilla es fija, asi que la misma corrida produce siempre los mismos
datos: eso hace el proyecto reproducible y las pruebas comparables.

El dato clave para el warehouse: la tabla `personal` guarda solo la oficina
ACTUAL. Al correr --traslados, dos asesores cambian de oficina y la historia
anterior se pierde en el origen. Reconstruirla es el trabajo del SCD tipo 2.
"""
import argparse
import os
import random
from datetime import date, datetime, timedelta

import psycopg2
from psycopg2.extras import execute_values

SEMILLA = 20261009
random.seed(SEMILLA)

# --- parametros del escenario -------------------------------------------
N_LEADS = 600
N_ASESORES = 15
INICIO = date(2026, 1, 1)
FIN = date(2026, 9, 30)

REGIONES = {
    "Lima":      ["San Isidro", "Miraflores", "San Juan de Lurigancho", "Comas"],
    "Arequipa":  ["Cercado", "Cayma"],
    "Puno":      ["Juliaca", "Puno Centro"],
    "La Libertad": ["Trujillo Centro"],
}
PRODUCTOS = [
    ("Credito Capital de Trabajo", 3000, 45000),
    ("Credito Agricola",           2000, 30000),
    ("Credito Consumo",            1000, 15000),
    ("Credito Vehicular",         10000, 80000),
    ("Microcredito",                500,  6000),
]
CANALES = ["Campana telefonica", "Referido", "Web", "Visita en campo", "Base BI"]
CANAL_CONTACTO = ["Llamada", "WhatsApp", "Presencial"]
NOMBRES = ["Rosa", "Carlos", "Maria", "Jorge", "Lucia", "Victor", "Elena", "Raul",
           "Patricia", "Miguel", "Sandra", "Fernando", "Carmen", "Diego", "Ana",
           "Julio", "Norma", "Cesar", "Gloria", "Hugo"]
APELLIDOS = ["Quispe", "Mamani", "Flores", "Rojas", "Chavez", "Huaman", "Vargas",
             "Condori", "Salazar", "Ticona", "Paredes", "Alvarez", "Nunez",
             "Bautista", "Carrion", "Espinoza", "Luna", "Ramos", "Zapata", "Ore"]

# Gestiones intermedias: el cliente todavia no decide.
RESULTADOS_INTERMEDIOS = {
    "No contesta": 0.42,
    "Contactado":  0.34,
    "Interesado":  0.24,
}
# Ultima gestion del lead: aqui si se define. Da una conversion cercana al 20%,
# que es lo tipico de una cartera de leads pre-aprobados en microfinanzas.
RESULTADOS_CIERRE = {
    "Desembolsado": 0.22,
    "Rechazado":    0.20,
    "Interesado":   0.21,
    "Contactado":   0.20,
    "No contesta":  0.17,
}


def conectar():
    return psycopg2.connect(
        host=os.getenv("PGHOST", "localhost"),
        port=os.getenv("PGPORT", "5433"),
        dbname=os.getenv("POSTGRES_DB", "wh_creditos"),
        user=os.getenv("POSTGRES_USER"),
        password=os.getenv("POSTGRES_PASSWORD"),
    )


def nombre():
    return f"{random.choice(NOMBRES)} {random.choice(APELLIDOS)} {random.choice(APELLIDOS)}"


def fecha_entre(a, b):
    return a + timedelta(days=random.randint(0, (b - a).days))


def elegir_resultado(es_ultima):
    tabla = RESULTADOS_CIERRE if es_ultima else RESULTADOS_INTERMEDIOS
    r, acc = random.random(), 0.0
    for res, p in tabla.items():
        acc += p
        if r <= acc:
            return res
    return "Contactado"


# -------------------------------------------------------------------------
def generar_personal():
    filas, pares = [], [(reg, of) for reg, ofs in REGIONES.items() for of in ofs]
    for i in range(1, N_ASESORES + 1):
        region, oficina = pares[(i - 1) % len(pares)]
        cargo = "Jefe de agencia" if i % 7 == 0 else "Asesor de ventanilla"
        filas.append((
            f"A-{i:03d}", nombre(), region, oficina,
            f"Ventanilla {((i - 1) % 5) + 1}", cargo,
            "Cesado" if i % 13 == 0 else "Activo",
        ))
    return filas


def generar_leads():
    filas, pares = [], [(reg, of) for reg, ofs in REGIONES.items() for of in ofs]
    for i in range(1, N_LEADS + 1):
        producto, piso, techo = random.choice(PRODUCTOS)
        region, oficina = random.choice(pares)
        score = random.randint(300, 850)
        # mejor score, mas prioridad (1 = mas propenso a desembolsar)
        prioridad = 1 if score > 740 else 2 if score > 660 else 3 if score > 580 else 4 if score > 480 else 5
        filas.append((
            f"L-{i:05d}", fecha_entre(INICIO, FIN), nombre(),
            f"{random.randint(10000000, 79999999)}",
            f"9{random.randint(10000000, 99999999)}",
            oficina, producto,
            round(random.uniform(piso, techo), 2),
            score, prioridad, random.choice(CANALES), region, oficina,
        ))
    return filas


def generar_asignaciones(leads, personal):
    activos = [p[0] for p in personal if p[6] == "Activo"]
    filas = []
    for n, lead in enumerate(leads):
        asesor = activos[n % len(activos)]          # reparto redondo
        asignado = datetime.combine(lead[1], datetime.min.time()) + timedelta(
            days=random.randint(0, 3), hours=random.randint(8, 17))
        filas.append((lead[0], asesor, asignado))
    return filas


def generar_gestiones(leads, asignaciones):
    por_lead = {a[0]: a for a in asignaciones}
    gestiones, convertidos = [], []
    for lead in leads:
        asig = por_lead[lead[0]]
        n = random.choices([1, 2, 3, 4, 5, 6, 7], weights=[12, 20, 23, 18, 13, 9, 5])[0]
        momento = asig[2]
        cerrado = False
        for k in range(n):
            momento += timedelta(days=random.randint(1, 9), hours=random.randint(0, 8))
            if momento.date() > FIN:
                break
            resultado = elegir_resultado(es_ultima=(k == n - 1))
            if resultado == "Desembolsado":
                cerrado = True
            gestiones.append((
                lead[0], asig[1], random.choice(CANAL_CONTACTO), resultado,
                random.randint(20, 900) if resultado != "No contesta" else random.randint(5, 30),
                None, momento,
            ))
            if resultado in ("Desembolsado", "Rechazado"):
                break
        if cerrado:
            convertidos.append((lead, asig[1], momento.date()))
    return gestiones, convertidos


def generar_desembolsos(convertidos):
    filas = []
    for lead, asesor, fecha in convertidos:
        aprobado = float(lead[7])
        monto = round(aprobado * random.uniform(0.55, 1.0), 2)   # casi nunca toman todo
        moneda = "USD" if random.random() < 0.08 else "PEN"
        if moneda == "USD":
            monto = round(monto / 3.75, 2)
        filas.append((
            lead[0], asesor, fecha, monto,
            random.choice([6, 12, 18, 24, 36, 48]),
            round(random.uniform(14.0, 68.0), 2), moneda,
        ))
    return filas


# -------------------------------------------------------------------------
def cargar(cur):
    print("Limpiando tablas...")
    cur.execute("TRUNCATE operacional.desembolsos, operacional.gestiones, "
                "operacional.asignaciones, operacional.leads, "
                "operacional.personal RESTART IDENTITY CASCADE;")

    # Reiniciar el origen obliga a reiniciar staging: los contadores vuelven
    # a 1 y las marcas de agua apuntan a un pasado que ya no existe.
    cur.execute("SELECT 1 FROM information_schema.routines "
                "WHERE routine_schema='staging' AND routine_name='reiniciar'")
    if cur.fetchone():
        cur.execute("CALL staging.reiniciar();")
        print("  staging reiniciado")

    personal = generar_personal()
    execute_values(cur,
        "INSERT INTO operacional.personal "
        "(id_asesor, nombre, region, oficina, puesto, cargo, estado) VALUES %s",
        personal)
    print(f"  personal      {len(personal):>6}")

    leads = generar_leads()
    execute_values(cur,
        "INSERT INTO operacional.leads (id_lead, fecha_aprobacion, nombre_cliente, "
        "documento, telefono, distrito, producto, monto_aprobado, score_riesgo, "
        "prioridad, canal, region, oficina) VALUES %s", leads)
    print(f"  leads         {len(leads):>6}")

    asignaciones = generar_asignaciones(leads, personal)
    execute_values(cur,
        "INSERT INTO operacional.asignaciones (id_lead, id_asesor, asignado_en) VALUES %s",
        asignaciones)
    print(f"  asignaciones  {len(asignaciones):>6}")

    gestiones, convertidos = generar_gestiones(leads, asignaciones)
    execute_values(cur,
        "INSERT INTO operacional.gestiones (id_lead, id_asesor, canal_contacto, "
        "resultado, duracion_seg, comentario, registrado_en) VALUES %s", gestiones)
    print(f"  gestiones     {len(gestiones):>6}")

    desembolsos = generar_desembolsos(convertidos)
    execute_values(cur,
        "INSERT INTO operacional.desembolsos (id_lead, id_asesor, fecha, monto, "
        "plazo_meses, tasa_anual, moneda) VALUES %s", desembolsos)
    print(f"  desembolsos   {len(desembolsos):>6}")


def trasladar(cur):
    """Mueve dos asesores de oficina SOBRESCRIBIENDO el valor anterior.

    Asi se comporta el sistema operacional real: no guarda historia. Correr
    esto, recargar el warehouse y comprobar que las gestiones antiguas siguen
    apuntando a la oficina correcta es la prueba de que el SCD tipo 2 sirve.
    """
    cambios = [
        ("A-001", "Lima", "Miraflores"),
        ("A-004", "Arequipa", "Cayma"),
    ]
    for id_asesor, region, oficina in cambios:
        cur.execute(
            "UPDATE operacional.personal "
            "SET region = %s, oficina = %s, actualizado_en = now() "
            "WHERE id_asesor = %s RETURNING nombre",
            (region, oficina, id_asesor))
        fila = cur.fetchone()
        if fila:
            print(f"  {id_asesor} {fila[0]} -> {oficina} ({region})")


def main():
    global N_LEADS

    ap = argparse.ArgumentParser()
    ap.add_argument("--traslados", action="store_true",
                    help="solo mover asesores de oficina, sin recargar")
    ap.add_argument("--leads", type=int, default=N_LEADS,
                    help="cuantos leads generar (por omision 600). "
                         "Usa un valor alto para el laboratorio de rendimiento.")
    args = ap.parse_args()
    N_LEADS = args.leads

    with conectar() as con, con.cursor() as cur:
        if args.traslados:
            print("Trasladando asesores (el origen pierde la historia):")
            trasladar(cur)
        else:
            cargar(cur)
        con.commit()
    print("Listo.")


if __name__ == "__main__":
    main()
