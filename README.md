# IOL Inversiones · Challenge PLAFT — Detección de patrones anómalos

**Ruta elegida: C, SQL + Power BI.** El análisis completo está en archivos `.sql` sobre PostgreSQL. Un script corto en Python resuelve la integración con APIs externas, y el dashboard está en Power BI Desktop.

> 📄 El **resumen ejecutivo** para el área de Prevención de Fraude está [al final de este README](#resumen-ejecutivo).

---

## Estructura del repositorio

```
├── data/
│   ├── raw/Challenge_iol_data_set.csv     dataset provisto (100.000 operaciones)
│   └── api/                               salida de las APIs + log de llamadas + snapshot de respaldo
├── scripts/fetch_api.py                   Task 03: llamadas HTTP (solo librería estándar de Python)
├── sql/
│   ├── 00_carga.sql                       esquema, staging y tabla tipada
│   ├── 01_exploracion.sql                 Task 01: exploración y calidad del dato
│   ├── 02_api_enriquecimiento.sql         Task 03: calendario hábil, dólar MEP, montos en ARS
│   ├── 03_patrones_anomalos.sql           Task 02: 4 patrones + score de riesgo por cliente
│   └── 04_vistas_powerbi.sql              capa semántica (vistas vw_*) para el dashboard
├── outputs/                               resultados de cada query (.txt) y cola de revisión (.csv)
├── powerbi/
│   ├── GUIA_DASHBOARD.md                  modelo, medidas DAX y diseño de páginas
│   ├── IOL_PLAFT.pbix                     dashboard
│   └── capturas/                          screenshots usados en este README
├── docs/propuesta_ia.md                   Task 04: caso de uso de IA, prompt y resultado
├── run_all.ps1 / run_all.sh               corre todo el pipeline de punta a punta
```

## Cómo reproducirlo

**Requisitos:** PostgreSQL 14 o superior (`psql` en el PATH), Python 3.9 o superior (sin paquetes extra) y Power BI Desktop.

```powershell
# Windows
$env:PGUSER="postgres"; $env:PGPASSWORD="<tu clave>"
.\run_all.ps1
```
```bash
# Linux / macOS
./run_all.sh
```

El pipeline crea la base `iol` y luego:
1. carga el CSV;
2. corre la exploración;
3. llama a las APIs;
4. enriquece las operaciones;
5. calcula los patrones;
6. publica las vistas `iol.vw_*`.

Los resultados de cada paso quedan en `outputs/`. Para el dashboard: abrir `powerbi/IOL_PLAFT.pbix` y actualizar, o seguir [`powerbi/GUIA_DASHBOARD.md`](powerbi/GUIA_DASHBOARD.md) para armarlo desde cero.

---

## Task 01 — Exploración del dataset

Detalle completo en [`outputs/01_exploracion.txt`](outputs/01_exploracion.txt).

| | |
|---|---|
| Operaciones | 100.000 (70% compras, 30% ventas) |
| Clientes únicos | 57.655 |
| Instrumentos | 1.445 símbolos. CEDEARs 54%, bonos y letras 24%, acciones 20%, opciones 2% |
| Más operados | AL30 (8,9%), AL30D (4,6%), MSFT, SPY, AMZN, MELI |
| Período | 02/01/2026 10:33 UTC → 13/03/2026 19:59 UTC (59 días con actividad) |
| Canales | App Mobile 66%, Web Desktop 29%, Web Responsive 2,7%, API 1,7%, IOLnet 0,3% |
| Monedas | ARS 85% de las operaciones; USD 15% (21% del volumen convertido a pesos) |

**¿Qué tan limpio está?** Estructuralmente está limpio: no hay nulos, IDs duplicados, duplicados lógicos ni cantidades o precios ≤ 0. Aparecieron estas particularidades:

- **Montos en rangos extremos.** La mediana de una operación en ARS es $34 mil y el máximo es $1.473 millones, unas 42.000 veces más. Las cantidades nominales llegan a 1.500 millones (Letras del Tesoro operadas por IOLnet).
- **Precios "placeholder".** Algunas operaciones de IOLnet tienen precio 1,00 o 0,01 en especies que cotizan entre $1,40 y $4.500. Ver el patrón P4.
- **Milisegundos .010.** El 96% de las operaciones de IOLnet tiene marca `.010Z` y el resto del dataset tiene `.000Z`. Probablemente IOLnet se carga por otra vía de integración. Es un dato útil para el área de datos.
- **Distribución por cliente muy asimétrica.** El 71% de los clientes opera una sola vez. El 1% más activo explica el 12% de las operaciones y el 59% del monto en pesos. Un solo cliente explica el 18% de todo el volumen.
- **Horarios y días.** El 70% de las operaciones cae fuera del horario de mercado (11 a 17 h ART), el 21% de madrugada y el 10% en sábado. No hay operaciones los domingos ni en los feriados (1/1, 16 y 17/2).

**Pregunta clave antes de concluir: ¿la actividad nocturna y de sábado es comportamiento de clientes o una característica del dato?** La evidencia apunta a lo segundo:
- La proporción es la misma en todos los canales (≈70% fuera de horario y ≈10% en sábado en API, App, Web e IOLnet).
- Las operaciones de sábado se reparten entre 8.693 clientes, y los 10 que más operan ese día explican solo el 2%.
- Cada día hábil "genera" timestamps desde ~10:30 UTC hasta ~20:00 UTC del día siguiente. El lunes, y el día posterior a un feriado, arrancan siempre a las 10:30 UTC. El sábado termina siempre antes de las 20:00 UTC. Es decir, el "sábado" es la continuación del viernes.
- **Conclusión:** el campo `fecha` probablemente no es la hora de ejecución en mercado. Puede ser la hora de carga de la orden, de liquidación o un corrimiento de huso. Hay que validarlo con el dueño del dato antes de usar el horario absoluto como alerta. Por eso el patrón P2 mide desvíos *relativos* por cliente.

## Task 02 — Patrones anómalos

Detalle completo en [`outputs/03_patrones_anomalos.txt`](outputs/03_patrones_anomalos.txt) y query en [`sql/03_patrones_anomalos.sql`](sql/03_patrones_anomalos.sql).

**Criterio general.** Un comportamiento es "anómalo" cuando se aparta mucho de la línea base de la población **y** tiene una lectura de riesgo PLAFT: transferencia de valor, manipulación, toma de cuenta o cuenta mula. Los umbrales se calculan sobre los datos (percentil 99,9 o múltiplos de la mediana) porque son explicables al negocio y robustos a la asimetría. Todos los montos se comparan en pesos, con el dólar MEP de la Task 03.

| # | Patrón | Criterio | Resultado |
|---|---|---|---|
| **P1** | Actividad inusualmente alta | Top 0,1% de clientes por cantidad de operaciones (≥ 31) **o** por monto total (≥ ARS 32 M) | **113 clientes** (0,2%) concentran el **35% del volumen**. El canal API, que es el 1,7% de las operaciones totales, representa el 30% de la actividad de estos clientes; IOLnet pasa del 0,3% al 5,6%. Instrumentos: Letras y Boncaps (T13F6, S17A6, S29Y6), AL30/AL30D y opciones GGAL. |
| **P2** | Horarios y días atípicos | 1) ¿Es estructural? 2) z-score binomial de cada cliente (≥ 10 ops) contra la línea base (21% madrugada, 10% día inhábil); se marca z ≥ 3 | **Es estructural** (ver Task 01). Solo 9 de 649 clientes superan z ≥ 3, cuando por azar se esperarían 2. Es una señal débil y de bajo monto. |
| **P3** | Cambio brusco de comportamiento | Enero vs. febrero-marzo, normalizado por días hábiles. **A:** ≤ 2 ops en enero y tasa ≥ 5x. **B:** monto ≥ ARS 5 M y ≥ 10x enero. **C:** sin actividad en enero y monto ≥ ARS 5 M | **68 clientes con cambio brusco.** Caso emblemático: `CLIBDBEB632`, 0 operaciones en enero y 282 entre el 26/02 y el 11/03, todas por API, compra-venta del mismo día en 5 acciones de baja liquidez. Además hay **270 clientes sin historial en enero** que mueven ARS 3.423 M; pueden ser altas nuevas o clientes dormidos. |
| **P4** | Precio fuera de mercado | Precio < 50% o > 200% de la mediana del mismo instrumento ese día (≥ 5 operaciones de referencia; se excluyen opciones) | **13 operaciones de 9 clientes** con una diferencia de valor de **ARS 741 M** respecto del precio de mercado. 5 de las 7 operaciones de IOLnet tienen precio 1,00 o 0,01. Ejemplo: `CLIEFAFE73D` compró 38.077 TGNO4 a $1,00 (mercado $4.582) y 40.351 METR a $1,00 (mercado $2.441) con 14 segundos de diferencia. |

