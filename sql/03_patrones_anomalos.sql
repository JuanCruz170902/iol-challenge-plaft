-- =============================================================================
-- 03_patrones_anomalos.sql — TASK 02: identificación de patrones anómalos
-- Requiere: 00_carga.sql, 02_api_enriquecimiento.sql (usa monto_ars y calendario)
--
-- Criterio general: un comportamiento es "anómalo" cuando se aparta mucho de la línea
-- base de la población Y ese apartamiento tiene una lectura de riesgo para PLAFT
-- (lavado, manipulación de precios, toma de cuenta, cuentas "mula").
-- Usamos umbrales por percentil (top 0,1%) o por múltiplos de la mediana: son fáciles
-- de explicar al área de negocio y robustos a la asimetría extrema del dataset.
--
-- Patrones:
--   P1  Actividad inusualmente alta (frecuencia y/o volumen en ARS)
--   P2  Horarios y días atípicos (primero se mide si es un fenómeno estructural)
--   P3  Cambio brusco de comportamiento (enero vs febrero-marzo)
--   P4  Operaciones a precio fuera de mercado
--   ==> Score de riesgo por cliente (tabla clientes_riesgo)
-- =============================================================================
SET search_path TO iol;
SET client_min_messages = warning;
\pset footer off

-- Perfil base por cliente (lo usan todos los patrones) -----------------------
DROP TABLE IF EXISTS perfil_cliente CASCADE;
CREATE TABLE perfil_cliente AS
SELECT id_cliente,
       count(*)                                                    AS ops,
       sum(monto_ars)                                              AS monto_ars,
       max(monto_ars)                                              AS max_monto_op_ars,
       count(DISTINCT dia_art)                                     AS dias_activos,
       count(DISTINCT simbolo_titulo)                              AS simbolos,
       count(DISTINCT origen)                                      AS canales,
       mode() WITHIN GROUP (ORDER BY origen)                       AS canal_principal,
       mode() WITHIN GROUP (ORDER BY simbolo_titulo)               AS simbolo_principal,
       round(100.0 * count(*) FILTER (WHERE tipo_tran = 'Compra') / count(*), 1) AS pct_compras,
       count(*) FILTER (WHERE franja_horaria = 'Madrugada (0-6)')  AS ops_madrugada,
       count(*) FILTER (WHERE tipo_dia <> 'Día hábil')             AS ops_dia_inhabil,
       count(*) FILTER (WHERE mes = '2026-01-01')                  AS ops_ene,
       count(*) FILTER (WHERE mes = '2026-02-01')                  AS ops_feb,
       count(*) FILTER (WHERE mes = '2026-03-01')                  AS ops_mar,
       coalesce(sum(monto_ars) FILTER (WHERE mes = '2026-01-01'), 0) AS monto_ene,
       coalesce(sum(monto_ars) FILTER (WHERE mes >= '2026-02-01'), 0) AS monto_feb_mar
FROM operaciones_enr
GROUP BY id_cliente;
ALTER TABLE perfil_cliente ADD PRIMARY KEY (id_cliente);

-- Umbrales de referencia (se calculan, no se hardcodean) ---------------------
DROP TABLE IF EXISTS umbrales CASCADE;
CREATE TABLE umbrales AS
SELECT
    percentile_cont(0.999) WITHIN GROUP (ORDER BY ops)       AS p999_ops,
    percentile_cont(0.999) WITHIN GROUP (ORDER BY monto_ars) AS p999_monto_cliente,
    percentile_cont(0.50)  WITHIN GROUP (ORDER BY ops)       AS p50_ops,
    percentile_cont(0.50)  WITHIN GROUP (ORDER BY monto_ars) AS p50_monto_cliente,
    (SELECT percentile_cont(0.999) WITHIN GROUP (ORDER BY monto_ars) FROM operaciones_enr) AS p999_monto_op,
    (SELECT avg((franja_horaria = 'Madrugada (0-6)')::int) FROM operaciones_enr)          AS base_madrugada,
    (SELECT avg((tipo_dia <> 'Día hábil')::int) FROM operaciones_enr)                      AS base_inhabil
FROM perfil_cliente;

