-- =====================================================================
-- 09 · DICCIONARIO DE DATOS
-- =====================================================================
-- El diccionario no se escribe en un documento aparte: se escribe EN LA
-- BASE con COMMENT ON, y el documento se genera desde ahi.
--
-- Motivo: un diccionario en Word se desactualiza la primera semana. Uno
-- que vive en los metadatos se actualiza cuando cambia la tabla, lo lee
-- Power BI, lo muestra pgAdmin y lo consulta cualquiera con una query.
--
-- Regla al escribir una descripcion: no repitas el nombre de la columna.
-- "oficina: la oficina" no sirve. Di que significa para el negocio.
-- =====================================================================

-- ---------------------------------------------------------------------
-- TABLAS
-- ---------------------------------------------------------------------
COMMENT ON SCHEMA dw IS 'Warehouse dimensional. Es lo unico que deberia consultar un reporte.';
COMMENT ON SCHEMA staging IS 'Copia cruda del origen. Zona de paso, no se consulta para reportes.';
COMMENT ON SCHEMA operacional IS 'Simulacion del sistema transaccional. Origen de todo.';

COMMENT ON TABLE dw.dim_tiempo IS
  'Calendario del 2025 al 2028. No viene del origen: se genera. Permite agrupar por mes, trimestre o dia habil sin calcularlo en cada consulta.';
COMMENT ON TABLE dw.dim_asesor IS
  'Personal de ventanilla con historia (SCD tipo 2). Una persona puede tener varias filas: una por cada periodo en que sus atributos se mantuvieron iguales.';
COMMENT ON TABLE dw.dim_cliente IS
  'Cliente con credito pre-aprobado. SCD tipo 1: los datos de contacto se sobrescriben porque solo interesa el valor actual.';
COMMENT ON TABLE dw.dim_producto IS 'Catalogo de productos crediticios.';
COMMENT ON TABLE dw.dim_oficina IS 'Catalogo de agencias, con su region.';
COMMENT ON TABLE dw.fact_gestion IS
  'Grano: una fila por contacto con el cliente. Responde cuantas gestiones, de que tipo y con que resultado.';
COMMENT ON TABLE dw.fact_desembolso IS
  'Grano: una fila por credito desembolsado. Separado de fact_gestion porque tiene otro grano: mezclarlos duplicaria el dinero.';

-- ---------------------------------------------------------------------
-- DIM TIEMPO
-- ---------------------------------------------------------------------
COMMENT ON COLUMN dw.dim_tiempo.sk_tiempo     IS 'Llave con forma AAAAMMDD. Unica llave del modelo con significado: hace legible el hecho sin unir.';
COMMENT ON COLUMN dw.dim_tiempo.fecha         IS 'La fecha como tal.';
COMMENT ON COLUMN dw.dim_tiempo.anio_mes      IS 'Periodo en formato AAAA-MM. Es por donde el negocio agrupa casi siempre.';
COMMENT ON COLUMN dw.dim_tiempo.trimestre     IS 'Trimestre calendario, del 1 al 4.';
COMMENT ON COLUMN dw.dim_tiempo.dia_semana    IS 'Dia de la semana segun ISO: 1 lunes, 7 domingo.';
COMMENT ON COLUMN dw.dim_tiempo.es_fin_semana IS 'Verdadero en sabado y domingo. Sirve para comparar productividad de dias habiles.';