**Score de riesgo por cliente** (tabla `clientes_riesgo`). Pesos: P4 = 3 · P3 cambio brusco = 2 · P1 = 2 · P3 sin historial = 1 · P2 = 1. Nivel Alto ≥ 4, Medio 2–3, Bajo 1.
Resultado: **5 clientes en riesgo Alto** (18% del volumen), 180 Medio y 268 Bajo. La cola completa está en [`outputs/clientes_riesgo.csv`](outputs/clientes_riesgo.csv).

## Task 03 — Integración con API externa

Script: [`scripts/fetch_api.py`](scripts/fetch_api.py). Uso del dato: [`sql/02_api_enriquecimiento.sql`](sql/02_api_enriquecimiento.sql).

| Dato | API | Para qué se usa |
|---|---|---|
| Feriados 2026 | `nolaborables.com.ar/api/v2/feriados/2026` → fallback `api.argentinadatos.com/v1/feriados/2026` → fallback snapshot versionado | Calendario de días hábiles bursátiles. Cada operación se marca como hábil, fin de semana o feriado. |
| Dólar MEP diario | `api.argentinadatos.com/v1/cotizaciones/dolares/bolsa` → fallback MEP implícito del dataset | Convertir las operaciones en USD a pesos para comparar todo el volumen en una sola moneda. Se usa el **MEP**, no el oficial, porque es el tipo de cambio de referencia de la operatoria bursátil. |