\echo '=== Umbrales calculados ==='
SELECT round(p999_ops::numeric, 0) AS p999_ops_cliente,
       round(p999_monto_cliente::numeric, 0) AS p999_monto_cliente_ars,
       round(p50_monto_cliente::numeric, 0)  AS mediana_monto_cliente_ars,
       round(p999_monto_op::numeric, 0)      AS p999_monto_operacion_ars,
       round(100 * base_madrugada, 1) AS pct_base_madrugada,
       round(100 * base_inhabil, 1)   AS pct_base_dia_inhabil
FROM umbrales;

-- =============================================================================
-- P1  ACTIVIDAD INUSUALMENTE ALTA
-- Criterio: cliente en el top 0,1% por cantidad de operaciones O por monto total en ARS.
-- Por qué: el 71% de los clientes opera 1 sola vez; quien opera cientos de veces o mueve
-- cientos de millones concentra exposición. Se cruza con canal e instrumentos para separar
-- perfiles explicables (algorítmico vía API, tesorería vía IOLnet) de los que no lo son.
-- =============================================================================
DROP TABLE IF EXISTS p1_actividad_alta CASCADE;
CREATE TABLE p1_actividad_alta AS
SELECT p.*,
       round(p.monto_ars / u.p50_monto_cliente::numeric, 0) AS veces_mediana_monto,
       (p.ops >= u.p999_ops)                                 AS por_frecuencia,
       (p.monto_ars >= u.p999_monto_cliente)                 AS por_monto
FROM perfil_cliente p CROSS JOIN umbrales u
WHERE p.ops >= u.p999_ops OR p.monto_ars >= u.p999_monto_cliente;

\echo '=== P1a Resumen: clientes en el top 0,1% y peso en el total ==='
SELECT count(*) AS clientes,
       count(*) FILTER (WHERE por_frecuencia) AS por_frecuencia,
       count(*) FILTER (WHERE por_monto)      AS por_monto,
       count(*) FILTER (WHERE por_frecuencia AND por_monto) AS ambos,
       round(100.0 * sum(ops) / (SELECT sum(ops) FROM perfil_cliente), 2)            AS pct_ops_total,
       round(100.0 * sum(monto_ars) / (SELECT sum(monto_ars) FROM perfil_cliente), 2) AS pct_monto_total
FROM p1_actividad_alta;

\echo '=== P1b Top 15 por monto en ARS ==='
SELECT id_cliente, canal_principal, ops, dias_activos, simbolos, simbolo_principal,
       round(monto_ars / 1e6, 1) AS monto_ars_mill, veces_mediana_monto, pct_compras
FROM p1_actividad_alta ORDER BY monto_ars DESC LIMIT 15;

\echo '=== P1c Top 10 por frecuencia ==='
SELECT id_cliente, canal_principal, ops, dias_activos, round(ops::numeric / dias_activos, 1) AS ops_por_dia,
       simbolos, simbolo_principal, round(monto_ars / 1e6, 1) AS monto_ars_mill
FROM p1_actividad_alta ORDER BY ops DESC LIMIT 10;

\echo '=== P1d ¿En qué canales operan? (vs. población) ==='
SELECT o.origen,
       round(100.0 * count(*) FILTER (WHERE a.id_cliente IS NOT NULL) / sum(count(*) FILTER (WHERE a.id_cliente IS NOT NULL)) OVER (), 1) AS pct_ops_top01,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct_ops_poblacion
FROM operaciones_enr o LEFT JOIN p1_actividad_alta a USING (id_cliente)
GROUP BY o.origen ORDER BY 2 DESC;

\echo '=== P1e ¿En qué instrumentos? (top 10 símbolos por monto de estos clientes) ==='
SELECT o.simbolo_titulo, min(o.descripcion_titulo) AS descripcion, count(*) AS ops,
       count(DISTINCT o.id_cliente) AS clientes_top01,
       round(sum(o.monto_ars) / 1e6, 1) AS monto_ars_mill
FROM operaciones_enr o JOIN p1_actividad_alta a USING (id_cliente)
GROUP BY o.simbolo_titulo ORDER BY sum(o.monto_ars) DESC LIMIT 10;

\echo '=== P1f Operaciones individuales extremas (monto >= p99,9 de operaciones) por canal ==='
SELECT origen, count(*) AS ops_extremas, count(DISTINCT id_cliente) AS clientes,
       round(sum(monto_ars) / 1e6, 1) AS monto_ars_mill
FROM operaciones_enr, umbrales
WHERE monto_ars >= p999_monto_op
GROUP BY origen ORDER BY ops_extremas DESC;

