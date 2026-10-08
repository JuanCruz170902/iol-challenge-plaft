-- =============================================================================
-- 05_export_powerbi.sql — Exporta las tablas que lee el proyecto Power BI (PBIP)
-- Requiere: 00 → 04.  Salida: powerbi/data/*.csv  (UTF-8, separador coma, decimales con punto)
-- El PBIP lee estos CSV, así quien revise el dashboard no necesita PostgreSQL.
-- =============================================================================
SET search_path TO iol;
SET client_min_messages = warning;

-- Hechos
\copy (SELECT id_transaccion, id_cliente, fecha, fecha_art, hora_art, franja_horaria, tipo_dia, tipo_tran, canal, moneda, simbolo_titulo, familia_instrumento, cantidad, precio, monto_ars, flag_precio_fuera_mercado, flag_operacion_extrema, CASE WHEN flag_precio_fuera_mercado THEN 'Sí' ELSE 'No' END AS precio_fuera_mercado FROM vw_fact_operaciones ORDER BY fecha_art, id_transaccion) TO 'powerbi/data/operaciones.csv' WITH (FORMAT csv, HEADER true)

-- Clientes (con log10 para el gráfico de dispersión de outliers)
\copy (SELECT id_cliente, canal_principal, ops, dias_activos, simbolos, round(monto_ars, 2) AS monto_ars, ops_ene, ops_feb, ops_mar, score_riesgo, nivel_riesgo, orden_nivel, motivos, p1_actividad_alta, p2_horario_atipico, p3_cambio_brusco, p3_sin_historial_monto_alto, p4_precio_fuera_mercado, round(diferencia_valor_ars, 2) AS diferencia_valor_ars, round(log(greatest(ops, 1))::numeric, 4) AS log10_ops, round(log(greatest(monto_ars, 1))::numeric, 4) AS log10_monto_ars, row_number() OVER (ORDER BY monto_ars DESC, id_cliente) AS rank_monto, row_number() OVER (ORDER BY ops DESC, monto_ars DESC, id_cliente) AS rank_ops FROM vw_dim_cliente) TO 'powerbi/data/clientes.csv' WITH (FORMAT csv, HEADER true)

-- Calendario + tipo de cambio
\copy (SELECT *, to_char(fecha, 'DD/MM') AS dia_mes, to_char(fecha, 'YYYYMMDD')::int AS fecha_num FROM vw_dim_calendario ORDER BY fecha) TO 'powerbi/data/calendario.csv' WITH (FORMAT csv, HEADER true)

-- Log de APIs
\copy (SELECT api, estado, filas, detalle, url FROM vw_api_log) TO 'powerbi/data/api_log.csv' WITH (FORMAT csv, HEADER true)

-- Top 15 instrumentos
\copy (SELECT row_number() OVER (ORDER BY count(*) DESC) AS ranking, simbolo_titulo || ' (' || moneda || ')' AS instrumento, count(*) AS ops, count(DISTINCT id_cliente) AS clientes, round(sum(monto_ars) / 1e6, 1) AS monto_ars_mill FROM operaciones_enr GROUP BY simbolo_titulo, moneda ORDER BY ops DESC LIMIT 15) TO 'powerbi/data/top_instrumentos.csv' WITH (FORMAT csv, HEADER true)

-- Clientes por tramo de actividad
\copy (WITH c AS (SELECT id_cliente, count(*) AS ops FROM operaciones GROUP BY 1) SELECT CASE WHEN ops = 1 THEN 1 WHEN ops = 2 THEN 2 WHEN ops <= 5 THEN 3 WHEN ops <= 10 THEN 4 WHEN ops <= 50 THEN 5 ELSE 6 END AS orden, CASE WHEN ops = 1 THEN '1 op' WHEN ops = 2 THEN '2 ops' WHEN ops <= 5 THEN '3-5' WHEN ops <= 10 THEN '6-10' WHEN ops <= 50 THEN '11-50' ELSE '>50' END AS tramo, count(*) AS clientes, sum(ops) AS ops FROM c GROUP BY 1, 2 ORDER BY 1) TO 'powerbi/data/tramos_clientes.csv' WITH (FORMAT csv, HEADER true)

-- Curva de concentración (Pareto) sobre monto en ARS homogeneizado
\copy (WITH c AS (SELECT id_cliente, sum(monto_ars) AS m FROM operaciones_enr GROUP BY 1), r AS (SELECT m, row_number() OVER (ORDER BY m DESC) AS rk, count(*) OVER () AS n, sum(m) OVER () AS tot FROM c) SELECT corte AS pct_clientes, 'Top ' || replace(trim_scale(corte)::text, '.', ',') || '%' AS segmento, round(100 * sum(m) FILTER (WHERE rk <= n * corte / 100.0) / max(tot), 2) AS pct_monto FROM r, (VALUES (0.1), (1), (5), (10), (20), (50)) t(corte) GROUP BY corte ORDER BY corte) TO 'powerbi/data/pareto.csv' WITH (FORMAT csv, HEADER true)

-- P3: top 12 clientes con cambio brusco, formato largo (cliente x mes)
\copy (WITH t AS (SELECT id_cliente FROM p3_cambio_comportamiento WHERE tipo_cambio = 'Cambio brusco' ORDER BY multiplicador_frecuencia DESC, ops_feb_mar DESC LIMIT 12) SELECT t.id_cliente, m.mes_orden, m.mes, CASE m.mes_orden WHEN 1 THEN p.ops_ene WHEN 2 THEN p.ops_feb ELSE p.ops_mar END AS ops FROM t JOIN perfil_cliente p USING (id_cliente) CROSS JOIN (VALUES (1, 'Enero'), (2, 'Febrero'), (3, 'Marzo (al 13)')) m(mes_orden, mes) ORDER BY 1, 2) TO 'powerbi/data/p3_top.csv' WITH (FORMAT csv, HEADER true)

-- P4: operaciones a precio fuera de mercado
\copy (SELECT id_cliente, fecha_art::date AS fecha, origen AS canal, tipo_tran, simbolo_titulo, cantidad, precio, precio_mediana_dia, ratio_vs_mercado, round((monto_ars_a_precio_mercado - monto_ars) / 1e6, 2) AS diferencia_ars_mill FROM p4_precio_fuera_mercado ORDER BY abs(monto_ars_a_precio_mercado - monto_ars) DESC) TO 'powerbi/data/p4_precio_fuera_mercado.csv' WITH (FORMAT csv, HEADER true)