-- ---------------------------------------------------------------------
-- DIM ASESOR
-- ---------------------------------------------------------------------
COMMENT ON COLUMN dw.dim_asesor.sk_asesor IS 'Llave sustituta. Identifica ESTA VERSION del asesor, no a la persona. Es a la que apunta el hecho.';
COMMENT ON COLUMN dw.dim_asesor.id_asesor IS 'Llave natural del sistema de origen. Identifica a la persona y se repite entre versiones.';
COMMENT ON COLUMN dw.dim_asesor.region    IS 'Region a la que pertenecia su oficina en ese periodo.';
COMMENT ON COLUMN dw.dim_asesor.oficina   IS 'Agencia donde trabajaba en ese periodo. Si se traslada, nace una version nueva.';
COMMENT ON COLUMN dw.dim_asesor.cargo     IS 'Asesor de ventanilla o Jefe de agencia.';
COMMENT ON COLUMN dw.dim_asesor.estado    IS 'Activo o Cesado al momento de la ultima carga.';
COMMENT ON COLUMN dw.dim_asesor.desde     IS 'Primer dia en que esta version estuvo vigente. En la carga inicial es 1900-01-01, para que los hechos anteriores encuentren su version.';
COMMENT ON COLUMN dw.dim_asesor.hasta     IS 'Ultimo dia de vigencia. 9999-12-31 en la version actual, para que las comparaciones de rango no necesiten tratar nulos.';
COMMENT ON COLUMN dw.dim_asesor.vigente   IS 'Verdadero en la version actual. Hay una sola por persona, garantizada por indice unico parcial.';
COMMENT ON COLUMN dw.dim_asesor._hash     IS 'md5 de los atributos vigilados. Si cambia, nace una version nueva. Evita comparar columna por columna.';

-- ---------------------------------------------------------------------
-- DIM CLIENTE
-- ---------------------------------------------------------------------
COMMENT ON COLUMN dw.dim_cliente.sk_cliente     IS 'Llave sustituta.';
COMMENT ON COLUMN dw.dim_cliente.id_lead        IS 'Llave natural del lead en el sistema de origen.';
COMMENT ON COLUMN dw.dim_cliente.documento      IS 'Documento de identidad. Dato personal: en produccion iria enmascarado para quien no sea de riesgos.';
COMMENT ON COLUMN dw.dim_cliente.telefono       IS 'Dato personal, mismo criterio que el documento.';
COMMENT ON COLUMN dw.dim_cliente.distrito       IS 'Distrito de residencia declarado.';
COMMENT ON COLUMN dw.dim_cliente.canal          IS 'Por donde entro el lead: campana telefonica, referido, web, visita en campo o base de BI.';
COMMENT ON COLUMN dw.dim_cliente.score_riesgo   IS 'Puntaje crediticio de 300 a 850 que entrega el area de riesgos.';
COMMENT ON COLUMN dw.dim_cliente.tramo_score    IS 'Banda del score, de A a E. Se calcula al cargar para que cada reporte no invente su propio corte.';
COMMENT ON COLUMN dw.dim_cliente.prioridad      IS 'Orden de atencion sugerido por riesgos: 1 el mas propenso a desembolsar, 5 el menos.';

-- ---------------------------------------------------------------------
-- DIM PRODUCTO Y OFICINA
-- ---------------------------------------------------------------------
COMMENT ON COLUMN dw.dim_producto.producto IS 'Nombre comercial del producto crediticio.';
COMMENT ON COLUMN dw.dim_producto.familia  IS 'Agrupacion derivada: Empresarial o Personal. Se calcula al cargar.';
COMMENT ON COLUMN dw.dim_oficina.oficina   IS 'Nombre de la agencia.';
COMMENT ON COLUMN dw.dim_oficina.region    IS 'Region a la que pertenece la agencia.';