-- =============================================================================
-- P2  HORARIOS Y DÍAS ATÍPICOS
-- Paso 1: ¿la actividad fuera de horario es de pocos clientes o de todos?
-- Paso 2: si es estructural, el horario absoluto no discrimina. Medimos entonces la
--         desviación de cada cliente respecto de la línea base con un z-score binomial:
--         z = (observado - esperado) / sqrt(n·p·(1-p)). Se marca z >= 3 con >= 10 ops.
-- =============================================================================
\echo '=== P2a Paso 1: concentración de las operaciones en día inhábil ==='
WITH s AS (
    SELECT id_cliente, count(*) AS n FROM operaciones_enr WHERE tipo_dia <> 'Día hábil' GROUP BY 1
), r AS (SELECT n, row_number() OVER (ORDER BY n DESC) AS rk FROM s)
SELECT (SELECT count(*) FROM s)                                   AS clientes_con_ops_inhabil,
       sum(n)                                                      AS ops_inhabil,
       round(100.0 * sum(n) FILTER (WHERE rk <= 10) / sum(n), 2)   AS pct_explicado_top10_clientes,
       round(100.0 * sum(n) FILTER (WHERE rk <= 100) / sum(n), 2)  AS pct_explicado_top100_clientes
FROM r;

\echo '=== P2b Paso 1: mismo análisis por franja horaria y canal (si todos ~iguales => estructural) ==='
SELECT origen,
       round(100.0 * avg((franja_horaria = 'Madrugada (0-6)')::int), 1) AS pct_madrugada,
       round(100.0 * avg((franja_horaria = 'Mercado (11-17)')::int), 1) AS pct_mercado,
       round(100.0 * avg((tipo_dia <> 'Día hábil')::int), 1)           AS pct_dia_inhabil
FROM operaciones_enr GROUP BY 1 ORDER BY 1;

\echo '=== P2c Paso 1: los "sábados" son la continuación del viernes (primer y último horario por día de semana, UTC) ==='
SELECT to_char(fecha_utc AT TIME ZONE 'UTC', 'ID Dy') AS dia_semana_utc,
       to_char(min((fecha_utc AT TIME ZONE 'UTC')::time), 'HH24:MI') AS hora_min,
       to_char(max((fecha_utc AT TIME ZONE 'UTC')::time), 'HH24:MI') AS hora_max,
       count(*) AS ops
FROM operaciones_enr GROUP BY 1 ORDER BY 1;

DROP TABLE IF EXISTS p2_horario_atipico CASCADE;
CREATE TABLE p2_horario_atipico AS
SELECT p.id_cliente, p.canal_principal, p.ops, p.ops_madrugada, p.ops_dia_inhabil,
       round(((p.ops_madrugada - p.ops * u.base_madrugada) / sqrt(p.ops * u.base_madrugada * (1 - u.base_madrugada)))::numeric, 2) AS z_madrugada,
       round(((p.ops_dia_inhabil - p.ops * u.base_inhabil) / sqrt(p.ops * u.base_inhabil * (1 - u.base_inhabil)))::numeric, 2)       AS z_inhabil,
       round(p.monto_ars / 1e6, 2) AS monto_ars_mill
FROM perfil_cliente p CROSS JOIN umbrales u
WHERE p.ops >= 10;

\echo '=== P2d Paso 2: clientes con desvío significativo (z >= 3) sobre su propia cantidad de operaciones ==='
SELECT count(*) AS clientes_evaluados_10mas_ops,
       count(*) FILTER (WHERE z_madrugada >= 3) AS z_madrugada_3,
       count(*) FILTER (WHERE z_inhabil >= 3)   AS z_inhabil_3,
       round(count(*) * 0.00135, 1)             AS esperados_por_azar_cada_uno
FROM p2_horario_atipico;

SELECT id_cliente, canal_principal, ops, ops_madrugada, z_madrugada, ops_dia_inhabil, z_inhabil, monto_ars_mill
FROM p2_horario_atipico
WHERE z_madrugada >= 3 OR z_inhabil >= 3
ORDER BY greatest(z_madrugada, z_inhabil) DESC;

