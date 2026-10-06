-- =============================================================================
-- 01_exploracion.sql — TASK 01: Exploración y comprensión del dataset
-- Requiere: 00_carga.sql
-- Salida de referencia: outputs/01_exploracion.txt
-- =============================================================================
SET search_path TO iol;
SET client_min_messages = warning;
\pset footer off

-- -----------------------------------------------------------------------------
-- 1.1 Descripción general
-- -----------------------------------------------------------------------------
\echo '=== 1.1 Descripción general ==='
SELECT
    count(*)                                   AS operaciones,
    count(DISTINCT id_cliente)                 AS clientes_unicos,
    count(DISTINCT simbolo_titulo)             AS simbolos,
    count(DISTINCT descripcion_titulo)         AS descripciones,
    min(fecha_utc)                             AS primera_op_utc,
    max(fecha_utc)                             AS ultima_op_utc,
    count(DISTINCT fecha_utc::date)            AS dias_con_actividad_utc,
    round(count(*)::numeric / count(DISTINCT id_cliente), 2) AS ops_por_cliente_prom
FROM operaciones;

-- -----------------------------------------------------------------------------
-- 1.2 Calidad del dato: ¿qué tan limpio está?
-- -----------------------------------------------------------------------------
\echo '=== 1.2a Nulos / vacíos / valores no positivos ==='
SELECT
    count(*) FILTER (WHERE id_cliente IS NULL OR id_cliente = '')         AS cliente_vacio,
    count(*) FILTER (WHERE simbolo_titulo IS NULL OR simbolo_titulo = '') AS simbolo_vacio,
    count(*) FILTER (WHERE cantidad <= 0)                                 AS cantidad_no_positiva,
    count(*) FILTER (WHERE precio <= 0)                                   AS precio_no_positivo,
    count(*) - count(DISTINCT id_transaccion)                             AS id_transaccion_duplicado
FROM operaciones;

\echo '=== 1.2b Duplicados lógicos (mismo cliente, instante, título, cantidad y precio) ==='
SELECT count(*) AS grupos_duplicados, coalesce(sum(n),0) AS operaciones_involucradas
FROM (
    SELECT count(*) AS n
    FROM operaciones
    GROUP BY id_cliente, fecha_utc, simbolo_titulo, cantidad, precio, tipo_tran
    HAVING count(*) > 1
) d;

\echo '=== 1.2c Milisegundos del timestamp por canal (particularidad: .010 concentrado en IOLnet) ==='
SELECT origen, ms_flag, count(*) AS ops
FROM operaciones
GROUP BY origen, ms_flag
ORDER BY origen, ms_flag;

\echo '=== 1.2d Símbolos con más de una descripción, y moneda declarada vs sufijo del ticker ==='
SELECT 'simbolos_con_>1_descripcion' AS control, count(*) AS casos
FROM (SELECT simbolo_titulo FROM operaciones GROUP BY 1 HAVING count(DISTINCT descripcion_titulo) > 1) s
UNION ALL
SELECT 'simbolos_operados_en_ARS_y_USD', count(*)
FROM (SELECT simbolo_titulo FROM operaciones GROUP BY 1 HAVING count(DISTINCT moneda) > 1) s
UNION ALL
SELECT 'ticker_termina_en_D_pero_moneda_ARS', count(*)
FROM operaciones WHERE simbolo_titulo ~ '^[A-Z]{2}\d{2}D$' AND moneda = 'ARS';

-- -----------------------------------------------------------------------------
-- 1.3 Instrumentos más operados
-- -----------------------------------------------------------------------------
\echo '=== 1.3 Top 15 instrumentos por cantidad de operaciones ==='
SELECT simbolo_titulo, min(descripcion_titulo) AS descripcion, moneda,
       count(*) AS ops,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct_ops,
       count(DISTINCT id_cliente) AS clientes
FROM operaciones
GROUP BY simbolo_titulo, moneda
ORDER BY ops DESC
LIMIT 15;

\echo '=== 1.3b Familias de instrumento (heurística por descripción) ==='
SELECT
    CASE
        WHEN descripcion_titulo ILIKE 'cedear%'                         THEN 'CEDEAR'
        WHEN descripcion_titulo ILIKE '%opci%' OR simbolo_titulo ~ '^[A-Z]{3}[CV]\d' THEN 'Opción'
        WHEN descripcion_titulo ILIKE '%bono%' OR descripcion_titulo ILIKE '%rep. arg%'
          OR simbolo_titulo ~ '^(AL|GD|AE|TX|TZ|S\d)' THEN 'Bono / Letra'
        WHEN descripcion_titulo ILIKE '%obligaci%' OR descripcion_titulo ILIKE '%o.n.%' THEN 'Obligación Negociable'
        ELSE 'Acción / Otro'
    END AS familia,
    count(*) AS ops,
    round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct_ops
