# TASK 04 — Propuesta de uso de IA

## Caso de uso: redactar la ficha de alerta de cada cliente de la cola de revisión

**Dónde agrega valor.** El análisis SQL ya identifica a quién mirar: `clientes_riesgo` deja unos 450 clientes con motivo y score. El cuello de botella está después. El analista tiene que abrir el detalle de cada cliente, entender qué pasó, armar una hipótesis y decidir el siguiente paso. Con la tabla de flags sola, eso lleva entre 15 y 30 minutos por caso.

**Qué hace la IA.** Recibe el perfil estructurado del cliente (los números que ya calculó el SQL, sin datos personales) y devuelve una **ficha de alerta en lenguaje natural** con este contenido:

1. Un resumen de lo observado en 3 a 4 líneas.
2. La hipótesis de riesgo y la hipótesis benigna, las dos juntas.
3. Qué información o documentación pedir para descartar una u otra.
4. Una prioridad sugerida (Alta / Media / Baja) con su justificación.

**Por qué este punto y no otro.**
- La detección queda en reglas transparentes (SQL), que son auditables y explicables ante el regulador. Que el LLM *decida* quién es sospechoso es más difícil de auditar.
- La IA trabaja sobre la parte que más tiempo consume y que mejor resuelve: leer números y redactar.
- Escala de forma lineal. Si la cola pasa de 450 a 4.500 clientes, la ficha se genera en segundos y el analista dedica su tiempo a decidir.

**Qué no hace.** No marca ni desmarca clientes, no bloquea cuentas y no reporta a la UIF. Es un borrador que el analista valida.

---

## Prompt

Prompt de sistema (fijo):

```text
Sos un analista senior de Prevención de Lavado de Activos y Fraude (PLAFT) en un broker de bolsa
argentino. Vas a recibir el perfil de actividad de UN cliente que ya fue marcado por reglas
automáticas. Tu tarea es redactar una ficha de alerta para que un analista humano decida.

Reglas:
- Basate SOLO en los datos provistos. Si algo no se puede afirmar con esos datos, decilo.
- Presentá siempre una hipótesis de riesgo Y una explicación benigna plausible.
- No uses lenguaje acusatorio ni concluyas que hubo fraude o lavado.
- Sugerí qué información pedir o revisar para confirmar o descartar (máximo 4 puntos).
- Prioridad sugerida: Alta / Media / Baja, con una línea de justificación.
- Respondé en español, en JSON con las claves:
  resumen, hipotesis_riesgo, hipotesis_benigna, verificaciones, prioridad, justificacion_prioridad
```

Mensaje de usuario, con **datos reales del dataset** (cliente `CLIBDBEB632`, generado desde `clientes_riesgo` y `operaciones_enr`):

```json
{
  "id_cliente": "CLIBDBEB632",
  "reglas_disparadas": ["Cambio brusco feb-mar", "Actividad top 0,1%"],
  "score": 4,
  "canal": "API (100% de las operaciones)",
  "operaciones_por_mes": {"enero": 0, "febrero": 40, "marzo_hasta_13": 242},
  "primera_operacion": "2026-02-26",
  "dias_activos": 12,
  "operaciones_por_dia_activo": 23.5,
  "promedio_poblacion_ops_por_cliente": 1.7,
  "monto_total_ars": 177776,
  "monto_promedio_por_operacion_ars": 630,
  "instrumentos": [
    {"simbolo": "COME", "compras": 69, "ventas": 23},
    {"simbolo": "BYMA", "compras": 42, "ventas": 16},
    {"simbolo": "ALUA", "compras": 42, "ventas": 13},
    {"simbolo": "VALO", "compras": 25, "ventas": 9},
    {"simbolo": "TXAR", "compras": 24, "ventas": 19}
  ],
  "nominales_por_orden": {"min": 1, "max": 21},
  "dias_especie_con_compra_y_venta_el_mismo_dia": "37 de 55",
  "pct_compras": 71.6
}
```

## Resultado esperado (salida obtenida con Claude para este caso)

```json
{
  "resumen": "Cliente sin actividad en enero que empieza a operar el 26/02 exclusivamente por API y llega a 282 operaciones en 12 días (23,5 por día activo, frente a un promedio de 1,7 operaciones por cliente en todo el trimestre). Opera solo 5 acciones locales, en 37 de 55 combinaciones día-especie compra y vende la misma especie en el mismo día, con órdenes de 1 a 21 nominales y un monto total bajo (ARS 178 mil).",
  "hipotesis_riesgo": "Patrón compatible con prueba o calibración de un algoritmo sobre especies de menor liquidez (COME, VALO, BYMA). A mayor escala, este tipo de compra-venta repetida de baja cantidad puede usarse para generar volumen artificial o mover el precio de cierre (wash trading / layering). También es compatible con una cuenta nueva que se usa para probar la operatoria antes de operar montos mayores.",
  "hipotesis_benigna": "Un desarrollador o inversor minorista que conectó un bot propio a la API y lo está probando con montos mínimos para limitar pérdidas. El monto total es bajo y no hay transferencia de valor evidente.",
  "verificaciones": [
    "Fecha de alta de la cuenta y de habilitación de la API (¿coincide con el 26/02?)",
    "Si hay otras cuentas operando del otro lado de las mismas especies y minutos (posible contraparte vinculada)",
    "Impacto de sus órdenes en el precio de cierre de COME y VALO en los días de mayor actividad (03 al 05/03)",
    "Perfil del inversor declarado y origen de los fondos depositados"
  ],
  "prioridad": "Media",
  "justificacion_prioridad": "La frecuencia y el cambio de comportamiento son extremos, pero el monto en juego es bajo; conviene revisarlo antes de que escale de volumen."
}
```

## Qué hace el analista con la ficha

1. **Lee la ficha y valida los números** contra el dashboard (página "Detalle de cliente"). La IA no puede inventar cifras, porque solo recibe las del SQL.
2. **Decide**: cierra el caso como "explicado", pide la información sugerida al área comercial o de cumplimiento, o lo eleva a un análisis profundo o a un eventual ROS.
3. **Registra su decisión** junto a la ficha. Con esas decisiones acumuladas se pueden recalibrar después los pesos del score (qué reglas terminan en casos reales) y medir cuánto acierta la prioridad sugerida.

## Implementación sugerida (no requerida en el challenge)

- Un job diario toma `clientes_riesgo` con score ≥ 2, arma el JSON de cada cliente con una query y llama a la API del modelo (Claude, por ejemplo) con salida estructurada en JSON.
- La ficha se guarda en una tabla `fichas_alerta (id_cliente, fecha, ficha_json, modelo, decision_analista)` que Power BI muestra en la página de detalle.
- **Cuidados:** se envían solo IDs ofuscados y métricas agregadas, sin datos personales. Se versiona el prompt, se audita una muestra de fichas por mes y se dejan registrados el modelo y la versión de prompt usados en cada ficha.