-- =============================================================================
-- P3  CAMBIO BRUSCO DE COMPORTAMIENTO (enero vs febrero-marzo)
-- Normalizamos por días hábiles con operaciones: enero 21, febrero 18, marzo 10 (corte 13/03).
-- Criterio A (frecuencia):         <= 2 ops en enero, >= 10 ops en feb-mar y tasa diaria >= 5x la de enero.
-- Criterio B (monto, con historia): operó en enero; monto feb-mar >= ARS 5 M y >= 10x el de enero.
-- Criterio C (sin historia):        sin operaciones en enero y monto feb-mar >= ARS 5 M.
--   C se separa de A/B porque el dataset no trae fecha de alta: un cliente sin enero puede ser una
--   cuenta nueva (señal de "cuenta mula") o un cliente dormido. Pesa menos en el score.
-- =============================================================================
DROP TABLE IF EXISTS p3_cambio_comportamiento CASCADE;
CREATE TABLE p3_cambio_comportamiento AS
WITH d AS (SELECT 21.0 AS dh_ene, 28.0 AS dh_feb_mar),
x AS (
    SELECT p.*,
           p.ops_feb + p.ops_mar                                   AS ops_feb_mar,
           round(p.ops_ene / d.dh_ene, 3)                          AS tasa_ene,
           round((p.ops_feb + p.ops_mar) / d.dh_feb_mar, 3)        AS tasa_feb_mar,
           round(((p.ops_feb + p.ops_mar) / d.dh_feb_mar) / greatest(p.ops_ene, 1) * d.dh_ene, 1) AS multiplicador_frecuencia,
           CASE WHEN p.monto_ene > 0 THEN round(p.monto_feb_mar / p.monto_ene, 1) END AS multiplicador_monto
    FROM perfil_cliente p, d
)
SELECT x.*,
       (ops_ene <= 2 AND ops_feb_mar >= 10 AND multiplicador_frecuencia >= 5)           AS por_frecuencia,
       (ops_ene > 0 AND monto_feb_mar >= 5e6 AND monto_feb_mar >= 10 * monto_ene)       AS por_monto,
       (ops_ene = 0)                                                                     AS sin_actividad_en_enero,
       CASE WHEN (ops_ene <= 2 AND ops_feb_mar >= 10 AND multiplicador_frecuencia >= 5)
              OR (ops_ene > 0 AND monto_feb_mar >= 5e6 AND monto_feb_mar >= 10 * monto_ene)
            THEN 'Cambio brusco' ELSE 'Sin historial en enero + monto alto' END          AS tipo_cambio
FROM x
WHERE (ops_ene <= 2 AND ops_feb_mar >= 10 AND multiplicador_frecuencia >= 5)
   OR (monto_feb_mar >= 5e6 AND (ops_ene = 0 OR monto_feb_mar >= 10 * monto_ene));

\echo '=== P3a Resumen ==='
SELECT tipo_cambio, count(*) AS clientes,
       count(*) FILTER (WHERE por_frecuencia) AS por_frecuencia,
       count(*) FILTER (WHERE por_monto)      AS por_monto_con_historia,
       count(*) FILTER (WHERE sin_actividad_en_enero) AS sin_actividad_enero,
       round(sum(monto_feb_mar) / 1e6, 1)     AS monto_feb_mar_mill
FROM p3_cambio_comportamiento GROUP BY 1;

\echo '=== P3b Top 15 por salto de frecuencia ==='
SELECT id_cliente, canal_principal, ops_ene, ops_feb, ops_mar, multiplicador_frecuencia,
       round(monto_ene / 1e6, 2) AS monto_ene_mill, round(monto_feb_mar / 1e6, 2) AS monto_feb_mar_mill, simbolo_principal
FROM p3_cambio_comportamiento WHERE por_frecuencia
ORDER BY multiplicador_frecuencia DESC, ops_feb_mar DESC LIMIT 15;

\echo '=== P3c Top 15 por salto de monto (con y sin historial en enero) ==='
SELECT id_cliente, canal_principal, ops_ene, ops_feb + ops_mar AS ops_feb_mar,
       round(monto_ene / 1e6, 2) AS monto_ene_mill, round(monto_feb_mar / 1e6, 2) AS monto_feb_mar_mill,
       coalesce(multiplicador_monto::text, 'nuevo') AS multiplicador_monto, simbolo_principal
FROM p3_cambio_comportamiento WHERE por_monto OR sin_actividad_en_enero AND NOT por_frecuencia
ORDER BY monto_feb_mar DESC LIMIT 15;

