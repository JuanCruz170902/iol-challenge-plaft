# Dashboard Power BI — guía de armado

> **Estado:** el dashboard ya está construido como proyecto PBIP (`powerbi/IOL_PLAFT.pbip`). El modelo y las páginas los genera `scripts/build_pbip.py` a partir del esqueleto que crea Power BI Desktop, y leen los CSV de `powerbi/data/`. Esta guía documenta el diseño, y sirve también para rearmarlo a mano o conectándolo directo a PostgreSQL.

Archivo esperado: `powerbi/IOL_PLAFT.pbix`. Capturas: `powerbi/capturas/*.png`, que se referencian en el README.

## 1. Conexión

1. Correr el pipeline (`run_all.ps1` o `run_all.sh`) para que existan las vistas `iol.vw_*`.
2. En Power BI Desktop: **Obtener datos → Base de datos PostgreSQL**. Servidor `localhost`, base de datos `iol`, modo **Importar**.
3. Seleccionar estas 5 vistas del esquema `iol`:

| Vista | Rol | Filas |
|---|---|---|
| `vw_fact_operaciones` | Hechos (1 fila por operación) | 100.000 |
| `vw_dim_cliente` | Dimensión cliente + score de riesgo | 57.655 |
| `vw_dim_calendario` | Calendario, feriados (API) y tipo de cambio | 90 |
| `vw_cliente_mes` | Actividad por cliente y mes | ~69.500 |
| `vw_api_log` | Trazabilidad de las llamadas a la API | 5 |

> Si no tenés PostgreSQL a mano, `outputs/clientes_riesgo.csv` alcanza para armar la página de "Cola de revisión".

## 2. Modelo

Relaciones (todas de uno a varios, filtro en una sola dirección):

- `vw_dim_cliente[id_cliente]` 1 → * `vw_fact_operaciones[id_cliente]`
- `vw_dim_calendario[fecha]` 1 → * `vw_fact_operaciones[fecha]`
- `vw_dim_cliente[id_cliente]` 1 → * `vw_cliente_mes[id_cliente]`

Ajustes de columnas:
- `vw_dim_cliente[nivel_riesgo]` → **Ordenar por columna** `orden_nivel`.
- `vw_dim_calendario[dia_semana]` → ordenar por `dow`.
- Ocultar las columnas técnicas: `orden_nivel`, `dow` y los IDs del lado "muchos".

## 3. Medidas DAX (tabla `_Medidas`)

```DAX
Operaciones = COUNTROWS ( vw_fact_operaciones )

Clientes = DISTINCTCOUNT ( vw_fact_operaciones[id_cliente] )

Monto ARS = SUM ( vw_fact_operaciones[monto_ars] )

Monto ARS (M) = DIVIDE ( [Monto ARS], 1e6 )

Ops por cliente = DIVIDE ( [Operaciones], [Clientes] )

% Fuera de horario =
DIVIDE (
    CALCULATE ( [Operaciones], vw_fact_operaciones[franja_horaria] <> "Mercado (11-17)" ),
    [Operaciones]
)

% Día inhábil =
DIVIDE (
    CALCULATE ( [Operaciones], vw_fact_operaciones[tipo_dia] <> "Día hábil" ),
    [Operaciones]
)

Clientes en alerta =
CALCULATE ( DISTINCTCOUNT ( vw_dim_cliente[id_cliente] ), vw_dim_cliente[nivel_riesgo] <> "Sin alerta" )

Clientes riesgo Alto =
CALCULATE ( DISTINCTCOUNT ( vw_dim_cliente[id_cliente] ), vw_dim_cliente[nivel_riesgo] = "Alto" )

% Monto en alerta =
DIVIDE (
    CALCULATE ( [Monto ARS], vw_dim_cliente[nivel_riesgo] <> "Sin alerta" ),
    CALCULATE ( [Monto ARS], REMOVEFILTERS ( vw_dim_cliente ) )
)

Ops precio fuera de mercado =
CALCULATE ( [Operaciones], vw_fact_operaciones[flag_precio_fuera_mercado] = TRUE () )

Diferencia de valor ARS (M) = DIVIDE ( SUM ( vw_dim_cliente[diferencia_valor_ars] ), 1e6 )

-- Curva de Pareto: % acumulado del monto según ranking de clientes
Rank cliente monto =
RANKX ( ALL ( vw_dim_cliente[id_cliente] ), CALCULATE ( [Monto ARS] ),, DESC, DENSE )

% Acumulado monto =
VAR r = [Rank cliente monto]
RETURN
DIVIDE (
    SUMX (
        FILTER ( ALL ( vw_dim_cliente[id_cliente] ), [Rank cliente monto] <= r ),
        CALCULATE ( [Monto ARS] )
    ),
    CALCULATE ( [Monto ARS], ALL ( vw_dim_cliente ) )
)
```

