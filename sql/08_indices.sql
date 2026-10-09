-- =====================================================================
-- 08 · INDICES Y PLANES DE EJECUCION
-- =====================================================================
-- Medido sobre 197.028 filas en fact_gestion y 60.001 en dim_cliente.
-- Con pocos miles de filas NINGUNA de estas mediciones tiene sentido:
-- Postgres prefiere leer la tabla entera y hace bien.
--
-- Metodo de cada experimento:
--   1. EXPLAIN (ANALYZE, COSTS OFF) de la consulta
--   2. crear el indice
--   3. ANALYZE para refrescar estadisticas
--   4. volver a medir y comparar el PLAN, no solo el tiempo
-- =====================================================================

-- ---------------------------------------------------------------------
-- EXPERIMENTO A · filtro muy selectivo sobre una columna sin indice
-- ---------------------------------------------------------------------
-- Buscar un cliente por documento entre 60.001.
--
--   SIN indice   Seq Scan · 3,32 ms · descarta 60.001 filas
--   CON indice   Index Scan · 0,09 ms
--   -> 37 veces mas rapido
--
-- Es el caso de libro: filtro que deja pasar casi nada.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_dim_cliente_doc
  ON dw.dim_cliente (documento);

-- ---------------------------------------------------------------------
-- EXPERIMENTO B · indice compuesto contra dos indices sueltos
-- ---------------------------------------------------------------------
-- Gestiones de un asesor en un rango de fechas.
--
--   Dos indices sueltos   BitmapAnd de ix_fg_asesor + ix_fg_tiempo · 2,87 ms
--   Uno compuesto         Index Only Scan · 0,21 ms · Heap Fetches: 0
--   -> 13 veces mas rapido
--
-- Dos cosas pasan a la vez:
--   a) con un solo indice el motor no tiene que combinar dos mapas de bits
--   b) "Index Only Scan" con Heap Fetches 0 significa que respondio SIN
--      tocar la tabla: todo lo que la consulta pedia estaba en el indice
--
-- ORDEN DE LAS COLUMNAS: primero la de igualdad (sk_asesor), despues la
-- de rango (sk_tiempo). Al reves el indice sirve mucho menos.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_fg_asesor_tiempo
  ON dw.fact_gestion (sk_asesor, sk_tiempo);

-- ---------------------------------------------------------------------
-- EXPERIMENTO C · lo que contradijo la regla de libro
-- ---------------------------------------------------------------------
-- La regla que se repite en todos lados dice: "un indice compuesto sobre
-- (A, B) no sirve para filtrar solo por B". Medido, es una simplificacion.
--
-- Misma consulta, filtrando SOLO por sk_tiempo:
--
--   Sin ningun indice util        Parallel Seq Scan · 9,95 ms
--   Con el compuesto (A, B)       Index Only Scan   · 2,15 ms   4,6x mejor
--   Con un indice dedicado (B)    Index Only Scan   · 1,66 ms   6,0x mejor
--
-- Por que: sin la primera columna el motor no puede SALTAR directo al
-- valor, pero si puede recorrer el indice entero, que es mucho mas chico
-- que la tabla. Si ademas el indice cubre todas las columnas pedidas,
-- responde sin tocar la tabla.
--
-- La regla corregida: el compuesto SI ayuda a la segunda columna, pero
-- menos que un indice dedicado. No es inutil, es subóptimo.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_fg_tiempo
  ON dw.fact_gestion (sk_tiempo);

-- ---------------------------------------------------------------------
-- EXPERIMENTO D · cuando el indice deja de convenir
-- ---------------------------------------------------------------------
-- Filtro por canal_contacto = 'WhatsApp', que deja pasar el 33%.
--
--   Contando solo filas       Index Only Scan · 4,85 ms   (el indice cubre todo)
--   Pidiendo otras columnas   Bitmap Heap Scan · 24,12 ms (hay que ir a la tabla)
--
-- Con 33% de las filas, ir al indice y despues saltar a la tabla por cada
-- coincidencia sale caro. Lo que salva al primer caso no es la selectividad:
-- es que el indice CUBRE la consulta.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_fg_canal
  ON dw.fact_gestion (canal_contacto);

-- ---------------------------------------------------------------------
-- INDICE PARCIAL · indexar solo lo que se consulta
-- ---------------------------------------------------------------------
-- Los desembolsos son el 6% de las gestiones, pero casi todos los reportes
-- los filtran. Un indice parcial ocupa una fraccion del completo.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_fg_desembolsos
  ON dw.fact_gestion (sk_tiempo, sk_asesor)
  WHERE es_desembolso = 1;

-- ---------------------------------------------------------------------
-- LO QUE CUESTA
-- ---------------------------------------------------------------------
--   Datos               25 MB
--   Datos + indices     40 MB
--   -> los indices pesan 60% de lo que pesa la tabla
--
-- Y cada INSERT, UPDATE y DELETE tiene que actualizarlos todos. Un indice
-- que nadie usa es solo costo.
-- ---------------------------------------------------------------------

ANALYZE dw.fact_gestion;
ANALYZE dw.fact_desembolso;
ANALYZE dw.dim_cliente;

-- ---------------------------------------------------------------------
-- Vista para vigilar que indices se usan de verdad
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW dw.v_uso_indices AS
SELECT schemaname AS esquema,
       relname    AS tabla,
       indexrelname AS indice,
       idx_scan   AS veces_usado,
       pg_size_pretty(pg_relation_size(indexrelid)) AS tamano
FROM pg_stat_user_indexes
WHERE schemaname IN ('dw','staging')
ORDER BY idx_scan ASC, pg_relation_size(indexrelid) DESC;

COMMENT ON VIEW dw.v_uso_indices IS
  'Indices ordenados de menos a mas usados. Los de arriba con 0 son candidatos a borrar.';

SELECT * FROM dw.v_uso_indices;