-- =============================================================================
-- P4  OPERACIONES A PRECIO FUERA DE MERCADO
-- Criterio: precio < 50% o > 200% de la mediana del mismo instrumento ese mismo día,
-- con al menos 5 operaciones de referencia. Se excluyen opciones (su precio varía
-- mucho intradía y la comparación genera falsos positivos).
-- Por qué: operar muy lejos del precio de mercado es la forma clásica de transferir
-- valor entre cuentas (operaciones "pactadas") o de encubrir un error operativo.
-- =============================================================================
DROP TABLE IF EXISTS p4_precio_fuera_mercado CASCADE;
CREATE TABLE p4_precio_fuera_mercado AS
WITH ref AS (
    SELECT simbolo_titulo, dia_art,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY precio)::numeric AS precio_mediana_dia,
           count(*) AS ops_referencia
    FROM operaciones_enr GROUP BY 1, 2
)
SELECT o.id_transaccion, o.id_cliente, o.fecha_art, o.origen, o.tipo_tran, o.simbolo_titulo, o.descripcion_titulo,
       o.moneda, o.cantidad, o.precio, round(r.precio_mediana_dia, 4) AS precio_mediana_dia, r.ops_referencia,
       round(o.precio / r.precio_mediana_dia, 4) AS ratio_vs_mercado,
       o.monto_ars,
       round(o.cantidad * r.precio_mediana_dia * CASE WHEN o.moneda = 'USD' THEN o.tc_ars_por_usd ELSE 1 END, 2) AS monto_ars_a_precio_mercado
FROM operaciones_enr o
JOIN ref r USING (simbolo_titulo, dia_art)
WHERE r.ops_referencia >= 5
  AND NOT (o.descripcion_titulo ILIKE '%opci%' OR o.simbolo_titulo ~ '^[A-Z]{3}[CV]\d')
  AND (o.precio < 0.5 * r.precio_mediana_dia OR o.precio > 2 * r.precio_mediana_dia);

\echo '=== P4a Resumen ==='
SELECT count(*) AS operaciones, count(DISTINCT id_cliente) AS clientes,
       round(sum(abs(monto_ars_a_precio_mercado - monto_ars)) / 1e6, 1) AS diferencia_valor_ars_mill
FROM p4_precio_fuera_mercado;

\echo '=== P4b Detalle (ordenado por diferencia de valor) ==='
SELECT id_cliente, origen, fecha_art::date AS dia, tipo_tran, simbolo_titulo, cantidad, precio, precio_mediana_dia,
       ratio_vs_mercado, round((monto_ars_a_precio_mercado - monto_ars) / 1e6, 2) AS diferencia_ars_mill
FROM p4_precio_fuera_mercado
ORDER BY abs(monto_ars_a_precio_mercado - monto_ars) DESC LIMIT 20;