> Si `% Acumulado monto` sobre 57 mil clientes resulta lenta, la curva se puede armar con la tabla precalculada de `01_exploracion.sql` (bloque 1.6b), cargándola como tabla aparte.

## 4. Páginas y visuales

Paleta sugerida: neutros para el contexto y un solo color de acento para las alertas. Alto = rojo, Medio = ámbar, Bajo = gris y Sin alerta = gris claro.

### Página 1 — Resumen (`capturas/01_resumen.png`)
- **Fila de tarjetas:** Operaciones · Clientes · Monto ARS (M) · % Fuera de horario · Clientes en alerta · Clientes riesgo Alto.
- **Columnas** `Operaciones` por `vw_dim_calendario[fecha]`, con leyenda `tipo_dia`: muestra que hay actividad los sábados y que no la hay en los feriados de la API.
- **Barras horizontales** `Operaciones` por `canal`.
- **Barras** `Monto ARS (M)` por `vw_dim_cliente[nivel_riesgo]`, para ver cuánto volumen está en alerta.

### Página 2 — Exploración (`capturas/02_exploracion.png`)
- **Matriz de calor**: filas `vw_fact_operaciones[hora_art]`, columnas `vw_dim_calendario[dia_semana]`, valor `Operaciones`, con formato condicional de escala de color de fondo. Es el visual clave: muestra que la actividad se reparte en las 24 horas y que el lunes arranca tarde.
- **Barras 100% apiladas**: `canal` × `franja_horaria`. Todos los canales quedan iguales, lo que indica un fenómeno estructural.
- **Tabla Top 15 instrumentos**: `simbolo_titulo`, `Operaciones`, `Clientes`, `Monto ARS (M)`.
- **Distribución de clientes**: columnas `vw_dim_cliente[ops]` agrupadas en intervalos (1, 2, 3–5, 6–10, 11–50, >50) con el recuento de clientes.

### Página 3 — Patrones (`capturas/03_patrones.png`)
- **P1 Rankings**: dos gráficos de barras horizontales con el **Top 10 de clientes por monto (ARS M)** y el **Top 10 por cantidad de operaciones**, coloreados por `nivel_riesgo`. Reemplazan al gráfico de dispersión en escala logarítmica porque se leen sin explicación.
- **P3 Columnas agrupadas** desde `vw_cliente_mes`: `ops` por `mes`, filtrado con `p3_cambio_brusco = Verdadero`. Conviene sumar un segmentador de `id_cliente`.
- **P4 Tabla** de operaciones con `flag_precio_fuera_mercado = Verdadero`: cliente, canal, fecha, símbolo, cantidad, precio y `ratio_vs_mercado`.
- **P2 Tarjeta / texto**: "Fuera de horario es estructural: 70% en todos los canales", junto a la medida `% Fuera de horario` desagregada por canal.

### Página 4 — Cola de revisión (`capturas/04_cola_revision.png`)
- **Segmentadores**: `nivel_riesgo`, `canal_principal` y los flags P1 a P4.
- **Tabla**: `id_cliente`, `nivel_riesgo`, `score_riesgo`, `motivos`, `ops`, `Monto ARS (M)`, `canal_principal`, ordenada por score y monto. Agregar formato condicional por icono en `nivel_riesgo`.
- **Detalle** con clic derecho sobre un cliente → Obtener detalles → Página 5.

### Página 5 — Detalle de cliente (página de obtención de detalles por `id_cliente`) (`capturas/05_detalle_cliente.png`)
- **Tarjetas**: score, nivel, motivos, ops, monto, canal.
- **Columnas** `Operaciones` por `fecha` para ese cliente.
- **Tabla de operaciones**: fecha_art, tipo_tran, simbolo_titulo, cantidad, precio, monto_ars y flags.
- Para la captura del README, usar **CLIBDBEB632** (cambio brusco por API) o **CLI74090760** (precio fuera de mercado).

### Página 6 — Datos externos (API) (`capturas/06_api.png`)
- **Línea**: `vw_dim_calendario[tc_ars_por_usd]` por fecha, con leyenda `fuente_tc`.
- **Tabla** `vw_api_log`: qué API respondió, cuál falló y qué fallback se usó.
- **Tabla de feriados**: `vw_dim_calendario` filtrado por `feriado` no vacío.

## 5. Capturas para el README

Exportar cada página con **Archivo → Exportar → PDF**, o con la herramienta de recorte de Windows, como PNG de unos 1600 px de ancho. Guardarlas en `powerbi/capturas/` con los nombres indicados arriba.