**Manejo de fallas (documentado, como pide la consigna):**
- **`nolaborables.com.ar` no resolvía DNS** durante el desarrollo (el dominio parece discontinuado). El script lo intenta primero, como pide la consigna. Si falla, usa ArgentinaDatos, que publica el mismo calendario oficial. Si también falla, usa un snapshot JSON versionado en el repo.
- **Dólar MEP:** si la API no responde, el SQL calcula un **MEP implícito con el propio dataset** (mediana diaria de AL30 en ARS / AL30D en USD). Se validó contra la API en tres fechas, con un desvío menor al 1%:

  | Fecha | MEP API | MEP implícito | Desvío |
  |---|---|---|---|
  | 02/01/2026 | 1.507,80 | 1.496,74 | -0,73% |
  | 13/02/2026 | 1.426,00 | 1.415,96 | -0,70% |
  | 13/03/2026 | 1.427,20 | 1.418,18 | -0,63% |

- Cada intento queda registrado en `data/api/api_log.csv` (tabla `api_log` y página "Datos externos" del dashboard). Así se sabe qué fuente se usó en cada corrida.

**Qué aportó al análisis.** El calendario de la API confirma que el dataset **no tiene operaciones en feriados**, pero sí en sábados. Esto refuerza la hipótesis de que el horario es un artefacto del dato y no comportamiento. Con el dólar MEP, el volumen total se homogeneiza en **≈ ARS 35.100 M**. Sin esa conversión, el 15% de las operaciones (las de USD) quedaría afuera de los rankings por monto.

## Task 04 — Propuesta de IA

Ver [`docs/propuesta_ia.md`](docs/propuesta_ia.md). Caso de uso: **la IA redacta la ficha de alerta de cada cliente de la cola de revisión.** Arma un resumen, presenta una hipótesis de riesgo junto a una benigna, sugiere verificaciones y una prioridad, siempre a partir de las métricas que ya calculó el SQL. El documento incluye el prompt con datos reales (`CLIBDBEB632`) y la salida obtenida. Las reglas detectan, la IA redacta y el analista decide.

## Dashboard (Power BI)

| Resumen | Exploración |
|---|---|
| ![Resumen](powerbi/capturas/01_resumen.png) | ![Exploración](powerbi/capturas/02_exploracion.png) |
| **Patrones** | **Cola de revisión** |
| ![Patrones](powerbi/capturas/03_patrones.png) | ![Cola](powerbi/capturas/04_cola_revision.png) |
| **Detalle de cliente** | **Datos externos (API)** |
| ![Detalle](powerbi/capturas/05_detalle_cliente.png) | ![API](powerbi/capturas/06_api.png) |