FROM operaciones
GROUP BY 1
ORDER BY ops DESC;

-- -----------------------------------------------------------------------------
-- 1.4 Distribución por canal, moneda y tipo
-- -----------------------------------------------------------------------------
\echo '=== 1.4a Por canal ==='
SELECT origen, count(*) AS ops,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct_ops,
       count(DISTINCT id_cliente) AS clientes,
       round(count(*)::numeric / count(DISTINCT id_cliente), 2) AS ops_por_cliente
FROM operaciones GROUP BY 1 ORDER BY ops DESC;

\echo '=== 1.4b Por moneda ==='
SELECT moneda, count(*) AS ops,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct_ops,
       round(sum(monto), 0) AS monto_total_moneda_original
FROM operaciones GROUP BY 1 ORDER BY ops DESC;

\echo '=== 1.4c Por tipo de transacción ==='
SELECT tipo_tran, count(*) AS ops,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct_ops
FROM operaciones GROUP BY 1 ORDER BY ops DESC;

\echo '=== 1.4d Canal x tipo (% de compras dentro de cada canal) ==='
SELECT origen,
       round(100.0 * count(*) FILTER (WHERE tipo_tran = 'Compra') / count(*), 1) AS pct_compra,
       round(100.0 * count(*) FILTER (WHERE moneda = 'USD') / count(*), 1)       AS pct_usd
FROM operaciones GROUP BY 1 ORDER BY 1;

-- -----------------------------------------------------------------------------
-- 1.5 Montos: rango muy amplio
-- -----------------------------------------------------------------------------
\echo '=== 1.5 Percentiles de monto por moneda (moneda original) ==='
SELECT moneda,
       round(min(monto), 2)                                                AS minimo,
       round(percentile_cont(0.50) WITHIN GROUP (ORDER BY monto)::numeric, 2) AS p50,
       round(percentile_cont(0.90) WITHIN GROUP (ORDER BY monto)::numeric, 2) AS p90,
       round(percentile_cont(0.99) WITHIN GROUP (ORDER BY monto)::numeric, 2) AS p99,
       round(percentile_cont(0.999) WITHIN GROUP (ORDER BY monto)::numeric, 2) AS p999,
       round(max(monto), 2)                                                AS maximo,
       round(max(monto) / nullif(percentile_cont(0.50) WITHIN GROUP (ORDER BY monto),0)::numeric, 0) AS max_sobre_mediana
FROM operaciones GROUP BY 1;

\echo '=== 1.5b Las 10 operaciones de mayor cantidad nominal ==='
SELECT fecha_utc, id_cliente, origen, simbolo_titulo, moneda, cantidad, precio, round(monto,2) AS monto
FROM operaciones ORDER BY cantidad DESC LIMIT 10;

-- -----------------------------------------------------------------------------
-- 1.6 Distribución de actividad por cliente (asimetría)
-- -----------------------------------------------------------------------------
\echo '=== 1.6a Clientes por tramo de cantidad de operaciones ==='
WITH c AS (SELECT id_cliente, count(*) AS ops FROM operaciones GROUP BY 1)
SELECT CASE WHEN ops = 1 THEN '01) 1'
            WHEN ops = 2 THEN '02) 2'
            WHEN ops <= 5 THEN '03) 3-5'
            WHEN ops <= 10 THEN '04) 6-10'
            WHEN ops <= 50 THEN '05) 11-50'
            WHEN ops <= 100 THEN '06) 51-100'
            ELSE '07) >100' END AS tramo_ops,
       count(*) AS clientes,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct_clientes,
       sum(ops) AS ops,
       round(100.0 * sum(ops) / sum(sum(ops)) OVER (), 2) AS pct_ops
FROM c GROUP BY 1 ORDER BY 1;

\echo '=== 1.6b Concentración (curva de Pareto): % de operaciones y de monto ARS que explica el top X% de clientes ==='
-- Monto en ARS de operaciones en ARS (el 85% del dataset). La versión homogeneizada en una sola moneda está en 02_api_enriquecimiento.sql
WITH c AS (
    SELECT id_cliente, count(*) AS ops, sum(monto) FILTER (WHERE moneda = 'ARS') AS monto_ars
    FROM operaciones GROUP BY 1
), r AS (
    SELECT *,
           row_number() OVER (ORDER BY ops DESC)                         AS rk_ops,
           row_number() OVER (ORDER BY coalesce(monto_ars,0) DESC)       AS rk_monto,
           count(*) OVER ()                                              AS n
    FROM c
)
SELECT corte,
       round(100.0 * sum(ops)       FILTER (WHERE rk_ops   <= n * corte) / sum(ops), 2)       AS pct_ops,
       round(100.0 * sum(monto_ars) FILTER (WHERE rk_monto <= n * corte) / sum(monto_ars), 2) AS pct_monto_ars