-- ---------------------------------------------------------------------
-- FACT GESTION
-- ---------------------------------------------------------------------
COMMENT ON COLUMN dw.fact_gestion.id_gestion     IS 'Dimension degenerada: el identificador de la gestion en el origen. Permite rastrear una fila hasta el sistema transaccional.';
COMMENT ON COLUMN dw.fact_gestion.sk_oficina     IS 'Oficina del asesor EN LA FECHA DE LA GESTION, tomada de la version vigente del SCD tipo 2. No es la oficina actual.';
COMMENT ON COLUMN dw.fact_gestion.resultado      IS 'Como termino el contacto: No contesta, Contactado, Interesado, Rechazado o Desembolsado.';
COMMENT ON COLUMN dw.fact_gestion.canal_contacto IS 'Por donde se contacto: Llamada, WhatsApp o Presencial.';
COMMENT ON COLUMN dw.fact_gestion.gestiones      IS 'Siempre 1. Permite SUM(gestiones) en vez de COUNT(*), que es lo que componen bien las medidas de BI.';
COMMENT ON COLUMN dw.fact_gestion.duracion_seg   IS 'Duracion del contacto en segundos. Metrica aditiva.';
COMMENT ON COLUMN dw.fact_gestion.es_desembolso  IS 'Vale 1 si esta gestion cerro con desembolso. Sumarla da la cantidad de cierres.';
COMMENT ON COLUMN dw.fact_gestion.es_rechazo     IS 'Vale 1 si el cliente rechazo la oferta.';
COMMENT ON COLUMN dw.fact_gestion.es_contacto    IS 'Vale 1 si hubo contacto efectivo, es decir cualquier resultado distinto de No contesta.';

-- ---------------------------------------------------------------------
-- FACT DESEMBOLSO
-- ---------------------------------------------------------------------
COMMENT ON COLUMN dw.fact_desembolso.id_desembolso  IS 'Dimension degenerada: identificador del desembolso en el origen.';
COMMENT ON COLUMN dw.fact_desembolso.moneda         IS 'PEN o USD, tal como se desembolso.';
COMMENT ON COLUMN dw.fact_desembolso.desembolsos    IS 'Siempre 1. Mismo criterio que gestiones.';
COMMENT ON COLUMN dw.fact_desembolso.monto          IS 'Monto en la moneda original. No sumar entre monedas distintas.';
COMMENT ON COLUMN dw.fact_desembolso.monto_pen      IS 'Monto llevado a soles al cargar. Es el que se suma. Evita que cada reporte use su propio tipo de cambio.';
COMMENT ON COLUMN dw.fact_desembolso.monto_aprobado IS 'Cuanto le habia aprobado riesgos. Comparado con monto da la tasa de utilizacion.';
COMMENT ON COLUMN dw.fact_desembolso.plazo_meses    IS 'Plazo pactado, de 6 a 48 meses.';
COMMENT ON COLUMN dw.fact_desembolso.tasa_anual     IS 'Tasa efectiva anual en porcentaje. Metrica NO aditiva: promediarla sin ponderar por monto da un numero falso.';

SELECT count(*) AS columnas_documentadas
FROM information_schema.columns c
JOIN pg_class t ON t.relname = c.table_name
JOIN pg_namespace n ON n.oid = t.relnamespace AND n.nspname = c.table_schema
WHERE c.table_schema = 'dw'
  AND col_description(t.oid, c.ordinal_position) IS NOT NULL;

-- ---------------------------------------------------------------------
-- COLUMNAS RESTANTES
-- ---------------------------------------------------------------------
-- Un diccionario con huecos no es un diccionario: la columna sin describir
-- es justo la que alguien va a interpretar mal.
-- ---------------------------------------------------------------------
DO $$
DECLARE r RECORD;
BEGIN
  -- columnas tecnicas, iguales en toda tabla del warehouse
  FOR r IN SELECT c.relname AS t FROM pg_class c
           JOIN pg_namespace n ON n.oid=c.relnamespace
           JOIN pg_attribute a ON a.attrelid=c.oid AND a.attname='_cargado_en'
                              AND a.attnum>0 AND NOT a.attisdropped
           WHERE n.nspname='dw' AND c.relkind='r'
  LOOP
    EXECUTE format(
      'COMMENT ON COLUMN dw.%I._cargado_en IS %L', r.t,
      'Momento de la ultima carga que escribio esta fila. Columna tecnica de auditoria.');
  END LOOP;
END $$;