## Limitaciones y próximos pasos

- El horario del dato no es confiable como hora de ejecución (ver Task 01). Hay que validarlo con el área de datos antes de construir alertas horarias.
- Falta la fecha de alta de la cuenta, el perfil declarado del inversor y los movimientos de fondos. Con esos datos, P3 podría distinguir una cuenta nueva de una dormida, y P1 podría compararse contra el perfil declarado y no solo contra la población.
- Marzo llega hasta el 13/03, por eso las comparaciones mensuales se normalizan por día hábil.
- Los pesos del score son criterio experto. Se pueden recalibrar con las decisiones de los analistas (casos confirmados o descartados).
- El uso de IA está documentado en `docs/propuesta_ia.md`. Durante el challenge también se usó IA como asistente para escribir código; el criterio de análisis y los umbrales son propios.

---

## Resumen ejecutivo

*Para el equipo de Prevención de Fraude · Operaciones de enero al 13 de marzo de 2026 · 100.000 operaciones · 57.655 clientes*

**Contexto.** La actividad está muy concentrada: 7 de cada 10 clientes operaron una sola vez, mientras que 113 clientes (0,2%) mueven un tercio del volumen. Las operaciones de madrugada y de sábado aparecen en todos los canales y clientes por igual. Por eso no sirven, por sí solas, para detectar riesgo. Recomendamos confirmar con el área de datos qué representa la hora registrada.

**Los 3 patrones más relevantes**

**1. Operaciones a precio muy alejado del mercado** (riesgo más alto)
- *Qué vimos:* 13 operaciones de 9 clientes se hicieron a menos de la mitad del precio de mercado de ese día; en varios casos, a una fracción mínima. Si se valuaran a precio de mercado, la diferencia sería de unos $741 millones. Ejemplo: un cliente compró acciones de TGN y Metrogas a $1 cuando cotizaban a $4.582 y $2.441.
- *Por qué es riesgo:* operar lejos del precio de mercado es la forma clásica de transferir valor entre cuentas, con operaciones pactadas que pueden encubrir lavado. También puede ser un error de carga, sobre todo en el canal IOLnet, donde se concentran estos casos.
- *Acción:* revisar las 13 operaciones esta semana e identificar la contraparte de cada una. Implementar un control automático que bloquee o pida confirmación cuando el precio se aleje más del 50% del de mercado.

**2. Clientes que cambian bruscamente su forma de operar**
- *Qué vimos:* 68 clientes multiplicaron por 5 o más su actividad, o por 10 su monto, entre enero y febrero-marzo. El caso más claro no había operado en enero y desde el 26/02 hizo 282 operaciones en 12 días, todas por conexión automática (API), comprando y vendiendo en el día 5 acciones de baja liquidez. Además, 270 clientes sin actividad en enero aparecieron operando más de $5 millones cada uno.
- *Por qué es riesgo:* un cambio repentino es la señal típica de cuenta tomada por terceros, cuenta "mula" o prueba de un mecanismo de manipulación de precios en especies poco líquidas.
- *Acción:* contrastar a estos clientes con su perfil declarado y su origen de fondos. Para quienes operan por API, verificar la fecha de habilitación y si hay cuentas vinculadas del otro lado de las operaciones.

**3. Concentración extrema de volumen en pocos clientes**
- *Qué vimos:* un solo cliente del canal IOLnet explica el 18% de todo el volumen del trimestre (unos $6.300 millones en Letras del Tesoro), y también tiene operaciones a precio fuera de mercado. Los 113 clientes más activos concentran el 35% del volumen.
- *Por qué es riesgo:* la exposición está concentrada. Si alguno de estos clientes no tiene un perfil que justifique esos montos, el impacto regulatorio y reputacional es alto.
- *Acción:* revisar con prioridad los 5 clientes de riesgo **Alto** de la cola. Para los 113, confirmar que la documentación de respaldo patrimonial esté al día y monitorearlos de forma continua.

**Próximo paso.** La cola de revisión priorizada (5 de riesgo alto, 180 medio y 268 bajo) está disponible en el tablero, con los motivos de cada alerta. Proponemos generar automáticamente una ficha resumen por cliente para reducir el tiempo de revisión de cada caso.
