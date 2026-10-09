-- =====================================================================
-- 05 · CARGA DE DIMENSIONES
-- =====================================================================
-- dim_oficina, dim_producto, dim_cliente  ->  MERGE (tipo 1)
-- dim_asesor                              ->  dos pasos (tipo 2)
--
-- Por que el tipo 2 necesita DOS pasos y no un MERGE:
--   para la misma llave natural hay que CERRAR la version vigente e
--   INSERTAR una nueva. Un solo MERGE no puede actualizar e insertar la
--   misma llave en la misma ejecucion.
-- =====================================================================

-- ---------------------------------------------------------------------
-- OFICINA · tipo 1
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE dw.cargar_dim_oficina()
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO dw.dim_oficina (oficina, region)
  SELECT DISTINCT oficina, region FROM staging.stg_personal
  WHERE oficina IS NOT NULL
  ON CONFLICT (oficina, region) DO NOTHING;

  INSERT INTO dw.dim_oficina (oficina, region)
  SELECT DISTINCT oficina, region FROM staging.stg_leads
  WHERE oficina IS NOT NULL
  ON CONFLICT (oficina, region) DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------------
-- PRODUCTO · tipo 1 · con un atributo derivado
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE dw.cargar_dim_producto()
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO dw.dim_producto (producto, familia)
  SELECT DISTINCT producto,
         CASE
           WHEN producto ILIKE '%capital de trabajo%' THEN 'Empresarial'
           WHEN producto ILIKE '%agricola%'           THEN 'Empresarial'
           WHEN producto ILIKE '%microcredito%'       THEN 'Empresarial'
           ELSE 'Personal'
         END
  FROM staging.stg_leads
  WHERE producto IS NOT NULL
  ON CONFLICT (producto) DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------------
-- CLIENTE · tipo 1 · MERGE: actualiza lo que cambio, inserta lo nuevo
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE dw.cargar_dim_cliente()
LANGUAGE plpgsql AS $$
BEGIN
  MERGE INTO dw.dim_cliente d
  USING (
    SELECT id_lead, nombre_cliente, documento, telefono, distrito, canal,
           score_riesgo, prioridad,
           CASE
             WHEN score_riesgo IS NULL  THEN 'Desconocido'
             WHEN score_riesgo >= 740   THEN 'A · muy bueno'
             WHEN score_riesgo >= 660   THEN 'B · bueno'
             WHEN score_riesgo >= 580   THEN 'C · regular'
             WHEN score_riesgo >= 480   THEN 'D · bajo'
             ELSE                            'E · muy bajo'
           END AS tramo_score,
           md5(coalesce(nombre_cliente,'')||'|'||coalesce(telefono,'')||'|'||
               coalesce(distrito,'')||'|'||coalesce(score_riesgo::text,'')) AS h
    FROM staging.stg_leads
  ) s
  ON d.id_lead = s.id_lead
  WHEN MATCHED AND d._hash IS DISTINCT FROM s.h THEN
    UPDATE SET nombre_cliente = s.nombre_cliente,
               documento      = s.documento,
               telefono       = s.telefono,
               distrito       = s.distrito,
               canal          = s.canal,
               score_riesgo   = s.score_riesgo,
               tramo_score    = s.tramo_score,
               prioridad      = s.prioridad,
               _hash          = s.h,
               _cargado_en    = now()
  WHEN NOT MATCHED THEN
    INSERT (id_lead, nombre_cliente, documento, telefono, distrito, canal,
            score_riesgo, tramo_score, prioridad, _hash)
    VALUES (s.id_lead, s.nombre_cliente, s.documento, s.telefono, s.distrito,
            s.canal, s.score_riesgo, s.tramo_score, s.prioridad, s.h);
END;
$$;

-- ---------------------------------------------------------------------
-- ASESOR · TIPO 2 · el corazon del proyecto
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE dw.cargar_dim_asesor()
LANGUAGE plpgsql AS $$
DECLARE
  v_cerradas INT;
  v_nuevas   INT;
  v_primera  BOOLEAN;