-- =============================================================================
-- SCORE DE RIESGO POR CLIENTE
-- Pesos (criterio experto, ajustable):
--   P4 precio fuera de mercado ................ 3  (señal más directa de transferencia de valor)
--   P3 cambio brusco (con historia o frecuencia) 2
--   P1 actividad top 0,1% ..................... 2
--   P3 sin historial en enero + monto alto .... 1  (puede ser alta nueva o cliente dormido)
--   P2 horario atípico (z >= 3) ............... 1  (señal débil: el horario es estructural)
--   Operación individual >= p99,9 ............. 0  (se informa; ya está contenida en P1 por monto)
-- Nivel: Alto >= 4 · Medio 2-3 · Bajo 1
-- =============================================================================
DROP TABLE IF EXISTS clientes_riesgo CASCADE;
CREATE TABLE clientes_riesgo AS
WITH f AS (
    SELECT p.id_cliente,
           (p4.id_cliente IS NOT NULL)                                         AS f_precio_fuera_mercado,
           coalesce(p3.tipo_cambio = 'Cambio brusco', false)                   AS f_cambio_brusco,
           coalesce(p3.tipo_cambio <> 'Cambio brusco', false)                  AS f_sin_historial_monto_alto,
           (p1.id_cliente IS NOT NULL)                                         AS f_actividad_alta,
           (p.max_monto_op_ars >= u.p999_monto_op)                             AS f_operacion_extrema,
           coalesce(p2.z_madrugada >= 3 OR p2.z_inhabil >= 3, false)           AS f_horario_atipico,
           p4.ops_precio_fuera, p4.diferencia_valor_ars
    FROM perfil_cliente p
    CROSS JOIN umbrales u
    LEFT JOIN (SELECT id_cliente, count(*) AS ops_precio_fuera,
                      sum(abs(monto_ars_a_precio_mercado - monto_ars)) AS diferencia_valor_ars
               FROM p4_precio_fuera_mercado GROUP BY 1) p4 USING (id_cliente)
    LEFT JOIN p3_cambio_comportamiento p3 USING (id_cliente)
    LEFT JOIN p1_actividad_alta p1        USING (id_cliente)
    LEFT JOIN p2_horario_atipico p2       USING (id_cliente)
)
SELECT p.id_cliente, p.canal_principal, p.canales, p.ops, p.dias_activos, p.simbolos, p.simbolo_principal,
       round(p.monto_ars, 2) AS monto_ars, round(p.max_monto_op_ars, 2) AS max_monto_op_ars, p.pct_compras,
       p.ops_ene, p.ops_feb, p.ops_mar, round(p.monto_ene, 2) AS monto_ene, round(p.monto_feb_mar, 2) AS monto_feb_mar,
       p.ops_madrugada, p.ops_dia_inhabil,
       f.f_precio_fuera_mercado, f.f_cambio_brusco, f.f_sin_historial_monto_alto, f.f_actividad_alta,
       f.f_operacion_extrema, f.f_horario_atipico,
       coalesce(f.ops_precio_fuera, 0) AS ops_precio_fuera, round(coalesce(f.diferencia_valor_ars, 0), 2) AS diferencia_valor_ars,
       3 * f.f_precio_fuera_mercado::int + 2 * f.f_cambio_brusco::int + 2 * f.f_actividad_alta::int
         + f.f_sin_historial_monto_alto::int + f.f_horario_atipico::int AS score,
       concat_ws(' | ',
           CASE WHEN f.f_precio_fuera_mercado THEN 'Precio fuera de mercado' END,
           CASE WHEN f.f_cambio_brusco        THEN 'Cambio brusco feb-mar' END,
           CASE WHEN f.f_sin_historial_monto_alto THEN 'Sin historial en enero + monto alto' END,
           CASE WHEN f.f_actividad_alta       THEN 'Actividad top 0,1%' END,
           CASE WHEN f.f_operacion_extrema    THEN 'Operación >= p99,9 (info)' END,
           CASE WHEN f.f_horario_atipico      THEN 'Horario atípico (z>=3)' END) AS motivos
FROM perfil_cliente p JOIN f USING (id_cliente)
WHERE f.f_precio_fuera_mercado OR f.f_cambio_brusco OR f.f_sin_historial_monto_alto OR f.f_actividad_alta OR f.f_horario_atipico;

ALTER TABLE clientes_riesgo ADD COLUMN nivel_riesgo text;
UPDATE clientes_riesgo SET nivel_riesgo = CASE WHEN score >= 4 THEN 'Alto' WHEN score >= 2 THEN 'Medio' ELSE 'Bajo' END;

\echo '=== P4c ¿Dónde se concentran los precios fuera de mercado? (canal) ==='
SELECT origen, count(*) AS ops, count(DISTINCT id_cliente) AS clientes,
       count(*) FILTER (WHERE precio IN (0.01, 1) OR round(precio, 2) IN (0.01, 1.00)) AS precio_placeholder_001_o_1
FROM p4_precio_fuera_mercado GROUP BY 1 ORDER BY 2 DESC;

\echo '=== R1 Clientes por nivel de riesgo ==='
SELECT nivel_riesgo, count(*) AS clientes, sum(ops) AS ops, round(sum(monto_ars) / 1e6, 1) AS monto_ars_mill,
       round(100.0 * sum(monto_ars) / (SELECT sum(monto_ars) FROM perfil_cliente), 1) AS pct_monto_total
FROM clientes_riesgo GROUP BY 1 ORDER BY min(score) DESC;

\echo '=== R2 Cola de revisión priorizada (score >= 3) ==='
SELECT id_cliente, nivel_riesgo, score, canal_principal, ops, round(monto_ars / 1e6, 1) AS monto_ars_mill, motivos
FROM clientes_riesgo WHERE score >= 3 ORDER BY score DESC, monto_ars DESC LIMIT 30;
