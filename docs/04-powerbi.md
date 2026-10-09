# Tablero en Power BI

El objetivo de este paso no es el tablero: es **comprobar que el modelo está bien
hecho**. Si modelaste bien, el reporte sale arrastrando campos. Si cada visual
exige una fórmula rara, el problema está en el modelo, no en Power BI.

---

## 1 · Conectar

**Inicio → Obtener datos → Más → Base de datos → PostgreSQL**

| Campo | Valor |
|---|---|
| Servidor | `localhost:5433` |
| Base de datos | `wh_creditos` |
| Modo de conectividad | **Importar** |

En la siguiente pantalla, pestaña **Base de datos**:

| Campo | Valor |
|---|---|
| Nombre de usuario | `axel` |
| Contraseña | la de `POSTGRES_PASSWORD` en `.env` |

Nivel de conexión: déjalo en `localhost:5433`.

> **Si Power BI pide el proveedor Npgsql:** descárgalo desde
> `github.com/npgsql/npgsql/releases`, instala la versión **4.0.x** marcando
> *Npgsql GAC Installation*, y reinicia Power BI Desktop. Las versiones
> recientes ya lo traen incluido.

**Por qué Importar y no DirectQuery:** son 197.000 filas, caben de sobra en
memoria y las consultas vuelan. DirectQuery se justifica cuando el dato cambia
cada minuto o cuando la tabla no cabe. No es el caso.

---

## 2 · Qué traer

Marca **solo estas siete**:

```
dw.dim_tiempo        1.462
dw.dim_asesor           20
dw.dim_cliente      60.001
dw.dim_producto          6
dw.dim_oficina          10
dw.fact_gestion    197.028
dw.fact_desembolso  12.253
```

**No traigas nada de `staging` ni de `operacional`.** Son zonas internas del
pipeline. Si aparecen en el modelo, alguien las va a usar y va a reportar sobre
datos sin limpiar.

---

## 3 · Revisar las relaciones

Power BI intenta detectarlas solas por nombre de columna. Ve a **Vista de
modelo** y comprueba que estén las diez:

| Desde | Hacia | Cardinalidad | Dirección |
|---|---|---|---|
| `dim_tiempo[sk_tiempo]` | `fact_gestion[sk_tiempo]` | 1 a muchos | Simple |
| `dim_cliente[sk_cliente]` | `fact_gestion[sk_cliente]` | 1 a muchos | Simple |
| `dim_asesor[sk_asesor]` | `fact_gestion[sk_asesor]` | 1 a muchos | Simple |
| `dim_producto[sk_producto]` | `fact_gestion[sk_producto]` | 1 a muchos | Simple |
| `dim_oficina[sk_oficina]` | `fact_gestion[sk_oficina]` | 1 a muchos | Simple |
| *(las mismas cinco)* | `fact_desembolso[...]` | 1 a muchos | Simple |

**Tres reglas:**

- **Dirección simple**, nunca bidireccional. La bidireccional crea caminos
  ambiguos y resultados que nadie puede explicar.
- **El filtro va de la dimensión al hecho**, nunca al revés.
- **Ninguna relación entre los dos hechos.** Se comunican a través de las
  dimensiones que comparten. Esto es una *constelación*, y es correcto.

### Marcar la tabla de fechas

Selecciona `dim_tiempo` → **Herramientas de tabla → Marcar como tabla de
fechas** → columna `fecha`.

Sin esto, las funciones de inteligencia de tiempo (acumulado del año,
comparación contra el año anterior) no funcionan bien.

---

## 4 · Limpiar la vista

En la vista de informe, **oculta** lo que nadie debe arrastrar:

- Todas las columnas `sk_*` de los hechos y las dimensiones
- `_hash`, `_cargado_en`, `_lote`, `_origen`
- `id_gestion`, `id_desembolso` (solo sirven para rastrear)

Un modelo con treinta campos visibles se usa. Uno con noventa, no.

---

## 5 · Las medidas

Créalas sobre `fact_gestion` o en una tabla de medidas aparte.

### Volumen

