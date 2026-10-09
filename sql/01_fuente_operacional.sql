-- =====================================================================
-- 01 · FUENTE OPERACIONAL  (esquema: operacional)
-- =====================================================================
-- Simula el sistema transaccional de la institucion: normalizado,
-- pensado para registrar, no para analizar. Es el ORIGEN del warehouse.
--
-- Nada de aqui se consulta para reportes: todo pasa primero por staging.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS operacional;
SET search_path TO operacional;

-- ---------------------------------------------------------------------
-- Clientes con credito pre-aprobado que entrega el area de riesgos
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS leads (
  id_lead           VARCHAR(20)  PRIMARY KEY,
  fecha_aprobacion  DATE         NOT NULL,
  nombre_cliente    VARCHAR(120) NOT NULL,
  documento         VARCHAR(15),
  telefono          VARCHAR(15),
  distrito          VARCHAR(60),
  producto          VARCHAR(60),
  monto_aprobado    NUMERIC(12,2),
  score_riesgo      INT,
  prioridad         SMALLINT CHECK (prioridad BETWEEN 1 AND 5),
  canal             VARCHAR(40),
  region            VARCHAR(60),
  oficina           VARCHAR(60),
  actualizado_en    TIMESTAMP    DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Personal de ventanilla.
-- OJO: aqui la oficina es el valor ACTUAL. El sistema operacional
-- sobrescribe cuando alguien se traslada y pierde la historia.
-- Reconstruir esa historia es el trabajo del SCD tipo 2 en el warehouse.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS personal (
  id_asesor       VARCHAR(10)  PRIMARY KEY,
  nombre          VARCHAR(120) NOT NULL,
  region          VARCHAR(60),
  oficina         VARCHAR(60),
  puesto          VARCHAR(40),
  cargo           VARCHAR(40),
  estado          VARCHAR(20) DEFAULT 'Activo',
  actualizado_en  TIMESTAMP   DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Reparto de leads entre ventanillas
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS asignaciones (
  id_lead      VARCHAR(20) PRIMARY KEY REFERENCES leads(id_lead),
  id_asesor    VARCHAR(10) NOT NULL    REFERENCES personal(id_asesor),
  asignado_en  TIMESTAMP   DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Cada contacto con el cliente. Tabla que solo crece.
-- Es la base del HECHO del warehouse.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gestiones (
  id_gestion      BIGSERIAL   PRIMARY KEY,
  id_lead         VARCHAR(20) NOT NULL REFERENCES leads(id_lead),
  id_asesor       VARCHAR(10) NOT NULL REFERENCES personal(id_asesor),
  canal_contacto  VARCHAR(30),   -- Llamada / WhatsApp / Presencial
  resultado       VARCHAR(30) NOT NULL,
                  -- Contactado / No contesta / Interesado / Desembolsado / Rechazado
  duracion_seg    INT,
  comentario      TEXT,
  registrado_en   TIMESTAMP   NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_gestiones_lead   ON gestiones (id_lead);
CREATE INDEX IF NOT EXISTS ix_gestiones_asesor ON gestiones (id_asesor, registrado_en);

-- ---------------------------------------------------------------------
-- El lead que convierte termina en un desembolso.
-- Aqui aparece el dinero, y de aqui saldra la cartera del Proyecto 2.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS desembolsos (
  id_desembolso   BIGSERIAL    PRIMARY KEY,
  id_lead         VARCHAR(20)  NOT NULL REFERENCES leads(id_lead),
  id_asesor       VARCHAR(10)  NOT NULL REFERENCES personal(id_asesor),
  fecha           DATE         NOT NULL,
  monto           NUMERIC(12,2) NOT NULL CHECK (monto > 0),
  plazo_meses     SMALLINT     NOT NULL CHECK (plazo_meses BETWEEN 1 AND 60),
  tasa_anual      NUMERIC(5,2) NOT NULL,
  moneda          CHAR(3)      NOT NULL DEFAULT 'PEN' CHECK (moneda IN ('PEN','USD')),
  registrado_en   TIMESTAMP    DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_desembolsos_fecha ON desembolsos (fecha);

-- ---------------------------------------------------------------------
-- Comprobacion
-- ---------------------------------------------------------------------
SELECT table_name,
       (SELECT count(*) FROM information_schema.columns c
         WHERE c.table_schema = 'operacional' AND c.table_name = t.table_name) AS columnas
FROM information_schema.tables t
WHERE table_schema = 'operacional'
ORDER BY table_name;
