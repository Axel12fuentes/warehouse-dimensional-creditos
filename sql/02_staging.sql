-- =====================================================================
-- 02 · CAPA DE STAGING  (esquema: staging)
-- =====================================================================
-- Copia cruda del origen. Tres reglas:
--
--   1. No se aplica NINGUNA regla de negocio aqui. Solo se copia.
--   2. Sin restricciones ni llaves foraneas: si el origen trae basura,
--      queremos verla, no que la carga falle.
--   3. Toda tabla lleva columnas tecnicas de auditoria.
--
-- Existe para poder reprocesar sin volver a molestar a la base
-- operacional, que en produccion esta sirviendo a la operacion.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS staging;

-- ---------------------------------------------------------------------
-- Tabla de control: la bitacora de cada carga y la marca de agua
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.control_carga (
  id_control     BIGSERIAL PRIMARY KEY,
  proceso        VARCHAR(60)  NOT NULL,
  estrategia     VARCHAR(20)  NOT NULL,   -- completa | incremental
  marca_agua     TIMESTAMP,               -- hasta donde se cargo
  filas          INT,
  estado         VARCHAR(20)  NOT NULL,   -- OK | ERROR
  mensaje        TEXT,
  inicio         TIMESTAMP    NOT NULL,
  fin            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_control_proceso
  ON staging.control_carga (proceso, inicio DESC);

COMMENT ON TABLE staging.control_carga IS
  'Una fila por ejecucion de carga. La marca de agua indica hasta que momento se trajo el dato.';

-- ---------------------------------------------------------------------
-- Columnas tecnicas que lleva TODA tabla de staging:
--   _cargado_en  cuando entro a staging
--   _lote        que ejecucion la trajo (enlaza con control_carga)
--   _origen      de que tabla del sistema fuente viene
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS staging.stg_personal;
CREATE TABLE staging.stg_personal (
  id_asesor       VARCHAR(10),
  nombre          VARCHAR(120),
  region          VARCHAR(60),
  oficina         VARCHAR(60),
  puesto          VARCHAR(40),
  cargo           VARCHAR(40),
  estado          VARCHAR(20),
  actualizado_en  TIMESTAMP,
  _cargado_en     TIMESTAMP NOT NULL DEFAULT now(),
  _lote           BIGINT,
  _origen         VARCHAR(60) NOT NULL DEFAULT 'operacional.personal'
);

DROP TABLE IF EXISTS staging.stg_leads;
CREATE TABLE staging.stg_leads (
  id_lead           VARCHAR(20),
  fecha_aprobacion  DATE,
  nombre_cliente    VARCHAR(120),
  documento         VARCHAR(15),
  telefono          VARCHAR(15),
  distrito          VARCHAR(60),
  producto          VARCHAR(60),
  monto_aprobado    NUMERIC(12,2),
  score_riesgo      INT,
  prioridad         SMALLINT,
  canal             VARCHAR(40),
  region            VARCHAR(60),
  oficina           VARCHAR(60),
  actualizado_en    TIMESTAMP,
  _cargado_en       TIMESTAMP NOT NULL DEFAULT now(),
  _lote             BIGINT,
  _origen           VARCHAR(60) NOT NULL DEFAULT 'operacional.leads'
);

DROP TABLE IF EXISTS staging.stg_asignaciones;
CREATE TABLE staging.stg_asignaciones (
  id_lead      VARCHAR(20),
  id_asesor    VARCHAR(10),
  asignado_en  TIMESTAMP,
  _cargado_en  TIMESTAMP NOT NULL DEFAULT now(),
  _lote        BIGINT,
  _origen      VARCHAR(60) NOT NULL DEFAULT 'operacional.asignaciones'
);

DROP TABLE IF EXISTS staging.stg_gestiones;
CREATE TABLE staging.stg_gestiones (
  id_gestion      BIGINT,
  id_lead         VARCHAR(20),
  id_asesor       VARCHAR(10),
  canal_contacto  VARCHAR(30),
  resultado       VARCHAR(30),
  duracion_seg    INT,
  comentario      TEXT,
  registrado_en   TIMESTAMP,
  _cargado_en     TIMESTAMP NOT NULL DEFAULT now(),
  _lote           BIGINT,
  _origen         VARCHAR(60) NOT NULL DEFAULT 'operacional.gestiones'
);
-- la carga incremental borra por ventana antes de insertar: conviene indexar
CREATE INDEX IF NOT EXISTS ix_stg_gestiones_reg
  ON staging.stg_gestiones (registrado_en);

DROP TABLE IF EXISTS staging.stg_desembolsos;
CREATE TABLE staging.stg_desembolsos (
  id_desembolso   BIGINT,
  id_lead         VARCHAR(20),
  id_asesor       VARCHAR(10),
  fecha           DATE,
  monto           NUMERIC(12,2),
  plazo_meses     SMALLINT,
  tasa_anual      NUMERIC(5,2),
  moneda          CHAR(3),
  registrado_en   TIMESTAMP,
  _cargado_en     TIMESTAMP NOT NULL DEFAULT now(),
  _lote           BIGINT,
  _origen         VARCHAR(60) NOT NULL DEFAULT 'operacional.desembolsos'
);
CREATE INDEX IF NOT EXISTS ix_stg_desembolsos_reg
  ON staging.stg_desembolsos (registrado_en);

-- ---------------------------------------------------------------------
-- Comprobacion
-- ---------------------------------------------------------------------
SELECT table_name,
       (SELECT count(*) FROM information_schema.columns c
         WHERE c.table_schema = 'staging' AND c.table_name = t.table_name) AS columnas
FROM information_schema.tables t
WHERE table_schema = 'staging'
ORDER BY table_name;