```dax
Gestiones = SUM(fact_gestion[gestiones])

Contactos efectivos = SUM(fact_gestion[es_contacto])

Cierres = SUM(fact_gestion[es_desembolso])

Rechazos = SUM(fact_gestion[es_rechazo])
```

### Ratios

```dax
Tasa de cierre = DIVIDE([Cierres], [Gestiones])

Contactabilidad = DIVIDE([Contactos efectivos], [Gestiones])

Gestiones por cierre = DIVIDE([Gestiones], [Cierres])
```

> `DIVIDE` y no `/`. Si el denominador es cero, `DIVIDE` devuelve vacío en vez
> de un error que rompe el visual entero.

### Dinero

```dax
Monto colocado = SUM(fact_desembolso[monto_pen])

Desembolsos = SUM(fact_desembolso[desembolsos])

Ticket promedio = DIVIDE([Monto colocado], [Desembolsos])

Monto aprobado = SUM(fact_desembolso[monto_aprobado])

Tasa de utilizacion = DIVIDE([Monto colocado], [Monto aprobado])
```

### Tiempo

```dax
Monto colocado YTD =
TOTALYTD([Monto colocado], dim_tiempo[fecha])

Monto mes anterior =
CALCULATE([Monto colocado], DATEADD(dim_tiempo[fecha], -1, MONTH))

Variacion vs mes anterior =
DIVIDE([Monto colocado] - [Monto mes anterior], [Monto mes anterior])
```

### Formato

| Medida | Formato |
|---|---|
| Tasas y variaciones | Porcentaje, 1 decimal |
| Montos | Moneda, sin decimales, separador de miles |
| Conteos | Número entero |

---

## 6 · El tablero

Tres páginas bastan.

### Página 1 · Resumen

| Visual | Campos |
|---|---|
| Tarjetas | Gestiones · Cierres · Tasa de cierre · Monto colocado |
| Columnas | `dim_tiempo[anio_mes]` por Monto colocado |
| Barras | `dim_oficina[oficina]` por Tasa de cierre |
| Anillo | `dim_cliente[tramo_score]` por Cierres |
| Segmentaciones | Periodo, Región, Producto |

### Página 2 · Productividad

| Visual | Campos |
|---|---|
| Tabla | Asesor · Gestiones · Contactabilidad · Tasa de cierre · Monto colocado |
| Dispersión | Gestiones (X) contra Tasa de cierre (Y), punto = asesor |
| Columnas apiladas | `dim_tiempo[nombre_dia]` por Gestiones, dividido por `resultado` |

El gráfico de dispersión es el que vale: separa a quien gestiona mucho con poca
efectividad de quien gestiona poco pero cierra.

### Página 3 · Colocación

| Visual | Campos |
|---|---|
| Columnas | `dim_producto[producto]` por Monto colocado |
| Medidor | Tasa de utilización |
| Líneas | Monto colocado y Monto mes anterior por `anio_mes` |
| Tabla | Producto · Desembolsos · Ticket promedio · Plazo promedio |

---

## 7 · La prueba del modelo

Construye este visual y mira el resultado:

> **Barras:** `dim_oficina[oficina]` por **Gestiones**

Las cifras deben coincidir con esto, que es la atribución histórica correcta:

| Oficina | Gestiones |
|---|---|
| San Isidro | las que se hicieron **estando** en San Isidro |
| Miraflores | las que se hicieron **estando** en Miraflores |

Si Power BI mostrara todas las gestiones de un asesor trasladado en su oficina
actual, el modelo estaría mal. No lo hace, porque el hecho apunta a la **versión
histórica** del asesor y de ahí sale la oficina.

**Eso es lo que este proyecto demuestra, y es lo que se enseña en el tablero.**

---

## 8 · Guardar

Guarda como `powerbi/warehouse-creditos.pbix`.

El `.pbix` está en `.gitignore`: lleva los datos adentro y pesa decenas de
megas. Lo que se versiona es el modelo —el SQL— no el archivo del reporte.
Para el portafolio, exporta **capturas** a `docs/` o publica a Power BI Service
y comparte el enlace.
