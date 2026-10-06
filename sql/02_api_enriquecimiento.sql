-- =============================================================================
-- 02_api_enriquecimiento.sql — TASK 03: uso de los datos traídos por API
-- Requiere: 00_carga.sql  +  python scripts/fetch_api.py  (genera data/api/*.csv)
--
-- Qué hace:
--   1. Carga feriados, cotizaciones MEP y el log de llamadas.
--   2. Arma un calendario con días hábiles bursátiles (lun-vie que no son feriado).
--   3. Calcula un tipo de cambio diario: MEP de la API; si la API no respondió (o falta un día),
--      MEP implícito del propio dataset (precio AL30 en ARS / precio AL30D en USD).
--   4. Crea iol.operaciones_enr: cada operación con monto homogeneizado en ARS y flags de calendario.
-- =============================================================================
SET search_path TO iol;
SET client_min_messages = warning;
\pset footer off

-- 1) Carga ------------------------------------------------------------------
DROP TABLE IF EXISTS feriados, tipo_cambio_api, api_log CASCADE;
CREATE TABLE feriados        (fecha date PRIMARY KEY, nombre text, tipo text, fuente text);
CREATE TABLE tipo_cambio_api (fecha date PRIMARY KEY, compra numeric, venta numeric, fuente text);
CREATE TABLE api_log         (ts_utc timestamptz, api text, url text, estado text, filas int, detalle text);

\copy feriados        FROM 'data/api/feriados_2026.csv'   WITH (FORMAT csv, HEADER true)
\copy tipo_cambio_api FROM 'data/api/tipo_cambio_mep.csv' WITH (FORMAT csv, HEADER true)
\copy api_log         FROM 'data/api/api_log.csv'         WITH (FORMAT csv, HEADER true)

\echo '=== 3.0 Log de llamadas a APIs (qué fuente se usó en esta corrida) ==='
SELECT api, estado, filas, left(detalle, 70) AS detalle FROM api_log ORDER BY ts_utc, api;

-- 2) Calendario --------------------------------------------------------------
DROP TABLE IF EXISTS calendario CASCADE;
CREATE TABLE calendario AS
SELECT d::date                                         AS fecha,
       extract(isodow FROM d)::int                     AS dow,
       f.nombre                                        AS feriado,
       (extract(isodow FROM d) < 6 AND f.fecha IS NULL) AS es_habil
FROM generate_series('2025-12-15'::date, '2026-03-31'::date, interval '1 day') d
LEFT JOIN feriados f ON f.fecha = d::date;

\echo '=== 3.1 Feriados dentro del período del dataset (según API) ==='
SELECT c.fecha, c.feriado,
       (SELECT count(*) FROM operaciones o WHERE o.dia_art = c.fecha) AS ops_ese_dia
FROM calendario c
WHERE c.feriado IS NOT NULL AND c.fecha BETWEEN '2026-01-01' AND '2026-03-13'
ORDER BY 1;

-- 3) Tipo de cambio diario ---------------------------------------------------
DROP TABLE IF EXISTS mep_implicito CASCADE;
CREATE TABLE mep_implicito AS
WITH p AS (
    SELECT dia_art,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY precio) FILTER (WHERE simbolo_titulo = 'AL30'  AND moneda = 'ARS') AS al30_ars,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY precio) FILTER (WHERE simbolo_titulo = 'AL30D' AND moneda = 'USD') AS al30d_usd,
           count(*) FILTER (WHERE simbolo_titulo = 'AL30')  AS n_ars,
           count(*) FILTER (WHERE simbolo_titulo = 'AL30D') AS n_usd
    FROM operaciones
    WHERE simbolo_titulo IN ('AL30', 'AL30D')
    GROUP BY dia_art
)
SELECT dia_art AS fecha, round((al30_ars / al30d_usd)::numeric, 2) AS mep_implicito, n_ars, n_usd
FROM p
WHERE n_ars >= 5 AND n_usd >= 5;   -- mínimo de operaciones para que la mediana sea representativa

DROP TABLE IF EXISTS tipo_cambio_diario CASCADE;
CREATE TABLE tipo_cambio_diario AS
SELECT c.fecha,
       coalesce(api.venta, imp.mep_implicito)                                   AS tc_ars_por_usd,
       CASE WHEN api.venta IS NOT NULL THEN 'API MEP (' || api.fuente || ')'
            ELSE 'MEP implícito dataset (AL30/AL30D)' END                       AS fuente_tc,
       api.fecha_ref <> c.fecha OR (api.fecha_ref IS NULL AND imp.fecha_ref <> c.fecha) AS arrastrado
FROM calendario c
LEFT JOIN LATERAL (SELECT t.venta, t.fuente, t.fecha AS fecha_ref FROM tipo_cambio_api t
                   WHERE t.fecha <= c.fecha ORDER BY t.fecha DESC LIMIT 1) api ON true
LEFT JOIN LATERAL (SELECT m.mep_implicito, m.fecha AS fecha_ref FROM mep_implicito m
                   WHERE m.fecha <= c.fecha ORDER BY m.fecha DESC LIMIT 1) imp ON true
WHERE c.fecha BETWEEN '2026-01-01' AND '2026-03-31';

-- Si el MEP implícito no tiene dato previo (1-ene), tomamos el primero disponible
UPDATE tipo_cambio_diario t
SET tc_ars_por_usd = (SELECT mep_implicito FROM mep_implicito ORDER BY fecha LIMIT 1), arrastrado = true
WHERE tc_ars_por_usd IS NULL;

\echo '=== 3.2 Tipo de cambio usado: fuente y rango ==='
SELECT fuente_tc, count(*) AS dias, min(tc_ars_por_usd) AS minimo, max(tc_ars_por_usd) AS maximo,
       round(avg(tc_ars_por_usd), 2) AS promedio
FROM tipo_cambio_diario GROUP BY 1;

\echo '=== 3.3 Control cruzado: MEP API vs MEP implícito del dataset (solo si la API respondió) ==='
SELECT a.fecha, a.venta AS mep_api, m.mep_implicito,
       round(100 * (m.mep_implicito / a.venta - 1), 2) AS desvio_pct
FROM tipo_cambio_api a JOIN mep_implicito m USING (fecha)
ORDER BY a.fecha;

-- 4) Operaciones enriquecidas ------------------------------------------------
DROP TABLE IF EXISTS operaciones_enr CASCADE;
CREATE TABLE operaciones_enr AS
SELECT o.*,
       tc.tc_ars_por_usd,
       CASE WHEN o.moneda = 'USD' THEN round(o.monto * tc.tc_ars_por_usd, 2) ELSE o.monto END AS monto_ars,
       c.es_habil,
       c.feriado,
       CASE WHEN c.feriado IS NOT NULL     THEN 'Feriado'
            WHEN o.dow_art IN (6, 7)       THEN 'Fin de semana'
            ELSE 'Día hábil' END                                          AS tipo_dia,
       CASE WHEN o.hora_art BETWEEN 11 AND 16 THEN 'Mercado (11-17)'
            WHEN o.hora_art BETWEEN 0 AND 5   THEN 'Madrugada (0-6)'
            WHEN o.hora_art BETWEEN 6 AND 10  THEN 'Pre-mercado (6-11)'
            ELSE 'Post-mercado (17-24)' END                               AS franja_horaria,
       date_trunc('month', o.dia_art)::date                               AS mes
FROM operaciones o
JOIN tipo_cambio_diario tc ON tc.fecha = o.dia_art
JOIN calendario c          ON c.fecha  = o.dia_art;

ALTER TABLE operaciones_enr ADD PRIMARY KEY (id_transaccion);
CREATE INDEX ix_enr_cliente ON operaciones_enr (id_cliente);

\echo '=== 3.4 Operaciones según tipo de día (calendario de la API) ==='
SELECT tipo_dia, count(*) AS ops,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct_ops,
       count(DISTINCT id_cliente) AS clientes,
       round(sum(monto_ars) / 1e6, 1) AS monto_ars_millones
FROM operaciones_enr GROUP BY 1 ORDER BY ops DESC;

\echo '=== 3.5 Volumen total homogeneizado en ARS por moneda de origen ==='
SELECT moneda, count(*) AS ops,
       round(sum(monto_ars) / 1e6, 1) AS monto_ars_millones,
       round(100.0 * sum(monto_ars) / sum(sum(monto_ars)) OVER (), 2) AS pct_monto
FROM operaciones_enr GROUP BY 1;

\echo '=== 3.6 Volumen mensual en ARS (el período de marzo llega hasta el 13/03) ==='
SELECT mes, count(*) AS ops, count(DISTINCT dia_art) FILTER (WHERE es_habil) AS dias_habiles_con_ops,
       round(sum(monto_ars) / 1e6, 1) AS monto_ars_millones,
       round(count(*)::numeric / nullif(count(DISTINCT dia_art) FILTER (WHERE es_habil), 0), 0) AS ops_por_dia_habil
FROM operaciones_enr GROUP BY 1 ORDER BY 1;
