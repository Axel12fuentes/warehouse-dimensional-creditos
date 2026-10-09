# Cuaderno de errores

Lo que falló mientras construía esto, por qué, y cómo lo resolví.

---

## 1 · `MERGE command cannot affect row a second time`

**Cuándo.** Al cargar los hechos después de regenerar el origen con 60.000
leads en lugar de 600.

**Qué decía.**

```
ERROR:  MERGE command cannot affect row a second time
HINT:   Ensure that not more than one source row matches any one target row.
```

**La causa, que no era la que parecía.** El mensaje apunta al `MERGE`, pero el
problema estaba dos pasos antes, en la carga incremental de staging.

La marca de agua se guardaba con `clock_timestamp()` — la hora del reloj — y la
ventana se filtraba contra `registrado_en`, que es la **fecha de negocio** del
dato. Mientras el origen solo crece, las dos avanzan juntas y nadie lo nota.

Al regenerar el origen, los datos nuevos nacieron con fechas de enero a
setiembre: **anteriores** a la última marca de agua. La incremental los
descartó por viejos y staging se quedó con las filas de la corrida anterior.

Encima, el `TRUNCATE ... RESTART IDENTITY` del generador reinició los
contadores. Los desembolsos nuevos empezaron otra vez en 1, chocando con los
`id_desembolso` que seguían en staging. Dos filas de origen con la misma
llave: eso es lo que el `MERGE` se negó a procesar.

**La corrección.** Dos cambios:

1. La marca de agua ahora se toma del **máximo del origen**, no del reloj:

   ```sql
   EXECUTE format('SELECT max(registrado_en) FROM operacional.%I', p_tabla)
     INTO v_hasta;
   ```

   Es tiempo de negocio contra tiempo de negocio. Coherente.

2. Se agregó `staging.reiniciar()`, que el generador llama en toda carga
   completa. **Reiniciar el origen obliga a reiniciar staging**: las marcas de
   agua apuntan a un pasado que ya no existe.

**Lo que aprendí.** El error apareció donde no estaba la causa. Y solo
apareció al cambiar la escala: con 600 leads nunca se habría visto.

---

## 2 · Dos reglas de libro que la medición desmintió

Medido sobre 197.028 filas, no sobre un ejemplo de manual.

### «Un índice compuesto sobre (A, B) no sirve para filtrar solo por B»

Falso, o al menos mal dicho. Filtrando solo por la segunda columna:

| | Plan | Tiempo |
|---|---|---|
| Sin índice útil | Parallel Seq Scan | 9,95 ms |
| Con el compuesto (A, B) | Index Only Scan | **2,15 ms** |
| Con un índice dedicado (B) | Index Only Scan | 1,66 ms |

Sin la primera columna el motor no puede **saltar** directo al valor, pero sí
puede recorrer el índice entero — que es mucho más chico que la tabla. Y si el
índice cubre lo que la consulta pide, responde sin tocarla.

**Dicho bien:** el compuesto ayuda a la segunda columna, pero menos que un
índice dedicado. Es subóptimo, no inútil.

### «Si el filtro deja pasar más del 20% de las filas, el índice no se usa»

También depende. Con un filtro que deja pasar el 33%:

| Consulta | Plan | Tiempo |
|---|---|---|
| Solo contar filas | Index Only Scan | 4,85 ms |
| Pidiendo otras columnas | Bitmap Heap Scan | 24,12 ms |

Lo que decide no es solo la selectividad: es si el índice **cubre** la
consulta. Cuando no tiene que ir a la tabla, el índice conviene incluso con
baja selectividad.

---

## 3 · La primera carga del SCD tipo 2 con fecha de hoy

**El síntoma que habría tenido.** Los hechos anteriores a hoy no encuentran
ninguna versión vigente y caen todos en la fila «Desconocido».

**Por qué.** Si en la primera carga las versiones nacen con
`desde = current_date`, la condición del hecho

```sql
AND g.registrado_en::date BETWEEN a.desde AND a.hasta
```

no se cumple para nada anterior.

**La corrección.** En la primera carga las versiones nacen con `1900-01-01`:

```sql
CASE WHEN v_primera THEN DATE '1900-01-01' ELSE current_date END
```

Lo detecté antes de que ocurriera, pero vale anotarlo: es el error más común
al implementar un SCD tipo 2 por primera vez.

---

## 4 · `pg_cron` no viene en la imagen oficial de Postgres

Poner `shared_preload_libraries=pg_cron` en una imagen que no lo tiene hace
que el servidor **no arranque**. Hubo que construir una imagen propia:

```dockerfile
FROM postgres:16
RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-16-cron \
 && rm -rf /var/lib/apt/lists/*
```

Además, `alpine` no trae el paquete: hay que usar la variante Debian.

---

## 5 · SCD tipo 2: el cambio del mismo día dejaba un rango imposible

**El síntoma.**

```
A-001  Miraflores  desde 2026-10-09  hasta 2026-10-08
```

La fecha de fin es **anterior** a la de inicio. Una versión que nunca estuvo
vigente ni un día.

**Por qué.** El paso que cierra una versión escribe `hasta = current_date - 1`.
Eso es correcto cuando la versión lleva tiempo abierta. Pero si la versión
**nació hoy** y el atributo vuelve a cambiar hoy, el resultado es un rango
vacío. Pasó al regenerar el origen y volver a trasladar a los mismos asesores
el mismo día.

**Por qué importa.** Ninguna fila de hechos puede caer dentro de un rango
imposible, así que esas filas apuntarían a «Desconocido». Con pocos registros
no se nota; con 197.000 sí.

**La corrección.** Un paso previo que trata el cambio del mismo día como lo
que es — una **corrección**, no una versión nueva — y actualiza la fila en el
sitio:

```sql
UPDATE dw.dim_asesor d
   SET oficina = o.oficina, ..., _hash = o.h
  FROM origen o
 WHERE d.id_asesor = o.id_asesor
   AND d.vigente
   AND d.desde = current_date          -- nacio hoy
   AND d._hash IS DISTINCT FROM o.h;
```

Más un barrido que elimina los rangos imposibles que hayan quedado, siempre
que ningún hecho los referencie.

**Lo que aprendí.** El SCD tipo 2 asume que el tiempo avanza entre cargas. En
desarrollo, donde se recarga varias veces al día, esa suposición se rompe.

---

## 6 · Una medida no puede llamarse igual que una columna

Al escribir las medidas DAX en el TMDL del proyecto `.pbip`, Power BI se negó
a abrir:

```
The 'Gestiones' measure cannot be created because a column with the
same name already exists.
```

La tabla tiene la columna `gestiones` y la medida se llamaba `Gestiones`.
Power BI no distingue mayúsculas. Se renombraron a `Total gestiones` y
`Total desembolsos`.

**Y un segundo error encima:** el script borraba las medidas por su nombre
antes de reescribirlas, pero al renombrarlas buscaba los nombres **nuevos**,
no encontraba los viejos, y quedaron las dos versiones conviviendo. Se agregó
una lista de nombres obsoletos que también se purgan.

Es la misma clase de error que el de la marca de agua: solo aparece **la
segunda vez** que se corre el proceso.
