-- =============================================================================
-- 04_vistas_powerbi.sql — Capa semántica para el dashboard de Power BI
-- Requiere: 00 → 02 → 03
-- Power BI se conecta a PostgreSQL (Obtener datos → Base de datos PostgreSQL),
-- base "iol", y se importan SOLO estas 5 vistas (esquema iol, prefijo vw_).
-- =============================================================================
SET search_path TO iol;
SET client_min_messages = warning;

-- Hechos: una fila por operación, con las marcas de anomalía a nivel operación
CREATE OR REPLACE VIEW vw_fact_operaciones AS
SELECT o.id_transaccion,
       o.id_cliente,
       o.fecha_art,
       o.dia_art                       AS fecha,
       o.hora_art,
       o.franja_horaria,
       o.tipo_dia,
       o.tipo_tran,
       o.origen                        AS canal,
       o.moneda,
       o.simbolo_titulo,
       o.descripcion_titulo,
       CASE WHEN o.descripcion_titulo ILIKE 'cedear%' THEN 'CEDEAR'
            WHEN o.descripcion_titulo ILIKE '%opci%' OR o.simbolo_titulo ~ '^[A-Z]{3}[CV]\d' THEN 'Opción'
            WHEN o.descripcion_titulo ILIKE '%bono%' OR o.descripcion_titulo ILIKE '%rep. arg%'
              OR o.simbolo_titulo ~ '^(AL|GD|AE|TX|TZ|S\d)' THEN 'Bono / Letra'
            ELSE 'Acción / Otro' END   AS familia_instrumento,
       o.cantidad,
       o.precio,
       o.monto                         AS monto_moneda_original,
       o.tc_ars_por_usd,
       o.monto_ars,
       (p4.id_transaccion IS NOT NULL) AS flag_precio_fuera_mercado,
       p4.ratio_vs_mercado,
       (o.monto_ars >= u.p999_monto_op) AS flag_operacion_extrema
FROM operaciones_enr o
CROSS JOIN umbrales u
LEFT JOIN p4_precio_fuera_mercado p4 USING (id_transaccion);

-- Dimensión cliente: perfil + score (los clientes sin alertas quedan con nivel 'Sin alerta')
CREATE OR REPLACE VIEW vw_dim_cliente AS
SELECT p.id_cliente,
       p.canal_principal,
       p.canales,
       p.ops,
       p.dias_activos,
       p.simbolos,
       p.simbolo_principal,
       p.monto_ars,
       p.pct_compras,
       p.ops_ene, p.ops_feb, p.ops_mar,
       p.monto_ene, p.monto_feb_mar,
       coalesce(r.score, 0)                    AS score_riesgo,
       coalesce(r.nivel_riesgo, 'Sin alerta')  AS nivel_riesgo,
       CASE coalesce(r.nivel_riesgo, 'Sin alerta')
            WHEN 'Alto' THEN 1 WHEN 'Medio' THEN 2 WHEN 'Bajo' THEN 3 ELSE 4 END AS orden_nivel,
       coalesce(r.motivos, '')                 AS motivos,
       coalesce(r.f_actividad_alta, false)     AS p1_actividad_alta,
       coalesce(r.f_horario_atipico, false)    AS p2_horario_atipico,
       coalesce(r.f_cambio_brusco, false)      AS p3_cambio_brusco,
       coalesce(r.f_sin_historial_monto_alto, false) AS p3_sin_historial_monto_alto,
       coalesce(r.f_precio_fuera_mercado, false)     AS p4_precio_fuera_mercado,
       coalesce(r.diferencia_valor_ars, 0)     AS diferencia_valor_ars
FROM perfil_cliente p
LEFT JOIN clientes_riesgo r USING (id_cliente);

-- Calendario con feriados (API) y tipo de cambio diario
CREATE OR REPLACE VIEW vw_dim_calendario AS
SELECT c.fecha,
       c.dow,
       (ARRAY['Lun','Mar','Mié','Jue','Vie','Sáb','Dom'])[c.dow] AS dia_semana,
       to_char(c.fecha, 'YYYY-MM') AS anio_mes,
       c.es_habil,
       c.feriado,
       t.tc_ars_por_usd,
       t.fuente_tc
FROM calendario c
LEFT JOIN tipo_cambio_diario t USING (fecha)
WHERE c.fecha BETWEEN '2026-01-01' AND '2026-03-31';

-- Evolución de la actividad de cada cliente por mes (para el visual de "cambio brusco")
CREATE OR REPLACE VIEW vw_cliente_mes AS
SELECT id_cliente, mes, count(*) AS ops, sum(monto_ars) AS monto_ars
FROM operaciones_enr GROUP BY 1, 2;

-- Trazabilidad de la integración con APIs (para mostrar en el dashboard qué fuente se usó)
CREATE OR REPLACE VIEW vw_api_log AS
SELECT ts_utc, api, url, estado, filas, detalle FROM api_log;

-- Export liviano para quien no levante la base: cola de revisión priorizada
\copy (SELECT * FROM vw_dim_cliente WHERE nivel_riesgo <> 'Sin alerta' ORDER BY score_riesgo DESC, monto_ars DESC) TO 'outputs/clientes_riesgo.csv' WITH (FORMAT csv, HEADER true)

SELECT 'vw_fact_operaciones' AS vista, count(*) FROM vw_fact_operaciones
UNION ALL SELECT 'vw_dim_cliente', count(*) FROM vw_dim_cliente
UNION ALL SELECT 'vw_dim_calendario', count(*) FROM vw_dim_calendario
UNION ALL SELECT 'vw_cliente_mes', count(*) FROM vw_cliente_mes
UNION ALL SELECT 'vw_api_log', count(*) FROM vw_api_log;