COMMENT ON COLUMN dw.dim_asesor.nombre        IS 'Nombre completo del asesor en ese periodo. Si se corrige el nombre nace una version nueva, igual que con la oficina.';
COMMENT ON COLUMN dw.dim_asesor.puesto        IS 'Ventanilla asignada dentro de la agencia, de 1 a 5.';
COMMENT ON COLUMN dw.dim_cliente.nombre_cliente IS 'Nombre completo declarado por el cliente.';
COMMENT ON COLUMN dw.dim_cliente._hash        IS 'md5 de los atributos vigilados. Si cambia, la fila se sobrescribe (SCD tipo 1).';
COMMENT ON COLUMN dw.dim_oficina.sk_oficina   IS 'Llave sustituta de la agencia.';
COMMENT ON COLUMN dw.dim_producto.sk_producto IS 'Llave sustituta del producto.';

COMMENT ON COLUMN dw.dim_tiempo.anio       IS 'Anio calendario.';
COMMENT ON COLUMN dw.dim_tiempo.mes        IS 'Numero de mes, de 1 a 12.';
COMMENT ON COLUMN dw.dim_tiempo.nombre_mes IS 'Nombre del mes en espanol, para mostrar en reportes.';
COMMENT ON COLUMN dw.dim_tiempo.dia        IS 'Dia del mes.';
COMMENT ON COLUMN dw.dim_tiempo.nombre_dia IS 'Nombre del dia en espanol.';

COMMENT ON COLUMN dw.fact_gestion.sk_gestion  IS 'Llave sustituta de la fila del hecho. No tiene significado de negocio.';
COMMENT ON COLUMN dw.fact_gestion.sk_tiempo   IS 'Fecha en que se registro la gestion.';
COMMENT ON COLUMN dw.fact_gestion.sk_cliente  IS 'Cliente contactado.';
COMMENT ON COLUMN dw.fact_gestion.sk_asesor   IS 'Version del asesor vigente EN LA FECHA DE LA GESTION, no la actual.';
COMMENT ON COLUMN dw.fact_gestion.sk_producto IS 'Producto que tenia pre-aprobado el cliente.';

COMMENT ON COLUMN dw.fact_desembolso.sk_desembolso IS 'Llave sustituta de la fila del hecho.';
COMMENT ON COLUMN dw.fact_desembolso.sk_tiempo     IS 'Fecha del desembolso.';
COMMENT ON COLUMN dw.fact_desembolso.sk_cliente    IS 'Cliente que recibio el credito.';
COMMENT ON COLUMN dw.fact_desembolso.sk_asesor     IS 'Version del asesor vigente EN LA FECHA DEL DESEMBOLSO.';
COMMENT ON COLUMN dw.fact_desembolso.sk_producto   IS 'Producto desembolsado.';
COMMENT ON COLUMN dw.fact_desembolso.sk_oficina    IS 'Agencia del asesor en la fecha del desembolso.';

-- Staging: una linea por tabla. Es zona de paso, no se documenta columna
-- por columna porque es copia literal del origen.
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT c.relname AS t FROM pg_class c
           JOIN pg_namespace n ON n.oid=c.relnamespace
           WHERE n.nspname='staging' AND c.relkind='r' AND c.relname LIKE 'stg_%'
  LOOP
    EXECUTE format('COMMENT ON TABLE staging.%I IS %L', r.t,
      'Copia cruda de operacional.' || replace(r.t,'stg_','') ||
      '. Mismas columnas que el origen, mas _cargado_en, _lote y _origen.');
    EXECUTE format('COMMENT ON COLUMN staging.%I._cargado_en IS %L', r.t,
      'Momento en que la fila entro a staging.');
    EXECUTE format('COMMENT ON COLUMN staging.%I._lote IS %L', r.t,
      'Ejecucion que trajo la fila. Enlaza con staging.control_carga.');
    EXECUTE format('COMMENT ON COLUMN staging.%I._origen IS %L', r.t,
      'Tabla del sistema fuente de la que proviene.');
  END LOOP;
END $$;
