-- =====================================================================
-- 03 · CARGA DE STAGING  (procedimientos)
-- =====================================================================
-- Dos estrategias, elegidas segun la tabla:
--
--   COMPLETA      personal, leads, asignaciones
--                 Son chicas y SUS ATRIBUTOS CAMBIAN en el origen.
--                 Para detectar un cambio hay que ver la foto entera.
--
--   INCREMENTAL   gestiones, desembolsos
--                 Solo crecen, nunca se modifican. Traer todo cada
--                 noche seria desperdicio. Se usa marca de agua.
--
-- Las dos son IDEMPOTENTES: correr el proceso dos veces deja el mismo
-- resultado que correrlo una vez.
-- =====================================================================

SET search_path TO staging, public;

-- ---------------------------------------------------------------------
-- Util: ultima marca de agua exitosa de un proceso
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION staging.ultima_marca(p_proceso VARCHAR)
RETURNS TIMESTAMP
LANGUAGE sql STABLE
AS $$
  SELECT coalesce(max(marca_agua), TIMESTAMP '1900-01-01')
  FROM staging.control_carga
  WHERE proceso = p_proceso AND estado = 'OK';
$$;

-- ---------------------------------------------------------------------
-- CARGA COMPLETA
-- Vacia la tabla y vuelve a copiar el origen entero.
-- Idempotente por construccion: el TRUNCATE borra lo anterior.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE staging.cargar_completa(p_tabla VARCHAR)
LANGUAGE plpgsql
AS $$
DECLARE
  v_lote   BIGINT;
  v_filas  INT;
  v_inicio TIMESTAMP := clock_timestamp();
BEGIN
  INSERT INTO staging.control_carga (proceso, estrategia, estado, inicio)
  VALUES (p_tabla, 'completa', 'EN CURSO', v_inicio)
  RETURNING id_control INTO v_lote;

  EXECUTE format('TRUNCATE staging.stg_%I', p_tabla);

  EXECUTE format(
    'INSERT INTO staging.stg_%I SELECT *, now(), %s, %L FROM operacional.%I',
    p_tabla, v_lote, 'operacional.' || p_tabla, p_tabla);

  GET DIAGNOSTICS v_filas = ROW_COUNT;

  UPDATE staging.control_carga
     SET filas = v_filas, estado = 'OK',
         marca_agua = v_inicio, fin = clock_timestamp()
   WHERE id_control = v_lote;

EXCEPTION WHEN OTHERS THEN
  UPDATE staging.control_carga
     SET estado = 'ERROR', mensaje = SQLERRM, fin = clock_timestamp()
   WHERE id_control = v_lote;
  RAISE;    -- sin esto el job terminaria en verde habiendo fallado
END;
$$;

-- ---------------------------------------------------------------------
-- CARGA INCREMENTAL
-- Trae solo lo registrado despues de la ultima marca de agua.
-- Idempotente porque primero BORRA la ventana que va a reinsertar:
-- si el proceso se repite, no duplica.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE staging.cargar_incremental(p_tabla VARCHAR)
LANGUAGE plpgsql
AS $$
DECLARE
  v_lote   BIGINT;
  v_filas  INT;
  v_desde  TIMESTAMP;
  v_hasta  TIMESTAMP := clock_timestamp();
  v_inicio TIMESTAMP := clock_timestamp();
BEGIN
  v_desde := staging.ultima_marca(p_tabla);

  INSERT INTO staging.control_carga (proceso, estrategia, estado, inicio)
  VALUES (p_tabla, 'incremental', 'EN CURSO', v_inicio)
  RETURNING id_control INTO v_lote;

  -- 1. limpiar la ventana (esto es lo que da la idempotencia)
  EXECUTE format(
    'DELETE FROM staging.stg_%I WHERE registrado_en > %L AND registrado_en <= %L',
    p_tabla, v_desde, v_hasta);

  -- 2. reinsertarla desde el origen
  EXECUTE format(
    'INSERT INTO staging.stg_%I SELECT *, now(), %s, %L FROM operacional.%I
       WHERE registrado_en > %L AND registrado_en <= %L',
    p_tabla, v_lote, 'operacional.' || p_tabla, p_tabla, v_desde, v_hasta);

  GET DIAGNOSTICS v_filas = ROW_COUNT;

  UPDATE staging.control_carga
     SET filas = v_filas, estado = 'OK',
         marca_agua = v_hasta, fin = clock_timestamp()
   WHERE id_control = v_lote;

EXCEPTION WHEN OTHERS THEN
  UPDATE staging.control_carga
     SET estado = 'ERROR', mensaje = SQLERRM, fin = clock_timestamp()
   WHERE id_control = v_lote;
  RAISE;
END;
$$;

-- ---------------------------------------------------------------------
-- Orquestador: una sola llamada para toda la capa
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE staging.cargar_todo()
LANGUAGE plpgsql
AS $$
BEGIN
  CALL staging.cargar_completa('personal');
  CALL staging.cargar_completa('leads');
  CALL staging.cargar_completa('asignaciones');
  CALL staging.cargar_incremental('gestiones');
  CALL staging.cargar_incremental('desembolsos');
END;
$$;

-- ---------------------------------------------------------------------
-- Vista para revisar las ultimas corridas
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW staging.v_ultimas_cargas AS
SELECT proceso, estrategia, estado, filas,
       marca_agua,
       round(extract(epoch FROM (fin - inicio))::numeric, 2) AS segundos,
       inicio
FROM staging.control_carga
ORDER BY inicio DESC;
