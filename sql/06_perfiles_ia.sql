-- =====================================================================
-- 06_perfiles_ia.sql · Task 04: base de perfiles para el asistente de IA
-- Arma, para cada cliente de la cola de revisión, el perfil estructurado
-- que recibe la IA (mismo formato que el ejemplo de docs/propuesta_ia.md).
-- Salida: outputs/perfiles_clientes_ia.json (un objeto por cliente).
-- Uso: psql -d iol -f sql/06_perfiles_ia.sql
-- Sin datos personales: solo el ID del dataset y métricas agregadas.
-- =====================================================================

\pset format unaligned
\pset tuples_only on
\o outputs/perfiles_clientes_ia.json

WITH ops AS (
    SELECT o.*
    FROM iol.operaciones_enr o
    JOIN iol.clientes_riesgo c USING (id_cliente)
),
canales AS (
    SELECT id_cliente,
           json_object_agg(origen, n ORDER BY n DESC) AS ops_por_canal
    FROM (SELECT id_cliente, origen, count(*) AS n FROM ops GROUP BY 1, 2) t
    GROUP BY 1
),
instrumentos AS (
    SELECT id_cliente,
           json_agg(json_build_object(
               'simbolo', simbolo_titulo,
               'compras', compras,
               'ventas', ventas,
               'monto_ars', monto_ars) ORDER BY n DESC, monto_ars DESC) AS top_instrumentos
    FROM (
        SELECT id_cliente, simbolo_titulo,
               count(*) AS n,
               count(*) FILTER (WHERE tipo_tran = 'Compra') AS compras,
               count(*) FILTER (WHERE tipo_tran = 'Venta')  AS ventas,
               round(sum(monto_ars)) AS monto_ars,
               row_number() OVER (PARTITION BY id_cliente ORDER BY count(*) DESC, sum(monto_ars) DESC) AS rk
        FROM ops GROUP BY 1, 2
    ) t
    WHERE rk <= 5
    GROUP BY 1
),
mismo_dia AS (
    SELECT id_cliente,
           count(*) FILTER (WHERE nc > 0 AND nv > 0) || ' de ' || count(*) AS dias_especie_compra_y_venta_mismo_dia
    FROM (
        SELECT id_cliente, dia_art, simbolo_titulo,
               count(*) FILTER (WHERE tipo_tran = 'Compra') AS nc,
               count(*) FILTER (WHERE tipo_tran = 'Venta')  AS nv
        FROM ops GROUP BY 1, 2, 3
    ) t
    GROUP BY 1
),
fechas AS (
    SELECT id_cliente, min(dia_art) AS primera, max(dia_art) AS ultima,
           round(percentile_cont(0.5) WITHIN GROUP (ORDER BY monto_ars)) AS monto_mediano_op_ars
    FROM ops GROUP BY 1
),
p4 AS (
    SELECT id_cliente,
           json_agg(json_build_object(
               'fecha', to_char(fecha_art, 'YYYY-MM-DD HH24:MI:SS'),
               'operacion', tipo_tran,
               'simbolo', simbolo_titulo,
               'cantidad', cantidad,
               'precio_operado', precio,
               'precio_mercado_dia', round(precio_mediana_dia, 2),
               'canal', origen) ORDER BY fecha_art) AS detalle
    FROM iol.p4_precio_fuera_mercado
    GROUP BY 1
),
pob AS (
    SELECT round(avg(ops), 1) AS prom_ops,
           round(percentile_cont(0.5) WITHIN GROUP (ORDER BY monto_ars)) AS mediana_monto
    FROM iol.perfil_cliente
)
SELECT json_agg(perfil ORDER BY orden, score DESC, monto DESC)
FROM (
    SELECT c.score, c.monto_ars AS monto,
           CASE c.nivel_riesgo WHEN 'Alto' THEN 1 WHEN 'Medio' THEN 2 ELSE 3 END AS orden,
           json_strip_nulls(json_build_object(
               'id_cliente', c.id_cliente,
               'nivel_riesgo', c.nivel_riesgo,
               'score', c.score,
               'reglas_disparadas', c.motivos,
               'canal_principal', c.canal_principal,
               'operaciones_por_canal', ca.ops_por_canal,
               'operaciones_total', c.ops,
               'operaciones_por_mes', json_build_object('enero', c.ops_ene, 'febrero', c.ops_feb, 'marzo_hasta_13', c.ops_mar),
               'monto_por_periodo_ars', json_build_object('enero', round(c.monto_ene), 'febrero_marzo', round(c.monto_feb_mar)),
               'primera_operacion', f.primera,
               'ultima_operacion', f.ultima,
               'dias_activos', c.dias_activos,
               'operaciones_por_dia_activo', round(c.ops::numeric / NULLIF(c.dias_activos, 0), 1),
               'monto_total_ars', round(c.monto_ars),
               'monto_maximo_operacion_ars', round(c.max_monto_op_ars),
               'monto_mediano_operacion_ars', f.monto_mediano_op_ars,
               'especies_distintas', c.simbolos,
               'top_instrumentos', i.top_instrumentos,
               'pct_compras', c.pct_compras,
               'dias_especie_compra_y_venta_mismo_dia', m.dias_especie_compra_y_venta_mismo_dia,
               'operaciones_madrugada', c.ops_madrugada,
               'operaciones_dia_inhabil', c.ops_dia_inhabil,
               'operaciones_precio_fuera_de_mercado', NULLIF(c.ops_precio_fuera, 0),
               'detalle_precio_fuera_de_mercado', p.detalle,
               'diferencia_valor_vs_mercado_ars', round(NULLIF(c.diferencia_valor_ars, 0)),
               'referencia_poblacion', json_build_object(
                   'promedio_operaciones_por_cliente', pob.prom_ops,
                   'mediana_monto_total_por_cliente_ars', pob.mediana_monto)
           )) AS perfil
    FROM iol.clientes_riesgo c
    LEFT JOIN canales ca USING (id_cliente)
    LEFT JOIN instrumentos i USING (id_cliente)
    LEFT JOIN mismo_dia m USING (id_cliente)
    LEFT JOIN fechas f USING (id_cliente)
    LEFT JOIN p4 p USING (id_cliente)
    CROSS JOIN pob
) t;

\o
