# Diccionario de datos

> Generado automaticamente desde los metadatos de la base.
> No se edita a mano: se editan los `COMMENT ON` en [`sql/09_diccionario.sql`](../sql/09_diccionario.sql) y se vuelve a correr
> `python scripts/generar_diccionario.py`.

Ultima generacion: 2026-10-09

## Tablas

| Esquema | Tabla | Filas aprox. | Tamano | Que contiene |
|---|---|---:|---:|---|
| `dw` | [`dim_asesor`](#dwdimasesor) | 20 | 64 kB | Personal de ventanilla con historia (SCD tipo 2). Una persona puede tener varias filas: una por cada periodo en que sus atributos se mantuvieron iguales. |
| `dw` | [`dim_cliente`](#dwdimcliente) | 60,001 | 17 MB | Cliente con credito pre-aprobado. SCD tipo 1: los datos de contacto se sobrescriben porque solo interesa el valor actual. |
| `dw` | [`dim_oficina`](#dwdimoficina) | 10 | 40 kB | Catalogo de agencias, con su region. |
| `dw` | [`dim_producto`](#dwdimproducto) | 6 | 40 kB | Catalogo de productos crediticios. |
| `dw` | [`dim_tiempo`](#dwdimtiempo) | 1,462 | 240 kB | Calendario del 2025 al 2028. No viene del origen: se genera. Permite agrupar por mes, trimestre o dia habil sin calcularlo en cada consulta. |
| `dw` | [`fact_desembolso`](#dwfactdesembolso) | 12,253 | 2528 kB | Grano: una fila por credito desembolsado. Separado de fact_gestion porque tiene otro grano: mezclarlos duplicaria el dinero. |
| `dw` | [`fact_gestion`](#dwfactgestion) | 197,028 | 40 MB | Grano: una fila por contacto con el cliente. Responde cuantas gestiones, de que tipo y con que resultado. |
| `staging` | [`control_carga`](#stagingcontrolcarga) | 6 | 48 kB | Una fila por ejecucion de carga. La marca de agua indica hasta que momento se trajo el dato. |
| `staging` | [`stg_asignaciones`](#stagingstgasignaciones) | 60,000 | 5960 kB | Copia cruda de operacional.asignaciones. Mismas columnas que el origen, mas _cargado_en, _lote y _origen. |
| `staging` | [`stg_desembolsos`](#stagingstgdesembolsos) | 12,253 | 1736 kB | Copia cruda de operacional.desembolsos. Mismas columnas que el origen, mas _cargado_en, _lote y _origen. |
| `staging` | [`stg_gestiones`](#stagingstggestiones) | 197,028 | 27 MB | Copia cruda de operacional.gestiones. Mismas columnas que el origen, mas _cargado_en, _lote y _origen. |
| `staging` | [`stg_leads`](#stagingstgleads) | 60,000 | 12 MB | Copia cruda de operacional.leads. Mismas columnas que el origen, mas _cargado_en, _lote y _origen. |
| `staging` | [`stg_personal`](#stagingstgpersonal) | 15 | 8192 bytes | Copia cruda de operacional.personal. Mismas columnas que el origen, mas _cargado_en, _lote y _origen. |

---

## dw.dim_asesor

Personal de ventanilla con historia (SCD tipo 2). Una persona puede tener varias filas: una por cada periodo en que sus atributos se mantuvieron iguales.

*20 filas aproximadas · 64 kB*

| Columna | Tipo | Nulo | Llave | Descripcion |
|---|---|:-:|---|---|
| `sk_asesor` | bigint | no | PK | Llave sustituta. Identifica ESTA VERSION del asesor, no a la persona. Es a la que apunta el hecho. |
| `id_asesor` | character varying(10) | no |  | Llave natural del sistema de origen. Identifica a la persona y se repite entre versiones. |
| `nombre` | character varying(120) | si |  | Nombre completo del asesor en ese periodo. Si se corrige el nombre nace una version nueva, igual que con la oficina. |
| `region` | character varying(60) | si |  | Region a la que pertenecia su oficina en ese periodo. |
| `oficina` | character varying(60) | si |  | Agencia donde trabajaba en ese periodo. Si se traslada, nace una version nueva. |
| `puesto` | character varying(40) | si |  | Ventanilla asignada dentro de la agencia, de 1 a 5. |
| `cargo` | character varying(40) | si |  | Asesor de ventanilla o Jefe de agencia. |
| `estado` | character varying(20) | si |  | Activo o Cesado al momento de la ultima carga. |
| `desde` | date | no |  | Primer dia en que esta version estuvo vigente. En la carga inicial es 1900-01-01, para que los hechos anteriores encuentren su version. |
| `hasta` | date | no |  | Ultimo dia de vigencia. 9999-12-31 en la version actual, para que las comparaciones de rango no necesiten tratar nulos. |
| `vigente` | boolean | no |  | Verdadero en la version actual. Hay una sola por persona, garantizada por indice unico parcial. |
| `_hash` | text | si |  | md5 de los atributos vigilados. Si cambia, nace una version nueva. Evita comparar columna por columna. |
| `_cargado_en` | timestamp without time zone | no |  | Momento de la ultima carga que escribio esta fila. Columna tecnica de auditoria. |

---

## dw.dim_cliente

Cliente con credito pre-aprobado. SCD tipo 1: los datos de contacto se sobrescriben porque solo interesa el valor actual.

*60,001 filas aproximadas · 17 MB*

| Columna | Tipo | Nulo | Llave | Descripcion |
|---|---|:-:|---|---|
| `sk_cliente` | bigint | no | PK | Llave sustituta. |
| `id_lead` | character varying(20) | no |  | Llave natural del lead en el sistema de origen. |
| `nombre_cliente` | character varying(120) | si |  | Nombre completo declarado por el cliente. |
| `documento` | character varying(15) | si |  | Documento de identidad. Dato personal: en produccion iria enmascarado para quien no sea de riesgos. |
| `telefono` | character varying(15) | si |  | Dato personal, mismo criterio que el documento. |
| `distrito` | character varying(60) | si |  | Distrito de residencia declarado. |
| `canal` | character varying(40) | si |  | Por donde entro el lead: campana telefonica, referido, web, visita en campo o base de BI. |
| `score_riesgo` | integer | si |  | Puntaje crediticio de 300 a 850 que entrega el area de riesgos. |
| `tramo_score` | character varying(20) | si |  | Banda del score, de A a E. Se calcula al cargar para que cada reporte no invente su propio corte. |
| `prioridad` | smallint | si |  | Orden de atencion sugerido por riesgos: 1 el mas propenso a desembolsar, 5 el menos. |
| `_hash` | text | si |  | md5 de los atributos vigilados. Si cambia, la fila se sobrescribe (SCD tipo 1). |
| `_cargado_en` | timestamp without time zone | no |  | Momento de la ultima carga que escribio esta fila. Columna tecnica de auditoria. |

---

## dw.dim_oficina

Catalogo de agencias, con su region.

*10 filas aproximadas · 40 kB*

| Columna | Tipo | Nulo | Llave | Descripcion |
|---|---|:-:|---|---|
| `sk_oficina` | bigint | no | PK | Llave sustituta de la agencia. |
| `oficina` | character varying(60) | no |  | Nombre de la agencia. |
| `region` | character varying(60) | no |  | Region a la que pertenece la agencia. |
| `_cargado_en` | timestamp without time zone | no |  | Momento de la ultima carga que escribio esta fila. Columna tecnica de auditoria. |

---

## dw.dim_producto

Catalogo de productos crediticios.

*6 filas aproximadas · 40 kB*

| Columna | Tipo | Nulo | Llave | Descripcion |
|---|---|:-:|---|---|
| `sk_producto` | bigint | no | PK | Llave sustituta del producto. |
| `producto` | character varying(60) | no |  | Nombre comercial del producto crediticio. |
| `familia` | character varying(40) | si |  | Agrupacion derivada: Empresarial o Personal. Se calcula al cargar. |
| `_cargado_en` | timestamp without time zone | no |  | Momento de la ultima carga que escribio esta fila. Columna tecnica de auditoria. |

---

## dw.dim_tiempo

Calendario del 2025 al 2028. No viene del origen: se genera. Permite agrupar por mes, trimestre o dia habil sin calcularlo en cada consulta.

*1,462 filas aproximadas · 240 kB*

| Columna | Tipo | Nulo | Llave | Descripcion |
|---|---|:-:|---|---|
| `sk_tiempo` | integer | no | PK | Llave con forma AAAAMMDD. Unica llave del modelo con significado: hace legible el hecho sin unir. |
| `fecha` | date | no |  | La fecha como tal. |
| `anio` | smallint | no |  | Anio calendario. |
| `trimestre` | smallint | no |  | Trimestre calendario, del 1 al 4. |
| `mes` | smallint | no |  | Numero de mes, de 1 a 12. |
| `nombre_mes` | character varying(12) | no |  | Nombre del mes en espanol, para mostrar en reportes. |
| `dia` | smallint | no |  | Dia del mes. |
| `dia_semana` | smallint | no |  | Dia de la semana segun ISO: 1 lunes, 7 domingo. |
| `nombre_dia` | character varying(12) | no |  | Nombre del dia en espanol. |
| `es_fin_semana` | boolean | no |  | Verdadero en sabado y domingo. Sirve para comparar productividad de dias habiles. |
| `anio_mes` | character(7) | no |  | Periodo en formato AAAA-MM. Es por donde el negocio agrupa casi siempre. |

---

## dw.fact_desembolso

Grano: una fila por credito desembolsado. Separado de fact_gestion porque tiene otro grano: mezclarlos duplicaria el dinero.

*12,253 filas aproximadas · 2528 kB*

| Columna | Tipo | Nulo | Llave | Descripcion |
|---|---|:-:|---|---|
| `sk_desembolso` | bigint | no | PK | Llave sustituta de la fila del hecho. |
| `id_desembolso` | bigint | no |  | Dimension degenerada: identificador del desembolso en el origen. |
| `sk_tiempo` | integer | no | FK a `dim_tiempo` | Fecha del desembolso. |
| `sk_cliente` | bigint | no | FK a `dim_cliente` | Cliente que recibio el credito. |
| `sk_asesor` | bigint | no | FK a `dim_asesor` | Version del asesor vigente EN LA FECHA DEL DESEMBOLSO. |
| `sk_producto` | bigint | no | FK a `dim_producto` | Producto desembolsado. |
| `sk_oficina` | bigint | no | FK a `dim_oficina` | Agencia del asesor en la fecha del desembolso. |
| `moneda` | character(3) | no |  | PEN o USD, tal como se desembolso. |
| `desembolsos` | smallint | no |  | Siempre 1. Mismo criterio que gestiones. |
| `monto` | numeric(12,2) | no |  | Monto en la moneda original. No sumar entre monedas distintas. |
| `monto_pen` | numeric(12,2) | no |  | Monto llevado a soles al cargar. Es el que se suma. Evita que cada reporte use su propio tipo de cambio. |
| `monto_aprobado` | numeric(12,2) | si |  | Cuanto le habia aprobado riesgos. Comparado con monto da la tasa de utilizacion. |
| `plazo_meses` | smallint | si |  | Plazo pactado, de 6 a 48 meses. |
| `tasa_anual` | numeric(5,2) | si |  | Tasa efectiva anual en porcentaje. Metrica NO aditiva: promediarla sin ponderar por monto da un numero falso. |
| `_cargado_en` | timestamp without time zone | no |  | Momento de la ultima carga que escribio esta fila. Columna tecnica de auditoria. |

---

## dw.fact_gestion

Grano: una fila por contacto con el cliente. Responde cuantas gestiones, de que tipo y con que resultado.

*197,028 filas aproximadas · 40 MB*

| Columna | Tipo | Nulo | Llave | Descripcion |
|---|---|:-:|---|---|
| `sk_gestion` | bigint | no | PK | Llave sustituta de la fila del hecho. No tiene significado de negocio. |
| `id_gestion` | bigint | no |  | Dimension degenerada: el identificador de la gestion en el origen. Permite rastrear una fila hasta el sistema transaccional. |
| `sk_tiempo` | integer | no | FK a `dim_tiempo` | Fecha en que se registro la gestion. |
| `sk_cliente` | bigint | no | FK a `dim_cliente` | Cliente contactado. |
| `sk_asesor` | bigint | no | FK a `dim_asesor` | Version del asesor vigente EN LA FECHA DE LA GESTION, no la actual. |
| `sk_producto` | bigint | no | FK a `dim_producto` | Producto que tenia pre-aprobado el cliente. |
| `sk_oficina` | bigint | no | FK a `dim_oficina` | Oficina del asesor EN LA FECHA DE LA GESTION, tomada de la version vigente del SCD tipo 2. No es la oficina actual. |
| `resultado` | character varying(30) | no |  | Como termino el contacto: No contesta, Contactado, Interesado, Rechazado o Desembolsado. |
| `canal_contacto` | character varying(30) | si |  | Por donde se contacto: Llamada, WhatsApp o Presencial. |
| `gestiones` | smallint | no |  | Siempre 1. Permite SUM(gestiones) en vez de COUNT(*), que es lo que componen bien las medidas de BI. |
| `duracion_seg` | integer | si |  | Duracion del contacto en segundos. Metrica aditiva. |
| `es_desembolso` | smallint | no |  | Vale 1 si esta gestion cerro con desembolso. Sumarla da la cantidad de cierres. |
| `es_rechazo` | smallint | no |  | Vale 1 si el cliente rechazo la oferta. |
| `es_contacto` | smallint | no |  | Vale 1 si hubo contacto efectivo, es decir cualquier resultado distinto de No contesta. |
| `_cargado_en` | timestamp without time zone | no |  | Momento de la ultima carga que escribio esta fila. Columna tecnica de auditoria. |

---

## staging.control_carga

Una fila por ejecucion de carga. La marca de agua indica hasta que momento se trajo el dato.

*6 filas aproximadas · 48 kB*

| Columna | Tipo | Nulo | Llave | Descripcion |
|---|---|:-:|---|---|
| `id_control` | bigint | no | PK |  |
| `proceso` | character varying(60) | no |  |  |
| `estrategia` | character varying(20) | no |  |  |
| `marca_agua` | timestamp without time zone | si |  |  |
| `filas` | integer | si |  |  |
| `estado` | character varying(20) | no |  |  |
| `mensaje` | text | si |  |  |
| `inicio` | timestamp without time zone | no |  |  |
| `fin` | timestamp without time zone | si |  |  |

---

## staging.stg_asignaciones

Copia cruda de operacional.asignaciones. Mismas columnas que el origen, mas _cargado_en, _lote y _origen.

*60,000 filas aproximadas · 5960 kB*

| Columna | Tipo | Nulo | Llave | Descripcion |
|---|---|:-:|---|---|
| `id_lead` | character varying(20) | si |  |  |
| `id_asesor` | character varying(10) | si |  |  |
| `asignado_en` | timestamp without time zone | si |  |  |
| `_cargado_en` | timestamp without time zone | no |  | Momento en que la fila entro a staging. |
| `_lote` | bigint | si |  | Ejecucion que trajo la fila. Enlaza con staging.control_carga. |
| `_origen` | character varying(60) | no |  | Tabla del sistema fuente de la que proviene. |

---

## staging.stg_desembolsos

Copia cruda de operacional.desembolsos. Mismas columnas que el origen, mas _cargado_en, _lote y _origen.

*12,253 filas aproximadas · 1736 kB*

| Columna | Tipo | Nulo | Llave | Descripcion |
|---|---|:-:|---|---|
| `id_desembolso` | bigint | si |  |  |
| `id_lead` | character varying(20) | si |  |  |
| `id_asesor` | character varying(10) | si |  |  |
| `fecha` | date | si |  |  |
| `monto` | numeric(12,2) | si |  |  |
| `plazo_meses` | smallint | si |  |  |
| `tasa_anual` | numeric(5,2) | si |  |  |
| `moneda` | character(3) | si |  |  |
| `registrado_en` | timestamp without time zone | si |  |  |
| `_cargado_en` | timestamp without time zone | no |  | Momento en que la fila entro a staging. |
| `_lote` | bigint | si |  | Ejecucion que trajo la fila. Enlaza con staging.control_carga. |
| `_origen` | character varying(60) | no |  | Tabla del sistema fuente de la que proviene. |

---

## staging.stg_gestiones

Copia cruda de operacional.gestiones. Mismas columnas que el origen, mas _cargado_en, _lote y _origen.

*197,028 filas aproximadas · 27 MB*

| Columna | Tipo | Nulo | Llave | Descripcion |
|---|---|:-:|---|---|
| `id_gestion` | bigint | si |  |  |
| `id_lead` | character varying(20) | si |  |  |
| `id_asesor` | character varying(10) | si |  |  |
| `canal_contacto` | character varying(30) | si |  |  |
| `resultado` | character varying(30) | si |  |  |
| `duracion_seg` | integer | si |  |  |
| `comentario` | text | si |  |  |
| `registrado_en` | timestamp without time zone | si |  |  |
| `_cargado_en` | timestamp without time zone | no |  | Momento en que la fila entro a staging. |
| `_lote` | bigint | si |  | Ejecucion que trajo la fila. Enlaza con staging.control_carga. |
| `_origen` | character varying(60) | no |  | Tabla del sistema fuente de la que proviene. |

---

## staging.stg_leads

Copia cruda de operacional.leads. Mismas columnas que el origen, mas _cargado_en, _lote y _origen.

*60,000 filas aproximadas · 12 MB*

| Columna | Tipo | Nulo | Llave | Descripcion |
|---|---|:-:|---|---|
| `id_lead` | character varying(20) | si |  |  |
| `fecha_aprobacion` | date | si |  |  |
| `nombre_cliente` | character varying(120) | si |  |  |
| `documento` | character varying(15) | si |  |  |
| `telefono` | character varying(15) | si |  |  |
| `distrito` | character varying(60) | si |  |  |
| `producto` | character varying(60) | si |  |  |
| `monto_aprobado` | numeric(12,2) | si |  |  |
| `score_riesgo` | integer | si |  |  |
| `prioridad` | smallint | si |  |  |
| `canal` | character varying(40) | si |  |  |
| `region` | character varying(60) | si |  |  |
| `oficina` | character varying(60) | si |  |  |
| `actualizado_en` | timestamp without time zone | si |  |  |
| `_cargado_en` | timestamp without time zone | no |  | Momento en que la fila entro a staging. |
| `_lote` | bigint | si |  | Ejecucion que trajo la fila. Enlaza con staging.control_carga. |
| `_origen` | character varying(60) | no |  | Tabla del sistema fuente de la que proviene. |

---

## staging.stg_personal

Copia cruda de operacional.personal. Mismas columnas que el origen, mas _cargado_en, _lote y _origen.

*15 filas aproximadas · 8192 bytes*

| Columna | Tipo | Nulo | Llave | Descripcion |
|---|---|:-:|---|---|
| `id_asesor` | character varying(10) | si |  |  |
| `nombre` | character varying(120) | si |  |  |
| `region` | character varying(60) | si |  |  |
| `oficina` | character varying(60) | si |  |  |
| `puesto` | character varying(40) | si |  |  |
| `cargo` | character varying(40) | si |  |  |
| `estado` | character varying(20) | si |  |  |
| `actualizado_en` | timestamp without time zone | si |  |  |
| `_cargado_en` | timestamp without time zone | no |  | Momento en que la fila entro a staging. |
| `_lote` | bigint | si |  | Ejecucion que trajo la fila. Enlaza con staging.control_carga. |
| `_origen` | character varying(60) | no |  | Tabla del sistema fuente de la que proviene. |

