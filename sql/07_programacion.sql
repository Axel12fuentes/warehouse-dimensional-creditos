-- =====================================================================
-- 07 · PROGRAMACION CON pg_cron
-- =====================================================================
-- pg_cron corre dentro de la propia base. Para un warehouse de este
-- tamano alcanza y evita montar un orquestador aparte.
--
-- Donde deja de alcanzar: cuando el pipeline depende de sistemas externos,
-- necesita reintentos con espera creciente, o hay que coordinar tareas en
-- varias maquinas. Ahi entra Airflow o Data Factory.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Envoltorio con bitacora: lo que se programa nunca es el procedimiento
-- crudo, sino uno que registra que paso.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE dw.ejecutar_carga_diaria()
LANGUAGE plpgsql AS $$
DECLARE
  v_lote   BIGINT;
  v_inicio TIMESTAMP := clock_timestamp();
  v_hechos INT;
BEGIN
  INSERT INTO staging.control_carga (proceso, estrategia, estado, inicio)
  VALUES ('warehouse_completo', 'orquestacion', 'EN CURSO', v_inicio)
  RETURNING id_control INTO v_lote;

  CALL dw.cargar_todo();

  SELECT count(*) INTO v_hechos FROM dw.fact_gestion;

  UPDATE staging.control_carga
     SET estado = 'OK', filas = v_hechos,
         marca_agua = v_inicio, fin = clock_timestamp()
   WHERE id_control = v_lote;

EXCEPTION WHEN OTHERS THEN
  UPDATE staging.control_carga
     SET estado = 'ERROR', mensaje = SQLERRM, fin = clock_timestamp()
   WHERE id_control = v_lote;
  RAISE;          -- imprescindible: si no, el job queda en verde habiendo fallado
END;
$$;

-- ---------------------------------------------------------------------
-- Programar la carga diaria
-- ---------------------------------------------------------------------
-- Formato cron:  minuto hora dia-mes mes dia-semana
--   0 2 * * *    todos los dias a las 02:00
--   0 */4 * * *  cada 4 horas
--   0 6 * * 1    los lunes a las 06:00
-- ---------------------------------------------------------------------

SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'carga-warehouse';

SELECT cron.schedule(
  'carga-warehouse',
  '0 2 * * *',
  $$CALL dw.ejecutar_carga_diaria()$$
);

-- ---------------------------------------------------------------------
-- Vista para vigilar las ejecuciones
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW dw.v_jobs AS
SELECT j.jobname, j.schedule, j.active, j.command,
       r.status, r.start_time,
       round(extract(epoch FROM (r.end_time - r.start_time))::numeric, 2) AS segundos,
       r.return_message
FROM cron.job j
LEFT JOIN LATERAL (
  SELECT * FROM cron.job_run_details d
  WHERE d.jobid = j.jobid ORDER BY d.start_time DESC LIMIT 5
) r ON true
ORDER BY j.jobname, r.start_time DESC;

-- ---------------------------------------------------------------------
-- Comandos utiles (no se ejecutan aqui, quedan documentados)
-- ---------------------------------------------------------------------
-- Ver los jobs:            SELECT * FROM cron.job;
-- Ver las ejecuciones:     SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 20;
-- Desactivar sin borrar:   UPDATE cron.job SET active = false WHERE jobname = 'carga-warehouse';
-- Borrar:                  SELECT cron.unschedule('carga-warehouse');
-- Correr a mano:           CALL dw.ejecutar_carga_diaria();

SELECT jobname, schedule, active FROM cron.job;