FROM r, (VALUES (0.001), (0.01), (0.05), (0.10), (0.20), (0.50)) t(corte)
GROUP BY corte ORDER BY corte;

\echo '=== 1.6c Top 10 clientes por cantidad de operaciones ==='
SELECT id_cliente, count(*) AS ops,
       count(DISTINCT origen) AS canales, min(origen) AS canal,
       count(DISTINCT simbolo_titulo) AS simbolos,
       count(DISTINCT dia_art) AS dias_activos,
       round(sum(monto) FILTER (WHERE moneda='ARS'), 0) AS monto_ars
FROM operaciones GROUP BY 1 ORDER BY ops DESC LIMIT 10;

-- -----------------------------------------------------------------------------
-- 1.7 Horarios y días inusuales
--     Horario de mercado BYMA (contado): 11:00 a 17:00 hora Argentina.
-- -----------------------------------------------------------------------------
\echo '=== 1.7a Operaciones por día de semana (hora Argentina) ==='
SELECT dow_art,
       (ARRAY['Lun','Mar','Mié','Jue','Vie','Sáb','Dom'])[dow_art] AS dia,
       count(*) AS ops,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct_ops
FROM operaciones GROUP BY 1 ORDER BY 1;

\echo '=== 1.7b Operaciones por hora Argentina ==='
SELECT hora_art, count(*) AS ops,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct_ops,
       CASE WHEN hora_art BETWEEN 11 AND 16 THEN 'mercado' ELSE 'fuera' END AS franja
FROM operaciones GROUP BY 1 ORDER BY 1;

\echo '=== 1.7c Resumen de franjas atípicas ==='
SELECT
    round(100.0 * count(*) FILTER (WHERE hora_art NOT BETWEEN 11 AND 16) / count(*), 2) AS pct_fuera_horario_mercado,
    round(100.0 * count(*) FILTER (WHERE hora_art BETWEEN 0 AND 5) / count(*), 2)        AS pct_madrugada_0a6,
    round(100.0 * count(*) FILTER (WHERE dow_art IN (6,7)) / count(*), 2)                AS pct_fin_de_semana,
    count(*) FILTER (WHERE dow_art IN (6,7))                                             AS ops_fin_de_semana
FROM operaciones;

\echo '=== 1.7d ¿Fuera de horario es un fenómeno de pocos clientes o de todos? (por canal) ==='
SELECT origen,
       round(100.0 * count(*) FILTER (WHERE hora_art NOT BETWEEN 11 AND 16) / count(*), 1) AS pct_fuera_horario,
       round(100.0 * count(*) FILTER (WHERE dow_art = 6) / count(*), 1)                    AS pct_sabado
FROM operaciones GROUP BY 1 ORDER BY 1;

\echo '=== 1.7e Ventana horaria de cada día: primera y última operación (UTC) ==='
-- Hipótesis: cada día hábil "genera" operaciones desde ~10 UTC hasta ~20 UTC del día siguiente.
-- Los sábados serían entonces la cola del viernes y los lunes / post-feriados arrancan tarde.
SELECT fecha_utc::date AS dia_utc,
       to_char(fecha_utc::date, 'Dy') AS dow,
       count(*) AS ops,
       to_char(min(fecha_utc) AT TIME ZONE 'UTC', 'HH24:MI') AS primera_utc,
       to_char(max(fecha_utc) AT TIME ZONE 'UTC', 'HH24:MI') AS ultima_utc,
       count(*) FILTER (WHERE extract(hour FROM fecha_utc AT TIME ZONE 'UTC') < 10) AS ops_antes_10utc
FROM operaciones
WHERE fecha_utc::date BETWEEN '2026-01-02' AND '2026-01-20'
GROUP BY 1 ORDER BY 1;

\echo '=== 1.7f Días calendario sin ninguna operación (dentro del rango) ==='
SELECT d::date AS dia, to_char(d, 'Dy') AS dow
FROM generate_series('2026-01-01'::date, '2026-03-13'::date, interval '1 day') d
WHERE NOT EXISTS (SELECT 1 FROM operaciones o WHERE o.fecha_utc::date = d::date)
  AND extract(isodow FROM d) <> 7
ORDER BY 1;
