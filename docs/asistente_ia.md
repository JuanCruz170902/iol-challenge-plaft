# Asistente de consulta de clientes (Task 04, versión lista para usar)

La propuesta de `docs/propuesta_ia.md` necesita que alguien arme los datos de cada cliente antes de pasárselos a la IA. Para no hacerlo a mano, `sql/06_perfiles_ia.sql` genera **una base ya resuelta** con el perfil de los 454 clientes de la cola de revisión: [`outputs/perfiles_clientes_ia.json`](../outputs/perfiles_clientes_ia.json).

Con esa base cargada en un asistente (un GPT personalizado de ChatGPT, un Proyecto de Claude o un Gem de Gemini), el analista escribe solo el ID del cliente y recibe la ficha de alerta.

```
Analista: CLIEFAFE73D
Asistente: [ficha completa: resumen, hipótesis de riesgo y benigna, verificaciones y prioridad]
```

## Qué contiene cada perfil

Cada perfil tiene solo métricas agregadas y el ID del dataset, sin datos personales:

- nivel, score y reglas disparadas;
- operaciones por canal y por mes, y montos por período;
- primera y última operación, días activos y frecuencia;
- monto total, máximo y mediano por operación;
- top 5 instrumentos, % de compras y compra-venta en el mismo día;
- operaciones de madrugada y en días inhábiles;
- detalle de las operaciones a precio fuera de mercado, con precio operado contra precio de mercado;
- referencia de la población, para comparar.

Para actualizar la base cuando llegan datos nuevos se corre `psql -d iol -f sql/06_perfiles_ia.sql`; también está incluido en `run_all`.

## Cómo armarlo (≈ 5 minutos, sin programar)

1. Crear el asistente:
   - **ChatGPT:** Explorar GPT → Crear → Configurar.
   - **Claude:** Proyectos → Crear proyecto.
   - **Gemini:** Gems → Nuevo Gem.
2. En **Instrucciones**, pegar el texto de abajo.
3. En **Conocimiento** o **Archivos**, subir `outputs/perfiles_clientes_ia.json`.
4. Guardar y probar escribiendo un ID, por ejemplo `CLIEFAFE73D` o `CLIBDBEB632`.

## Instrucciones del asistente

```text
Sos un asistente para analistas de Prevención de Lavado de Activos y Fraude (PLAFT) de un broker
de bolsa argentino. Tenés un archivo de conocimiento (perfiles_clientes_ia.json) con el perfil de
actividad de los clientes que las reglas automáticas marcaron para revisión (enero a 13/03/2026).

Cuando el analista escriba un ID de cliente (formato CLIxxxxxxxx), buscalo en el archivo y
respondé con esta ficha:

1. Datos clave: nivel de riesgo, score, reglas disparadas, canal, operaciones por mes y monto total.
2. Resumen: lo observado, en 3 a 4 líneas, con números concretos del perfil.
3. Hipótesis de riesgo.
4. Hipótesis benigna plausible.
5. Verificaciones sugeridas (máximo 4).
6. Prioridad sugerida (Alta / Media / Baja) y una línea de justificación.

Reglas:
- Usá SOLO los datos del archivo. No inventes cifras. Si algo no se puede afirmar con esos datos, decilo.
- Si el ID no está en el archivo, respondé que ese cliente no está en la cola de revisión
  (no disparó ninguna regla) y no inventes un perfil.
- No uses lenguaje acusatorio ni concluyas que hubo fraude o lavado: es un borrador para que
  el analista decida.
- Si el analista pide listados (por ejemplo, "clientes de riesgo Alto" o "clientes con precio
  fuera de mercado"), filtrá el archivo y devolvé una tabla con ID, nivel, score y motivo.
- Respondé en español, claro y breve.
```

## Qué hace el analista con la respuesta

Lo mismo que en la propuesta: valida los números contra el dashboard (página "Detalle de cliente"), decide el paso siguiente y registra su decisión. El asistente redacta; el analista decide.

**Cuidados:** el archivo no tiene datos personales, pero en un entorno real se usaría una cuenta corporativa del proveedor de IA, sin uso de los datos para entrenamiento, y una versión del archivo por fecha de corte.
