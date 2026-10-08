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

## Resultado obtenido (ChatGPT, con el prompt y los datos de arriba)

```json
{
  "resumen": "Cliente con inicio de actividad el 26/02/2026 y fuerte incremento de operaciones en marzo: 40 operaciones en febrero frente a 242 hasta el 13/03. Registra 23,5 operaciones por día activo, muy por encima del promedio poblacional informado de 1,7. El 100% de las operaciones se realizó vía API, con concentración en cinco especies y operaciones de compra y venta de una misma especie en el mismo día en 37 de 55 días-especie observados. El monto total operado informado es ARS 177.776, con un promedio de ARS 630 por operación.",
  "hipotesis_riesgo": "La combinación de crecimiento muy abrupto de la actividad, frecuencia operativa excepcionalmente superior al promedio, uso exclusivo de API y realización frecuente de compras y ventas de la misma especie durante el mismo día podría resultar compatible con una operatoria automatizada o de alta rotación que amerite revisar su racionalidad económica y consistencia con el perfil declarado. Con los datos disponibles no puede afirmarse que exista lavado de activos, fraude ni otra conducta irregular.",
  "hipotesis_benigna": "La actividad podría responder a una estrategia legítima de trading automatizado mediante API, con operaciones de bajo monto y alta frecuencia, particularmente orientada a capturar movimientos de precios intradiarios. La compra y venta de las mismas especies durante el día también puede ser consistente con una estrategia de rotación o rebalanceo de cartera.",
  "verificaciones": [
    "Revisar el perfil económico, actividad declarada y origen de fondos del cliente, y contrastarlos con el nivel y tipo de operatoria observado.",
    "Analizar el detalle temporal de las operaciones para determinar si existe un patrón sistemático de entrada y salida, incluyendo resultados económicos y frecuencia de reversión.",
    "Verificar qué aplicación, estrategia o tercero utiliza la API y si la operatoria automatizada está autorizada y es consistente con la actividad declarada.",
    "Revisar ingresos y egresos de fondos asociados a la operatoria, contrapartes y eventuales transferencias hacia/desde terceros, si dicha información se encuentra disponible."
  ],
  "prioridad": "Media",
  "justificacion_prioridad": "La alerta presenta indicadores relevantes de comportamiento atípico —especialmente el salto de actividad y la frecuencia operativa—, pero los montos son relativamente bajos y existe una explicación benigna plausible basada en trading automatizado. Se recomienda revisión humana antes de escalar."
}
```

**Lectura del analista sobre esta salida.** La ficha respeta las reglas del prompt: usa solo los datos provistos, no acusa y llega a una prioridad razonable (Media: comportamiento muy atípico pero de monto bajo). Le agregaría una verificación más concreta: buscar si hay **cuentas vinculadas operando del otro lado** de las mismas especies y minutos, y medir el **impacto de sus órdenes en el precio de cierre** de las especies menos líquidas (COME, VALO). Ese es justamente el rol del analista: validar y completar el borrador.

## Qué hace el analista con la ficha

1. **Lee la ficha y valida los números** contra el dashboard (página "Detalle de cliente"). La IA no puede inventar cifras, porque solo recibe las del SQL.
2. **Decide**: cierra el caso como "explicado", pide la información sugerida al área comercial o de cumplimiento, o lo eleva a un análisis profundo o a un eventual ROS.
3. **Registra su decisión** junto a la ficha. Con esas decisiones acumuladas se pueden recalibrar después los pesos del score (qué reglas terminan en casos reales) y medir cuánto acierta la prioridad sugerida.

## Implementación sugerida

**Versión lista para usar:** [`docs/asistente_ia.md`](asistente_ia.md). `sql/06_perfiles_ia.sql` genera la base con el perfil de los 454 clientes de la cola ([`outputs/perfiles_clientes_ia.json`](../outputs/perfiles_clientes_ia.json)). Cargada en un asistente (GPT personalizado, Proyecto de Claude o Gem de Gemini) junto con estas instrucciones, el analista escribe solo el ID del cliente y recibe la ficha, sin copiar datos a mano.

A escala:

- Un job diario toma `clientes_riesgo` con score ≥ 2, arma el JSON de cada cliente con una query y llama a la API del modelo (Claude, por ejemplo) con salida estructurada en JSON.
- La ficha se guarda en una tabla `fichas_alerta (id_cliente, fecha, ficha_json, modelo, decision_analista)` que Power BI muestra en la página de detalle.
- **Cuidados:** se envían solo IDs ofuscados y métricas agregadas, sin datos personales. Se versiona el prompt, se audita una muestra de fichas por mes y se dejan registrados el modelo y la versión de prompt usados en cada ficha.