BEGIN
  -- Primera carga: no hay historia previa. Las versiones nacen con fecha
  -- de inicio muy antigua para que los hechos viejos encuentren su version.
  -- Si naciera hoy, las gestiones de enero no coincidirian con nada.
  SELECT count(*) = 0 INTO v_primera
  FROM dw.dim_asesor WHERE sk_asesor <> -1;

  -- PASO 0 · cambios ocurridos EL MISMO DIA en que nacio la version
  --
  -- No son una version nueva: son una correccion. Si se cerraran con
  -- hasta = ayer quedaria un rango imposible (hasta anterior a desde) y
  -- ninguna fila de hechos podria caer en el. Se actualizan en el sitio.
  WITH origen AS (
    SELECT id_asesor, nombre, region, oficina, puesto, cargo, estado,
           md5(coalesce(nombre,'')||'|'||coalesce(region,'')||'|'||
               coalesce(oficina,'')||'|'||coalesce(puesto,'')||'|'||
               coalesce(cargo,'')||'|'||coalesce(estado,'')) AS h
    FROM staging.stg_personal
  )
  UPDATE dw.dim_asesor d
     SET nombre = o.nombre, region = o.region, oficina = o.oficina,
         puesto = o.puesto, cargo = o.cargo, estado = o.estado,
         _hash = o.h, _cargado_en = now()
    FROM origen o
   WHERE d.id_asesor = o.id_asesor
     AND d.vigente
     AND d.sk_asesor <> -1
     AND d.desde = current_date          -- nacio hoy
     AND d._hash IS DISTINCT FROM o.h;

  -- PASO 1 · cerrar las versiones vigentes cuyo atributo vigilado cambio
  WITH origen AS (
    SELECT id_asesor,
           md5(coalesce(nombre,'')||'|'||coalesce(region,'')||'|'||
               coalesce(oficina,'')||'|'||coalesce(puesto,'')||'|'||
               coalesce(cargo,'')||'|'||coalesce(estado,'')) AS h
    FROM staging.stg_personal
  )
  UPDATE dw.dim_asesor d
     SET hasta   = current_date - 1,
         vigente = false
    FROM origen o
   WHERE d.id_asesor = o.id_asesor
     AND d.vigente
     AND d.sk_asesor <> -1
     AND d._hash IS DISTINCT FROM o.h;
  GET DIAGNOSTICS v_cerradas = ROW_COUNT;

  -- PASO 2 · insertar la version nueva de quien quedo sin vigente
  INSERT INTO dw.dim_asesor
    (id_asesor, nombre, region, oficina, puesto, cargo, estado, desde, hasta, vigente, _hash)
  SELECT s.id_asesor, s.nombre, s.region, s.oficina, s.puesto, s.cargo, s.estado,
         CASE WHEN v_primera THEN DATE '1900-01-01' ELSE current_date END,
         DATE '9999-12-31',
         true,
         md5(coalesce(s.nombre,'')||'|'||coalesce(s.region,'')||'|'||
             coalesce(s.oficina,'')||'|'||coalesce(s.puesto,'')||'|'||
             coalesce(s.cargo,'')||'|'||coalesce(s.estado,''))
  FROM staging.stg_personal s
  LEFT JOIN dw.dim_asesor d
         ON d.id_asesor = s.id_asesor AND d.vigente
  WHERE d.id_asesor IS NULL;
  GET DIAGNOSTICS v_nuevas = ROW_COUNT;

  -- PASO 3 · barrer rangos imposibles que haya dejado una carga anterior.
  -- Son versiones que nunca estuvieron vigentes ni un dia, asi que ningun
  -- hecho puede apuntar a ellas.
  DELETE FROM dw.dim_asesor d
   WHERE d.hasta < d.desde
     AND NOT EXISTS (SELECT 1 FROM dw.fact_gestion f    WHERE f.sk_asesor = d.sk_asesor)
     AND NOT EXISTS (SELECT 1 FROM dw.fact_desembolso f WHERE f.sk_asesor = d.sk_asesor);

  RAISE NOTICE 'dim_asesor: % version(es) cerrada(s), % nueva(s)', v_cerradas, v_nuevas;
END;
$$;

-- ---------------------------------------------------------------------
-- Orquestador
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE dw.cargar_dimensiones()
LANGUAGE plpgsql AS $$
BEGIN
  CALL dw.cargar_dim_oficina();
  CALL dw.cargar_dim_producto();
  CALL dw.cargar_dim_cliente();
  CALL dw.cargar_dim_asesor();
END;
$$;

-- ---------------------------------------------------------------------
-- Vista para auditar la historia del asesor
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW dw.v_historia_asesor AS
SELECT id_asesor, nombre, region, oficina, desde, hasta, vigente, sk_asesor
FROM dw.dim_asesor
WHERE sk_asesor <> -1
ORDER BY id_asesor, desde;
