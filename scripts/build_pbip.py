"""
build_pbip.py — Genera el proyecto Power BI (PBIP: modelo TMDL + reporte PBIR) del challenge.

Parte del esqueleto vacío que creó Power BI Desktop (powerbi/IOL_PLAFT.*) y le agrega:
  * Modelo semántico: 9 tablas que leen powerbi/data/*.csv, relaciones y medidas DAX.
  * Reporte: 6 páginas con visuales enlazados al modelo.
El parámetro "CarpetaDatos" del modelo apunta a la carpeta powerbi/data; si el repo se clona en
otra ruta, se cambia desde Power BI (Transformar datos → Editar parámetros).

Uso:  python scripts/build_pbip.py [ruta_carpeta_datos_en_windows]
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBI = os.path.join(ROOT, "powerbi")
SM = os.path.join(PBI, "IOL_PLAFT.SemanticModel", "definition")
RP = os.path.join(PBI, "IOL_PLAFT.Report", "definition")
DATA_DIR_WIN = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\usuario\Downloads\iol-challenge-plaft\powerbi\data" + "\\"

VC_SCHEMA = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.9.0/schema.json"
PAGE_SCHEMA = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json"
PAGES_SCHEMA = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/pagesMetadata/1.1.0/schema.json"
W, H = 1280, 720

# Colores (acento único para riesgo, neutros para contexto)
C_TEXT, C_MUTED, C_ACCENT = "#1F2430", "#6B7280", "#B42318"
IOL_VIOLETA, IOL_MENTA, IOL_VIOLETA_CLARO = "#6439FF", "#03F2AB", "#EFEAFF"
THEME_NAME = "IOL-PLAFT-3f9c2a71.json"
LOGO_NAME = "iol_logo1791308900.png"  # provisto por el usuario, en StaticResources/RegisteredResources
THEME = {
    "name": THEME_NAME,
    "dataColors": ["#6439FF", "#00B386", "#1F2430", "#A48BFF", "#F59E0B", "#B42318", "#64748B", "#C8B8FE"],
    "foreground": "#1F2430",
    "background": "#FFFFFF",
    "tableAccent": "#6439FF",
    "good": "#00B386",
    "bad": "#B42318",
    "neutral": "#F59E0B",
}


def hid(seed: str, n: int = 20) -> str:
    """IDs deterministas (20 hex) para que el diff en git sea estable entre corridas."""
    return hashlib.sha1(seed.encode()).hexdigest()[:n]


# =============================================================================
# MODELO SEMÁNTICO (TMDL)
# =============================================================================
# (nombre_columna, tipo_tmdl, tipo_M, opciones)
T = {
    "Operaciones": ("operaciones.csv", [
        ("id_transaccion", "string", "text", {"hidden": True}),
        ("id_cliente", "string", "text", {}),
        ("fecha", "dateTime", "date", {"fmt": "dd/MM/yyyy"}),
        ("fecha_art", "dateTime", "datetime", {"fmt": "dd/MM/yyyy HH:mm:ss"}),
        ("hora_art", "int64", "Int64.Type", {"fmt": "0"}),
        ("franja_horaria", "string", "text", {}),
        ("tipo_dia", "string", "text", {}),
        ("tipo_tran", "string", "text", {}),
        ("canal", "string", "text", {}),
        ("moneda", "string", "text", {}),
        ("simbolo_titulo", "string", "text", {}),
        ("familia_instrumento", "string", "text", {}),
        ("cantidad", "int64", "Int64.Type", {"fmt": "#,##0"}),
        ("precio", "double", "number", {"fmt": "#,##0.0000"}),
        ("monto_ars", "double", "number", {"fmt": "#,##0", "sum": True}),
        ("flag_precio_fuera_mercado", "boolean", "logical", {}),
        ("flag_operacion_extrema", "boolean", "logical", {}),
    ]),
    "Clientes": ("clientes.csv", [
        ("id_cliente", "string", "text", {}),
        ("canal_principal", "string", "text", {}),
        ("ops", "int64", "Int64.Type", {"fmt": "#,##0"}),
        ("dias_activos", "int64", "Int64.Type", {"fmt": "#,##0"}),
        ("simbolos", "int64", "Int64.Type", {"fmt": "#,##0"}),
        ("monto_ars", "double", "number", {"fmt": "#,##0"}),
        ("ops_ene", "int64", "Int64.Type", {"fmt": "0"}),
        ("ops_feb", "int64", "Int64.Type", {"fmt": "0"}),
        ("ops_mar", "int64", "Int64.Type", {"fmt": "0"}),
        ("score_riesgo", "int64", "Int64.Type", {"fmt": "0"}),
        ("nivel_riesgo", "string", "text", {"sortBy": "orden_nivel"}),
        ("orden_nivel", "int64", "Int64.Type", {"hidden": True, "fmt": "0"}),
        ("motivos", "string", "text", {}),
        ("p1_actividad_alta", "boolean", "logical", {}),
        ("p2_horario_atipico", "boolean", "logical", {}),
        ("p3_cambio_brusco", "boolean", "logical", {}),
        ("p3_sin_historial_monto_alto", "boolean", "logical", {}),
        ("p4_precio_fuera_mercado", "boolean", "logical", {}),
        ("diferencia_valor_ars", "double", "number", {"fmt": "#,##0"}),
        ("log10_ops", "double", "number", {"fmt": "0.00", "sum": True}),
        ("log10_monto_ars", "double", "number", {"fmt": "0.00", "sum": True}),
    ]),
    "Calendario": ("calendario.csv", [
        ("fecha", "dateTime", "date", {"fmt": "dd/MM/yyyy"}),
        ("dow", "int64", "Int64.Type", {"hidden": True, "fmt": "0"}),
        ("dia_semana", "string", "text", {"sortBy": "dow"}),
        ("anio_mes", "string", "text", {}),
        ("es_habil", "boolean", "logical", {}),
        ("feriado", "string", "text", {}),
        ("tc_ars_por_usd", "double", "number", {"fmt": "#,##0.00", "sum": True}),
        ("fuente_tc", "string", "text", {}),
    ]),
    "ApiLog": ("api_log.csv", [
        ("api", "string", "text", {}),
        ("estado", "string", "text", {}),
        ("filas", "int64", "Int64.Type", {"fmt": "0"}),
        ("detalle", "string", "text", {}),
        ("url", "string", "text", {}),
    ]),
    "TopInstrumentos": ("top_instrumentos.csv", [
        ("ranking", "int64", "Int64.Type", {"fmt": "0"}),
        ("instrumento", "string", "text", {"sortBy": "ranking"}),
        ("ops", "int64", "Int64.Type", {"fmt": "#,##0", "sum": True}),
        ("clientes", "int64", "Int64.Type", {"fmt": "#,##0", "sum": True}),
        ("monto_ars_mill", "double", "number", {"fmt": "#,##0.0", "sum": True}),
    ]),
    "TramosClientes": ("tramos_clientes.csv", [
        ("orden", "int64", "Int64.Type", {"hidden": True, "fmt": "0"}),
        ("tramo", "string", "text", {"sortBy": "orden"}),
        ("clientes", "int64", "Int64.Type", {"fmt": "#,##0", "sum": True}),
        ("ops", "int64", "Int64.Type", {"fmt": "#,##0", "sum": True}),
    ]),
    "Pareto": ("pareto.csv", [
        ("pct_clientes", "double", "number", {"fmt": "0.0"}),
        ("pct_monto", "double", "number", {"fmt": "0.0", "sum": True}),
    ]),
    "P3Top": ("p3_top.csv", [
        ("id_cliente", "string", "text", {}),
        ("mes_orden", "int64", "Int64.Type", {"hidden": True, "fmt": "0"}),
        ("mes", "string", "text", {"sortBy": "mes_orden"}),
        ("ops", "int64", "Int64.Type", {"fmt": "#,##0", "sum": True}),
    ]),
    "P4PrecioFueraMercado": ("p4_precio_fuera_mercado.csv", [
        ("id_cliente", "string", "text", {}),
        ("fecha", "dateTime", "date", {"fmt": "dd/MM/yyyy"}),
        ("canal", "string", "text", {}),
        ("tipo_tran", "string", "text", {}),
        ("simbolo_titulo", "string", "text", {}),
        ("cantidad", "int64", "Int64.Type", {"fmt": "#,##0"}),
        ("precio", "double", "number", {"fmt": "#,##0.00"}),
        ("precio_mediana_dia", "double", "number", {"fmt": "#,##0.00"}),
        ("ratio_vs_mercado", "double", "number", {"fmt": "0.0000"}),
        ("diferencia_ars_mill", "double", "number", {"fmt": "#,##0.00"}),
    ]),
}

MEASURES = [
    ("Operaciones totales", "FORMAT ( [Cant. operaciones], \"#,##0\" )", "", "KPI en texto (evita la abreviatura automática 'mil')"),
    ("Clientes activos", "FORMAT ( [Clientes únicos], \"#,##0\" )", "", "KPI en texto"),
    ("Monto ARS M", "FORMAT ( [Monto ARS (M)], \"#,##0\" )", "", "KPI en texto, millones de pesos"),
    ("Fuera de horario (%)", "FORMAT ( [% Fuera de horario], \"0.0%\" )", "", "KPI en texto"),
    ("Clientes con alerta", "FORMAT ( [Clientes en alerta], \"#,##0\" )", "", "KPI en texto"),
    ("Riesgo alto", "FORMAT ( [Clientes riesgo Alto], \"#,##0\" )", "", "KPI en texto"),
    ("Monto en alerta (ARS M)", "FORMAT ( CALCULATE ( [Monto clientes (M)], Clientes[nivel_riesgo] <> \"Sin alerta\" ), \"#,##0\" )", "", "Monto de los clientes con alguna alerta, en millones de pesos"),
    ("Cant. operaciones", "COUNTROWS ( Operaciones )", "#,##0", "Cantidad de operaciones"),
    ("Clientes únicos", "DISTINCTCOUNT ( Operaciones[id_cliente] )", "#,##0", "Clientes únicos que operaron"),
    ("Monto ARS (M)", "DIVIDE ( SUM ( Operaciones[monto_ars] ), 1000000 )", "#,##0", "Monto operado en millones de pesos (USD convertidos a dólar MEP)"),
    ("% Fuera de horario", "DIVIDE ( CALCULATE ( [Cant. operaciones], Operaciones[franja_horaria] <> \"Mercado (11-17)\" ), [Cant. operaciones] )", "0.0%", "Operaciones fuera de 11 a 17 hs (hora Argentina)"),
    ("% Día inhábil", "DIVIDE ( CALCULATE ( [Cant. operaciones], Operaciones[tipo_dia] <> \"Día hábil\" ), [Cant. operaciones] )", "0.0%", "Operaciones en fin de semana o feriado"),
    ("Clientes en alerta", "CALCULATE ( COUNTROWS ( Clientes ), Clientes[nivel_riesgo] <> \"Sin alerta\" )", "#,##0", "Clientes con al menos una alerta"),
    ("Clientes riesgo Alto", "CALCULATE ( COUNTROWS ( Clientes ), Clientes[nivel_riesgo] = \"Alto\" )", "#,##0", "Clientes con score >= 4"),
    ("Monto clientes (M)", "DIVIDE ( SUM ( Clientes[monto_ars] ), 1000000 )", "#,##0", "Monto total de los clientes del contexto, en millones de pesos"),
    ("Ops precio fuera de mercado", "CALCULATE ( [Cant. operaciones], Operaciones[flag_precio_fuera_mercado] = TRUE () )", "#,##0", "Operaciones a menos de la mitad o más del doble del precio del día"),
]


def m_partition(table: str, file: str, cols) -> str:
    bools = [c for c, t, m, o in cols if m == "logical"]
    types = ", ".join(f'{{"{c}", {("type " + m) if m in ("text", "number", "date", "datetime") else m}}}'
                      for c, t, m, o in cols if m != "logical")
    lines = [
        "let",
        f'\tOrigen = Csv.Document(File.Contents(CarpetaDatos & "{file}"), [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),',
        "\tEncabezados = Table.PromoteHeaders(Origen, [PromoteAllScalars = true]),",
        f'\tTipos = Table.TransformColumnTypes(Encabezados, {{{types}}}, "en-US")',
    ]
    last = "Tipos"
    if bools:
        bl = ", ".join(f'{{"{c}", each _ = "t", type logical}}' for c in bools)
        lines[-1] += ","
        lines.append(f"\tBooleanos = Table.TransformColumns(Tipos, {{{bl}}})")
        last = "Booleanos"
    lines += ["in", f"\t{last}"]
    return "\n".join("\t\t\t\t" + l for l in lines)


def table_tmdl(name: str, file: str, cols) -> str:
    out = [f"table {name}", ""]
    for c, t, m, o in cols:
        out.append(f"\tcolumn {c}")
        out.append(f"\t\tdataType: {t}")
        if o.get("hidden"):
            out.append("\t\tisHidden")
        if "fmt" in o:
            out.append(f"\t\tformatString: {o['fmt']}")
        out.append(f"\t\tsummarizeBy: {'sum' if o.get('sum') else 'none'}")
        out.append(f"\t\tsourceColumn: {c}")
        if "sortBy" in o:
            out.append(f"\t\tsortByColumn: {o['sortBy']}")
        out.append("")
    out.append(f"\tpartition {name} = m")
    out.append("\t\tmode: import")
    out.append("\t\tsource =")
    out.append(m_partition(name, file, cols))
    out.append("")
    return "\n".join(out) + "\n"


def measures_tmdl() -> str:
    out = ["table Medidas", ""]
    for n, dax, fmt, desc in MEASURES:
        out.append(f"\t/// {desc}")
        out.append(f"\tmeasure '{n}' = {dax}")
        if fmt:
            out.append(f"\t\tformatString: {fmt}")
        out.append("")
    out += ["\tcolumn Dummy", "\t\tdataType: string", "\t\tisHidden", "\t\tsummarizeBy: none",
            "\t\tsourceColumn: [Dummy]", "", "\tpartition Medidas = calculated", "\t\tmode: import",
            '\t\tsource = ROW("Dummy", BLANK())', ""]
    return "\n".join(out) + "\n"


def build_model():
    os.makedirs(os.path.join(SM, "tables"), exist_ok=True)
    for f in os.listdir(os.path.join(SM, "tables")):
        os.remove(os.path.join(SM, "tables", f))
    for name, (file, cols) in T.items():
        with open(os.path.join(SM, "tables", f"{name}.tmdl"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(table_tmdl(name, file, cols))
    with open(os.path.join(SM, "tables", "Medidas.tmdl"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write(measures_tmdl())

    with open(os.path.join(SM, "expressions.tmdl"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("/// Carpeta con los CSV exportados por sql/05_export_powerbi.sql (terminar con \\)\n")
        fh.write(f'expression CarpetaDatos = "{DATA_DIR_WIN}" meta [IsParameterQuery = true, Type = "Text", IsParameterQueryRequired = true]\n')

    with open(os.path.join(SM, "relationships.tmdl"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("relationship Operaciones_Clientes\n\tfromColumn: Operaciones.id_cliente\n\ttoColumn: Clientes.id_cliente\n\n")
        fh.write("relationship Operaciones_Calendario\n\tfromColumn: Operaciones.fecha\n\ttoColumn: Calendario.fecha\n")

    tables = list(T) + ["Medidas"]
    model = [
        "model Model",
        "\tculture: es-ES",
        "\tdefaultPowerBIDataSourceVersion: powerBI_V3",
        "\tsourceQueryCulture: es-AR",
        "\tvalueFilterBehavior: independent",
        "\tdataAccessOptions",
        "\t\tlegacyRedirects",
        "\t\treturnErrorValuesAsNull",
        "",
        "annotation __PBI_TimeIntelligenceEnabled = 0",
        "",
        'annotation PBI_ProTooling = ["DevMode"]',
        "",
    ] + [f"ref table {t}" for t in tables] + ["", "ref cultureInfo es-ES", ""]
    with open(os.path.join(SM, "model.tmdl"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(model) + "\n")


# =============================================================================
# REPORTE (PBIR)
# =============================================================================
def lit(v):
    return {"expr": {"Literal": {"Value": v}}}


def col(t, c):
    return {"Column": {"Expression": {"SourceRef": {"Entity": t}}, "Property": c}}


def meas(m):
    return {"Measure": {"Expression": {"SourceRef": {"Entity": "Medidas"}}, "Property": m}}


def agg(t, c, fn=0):
    return {"Aggregation": {"Expression": col(t, c), "Function": fn}}


def proj(field):
    if "Column" in field:
        t, c = field["Column"]["Expression"]["SourceRef"]["Entity"], field["Column"]["Property"]
        return {"field": field, "queryRef": f"{t}.{c}", "nativeQueryRef": c}
    if "Measure" in field:
        m = field["Measure"]["Property"]
        return {"field": field, "queryRef": f"Medidas.{m}", "nativeQueryRef": m}
    a = field["Aggregation"]
    t, c = a["Expression"]["Column"]["Expression"]["SourceRef"]["Entity"], a["Expression"]["Column"]["Property"]
    fname = {0: "Sum", 1: "Avg", 3: "Min", 4: "Max"}[a["Function"]]
    label = {0: "Sum of", 1: "Average of", 3: "Min of", 4: "Max of"}[a["Function"]]
    return {"field": field, "queryRef": f"{fname}({t}.{c})", "nativeQueryRef": f"{label} {c}"}


def title_vco(text):
    return {
        "title": [{"properties": {"show": lit("true"), "text": lit(f"'{text}'"),
                                  "fontSize": lit("12D"), "bold": lit("true")}}],
        "subTitle": [{"properties": {"show": lit("false")}}],
        "padding": [{"properties": {k: lit("8D") for k in ("top", "bottom", "left", "right")}}],
    }


def visual(page, key, vtype, x, y, w, h, roles=None, objects=None, title=None, sort=None, filters=None, z=0):
    v = {"visualType": vtype}
    if roles:
        v["query"] = {"queryState": {r: {"projections": [proj(f) for f in fs]} for r, fs in roles.items()}}
        if sort:
            v["query"]["sortDefinition"] = {"sort": [{"field": f, "direction": d} for f, d in sort], "isDefaultSort": False}
    if objects:
        v["objects"] = objects
    if title:
        v["visualContainerObjects"] = title_vco(title)
    name = hid(page + key)
    d = {"$schema": VC_SCHEMA, "name": name,
         "position": {"x": x, "y": y, "z": 1000 + z * 1000, "height": h, "width": w, "tabOrder": 1000 + z * 1000},
         "visual": v}
    if filters:
        d["filterConfig"] = {"filters": filters}
    return name, d


def textbox(page, key, x, y, w, h, paras, z=0):
    ps = []
    for text, size, color, bold in paras:
        ps.append({"textRuns": [{"value": text, "textStyle": {
            "fontFamily": "Segoe UI Semibold" if bold else "Segoe UI", "fontSize": f"{size}px", "color": color}}],
            "horizontalTextAlignment": "left"})
    name, d = visual(page, key, "textbox", x, y, w, h, z=z)
    d["visual"]["objects"] = {"general": [{"properties": {"paragraphs": ps}}]}
    d["visual"]["visualContainerObjects"] = {
        "background": [{"properties": {"show": lit("false")}}],
        "border": [{"properties": {"show": lit("false")}}],
        "padding": [{"properties": {k: lit("0D") for k in ("top", "bottom", "left", "right")}}]}
    return name, d


def table_objects():
    return {"columnHeaders": [{"properties": {"columnAdjustment": lit("'growToFit'"), "autoSizeColumnWidth": lit("true")}}]}


def in_filter(key, table, column, values, negate=False):
    cond = {"In": {"Expressions": [{"Column": {"Expression": {"SourceRef": {"Source": "t"}}, "Property": column}}],
                   "Values": [[{"Literal": {"Value": v}}] for v in values]}}
    if negate:
        cond = {"Not": {"Expression": cond}}
    return {"name": "Filter" + hid(key, 24), "field": col(table, column), "type": "Categorical",
            "filter": {"Version": 2, "From": [{"Name": "t", "Entity": table, "Type": 0}], "Where": [{"Condition": cond}]},
            "howCreated": "User"}


def nav_button(page, key, x, y, w, h, label, target, fill=IOL_VIOLETA, font="#FFFFFF", size=13, z=0):
    sel = {"id": "default"}
    name, d = visual(page, key, "actionButton", x, y, w, h, z=z)
    # Patrón de botón: "show" en una entrada sin selector + propiedades por estado con selector id=default
    d["visual"]["objects"] = {
        "icon": [{"properties": {"show": lit("false")}}],
        "text": [{"properties": {"show": lit("true")}},
                 {"properties": {"text": lit(f"'{label}'"), "fontColor": {"solid": {"color": lit(f"'{font}'")}},
                                 "fontSize": lit(f"{size}D"), "bold": lit("true"), "horizontalAlignment": lit("'center'")},
                  "selector": sel}],
        "fill": [{"properties": {"show": lit("true")}},
                 {"properties": {"fillColor": {"solid": {"color": lit(f"'{fill}'")}}, "transparency": lit("0D")},
                  "selector": sel}],
        "outline": [{"properties": {"show": lit("false")}}],
    }
    d["visual"]["visualContainerObjects"] = {
        "visualLink": [{"properties": {"show": lit("true"), "type": lit("'PageNavigation'"), "navigationSection": lit(f"'{target}'")}}]}
    return name, d


def block(page, key, x, y, w, h, color, paras=None, z=0):
    """Bloque de color (textbox con fondo) para la portada y acentos."""
    name, d = textbox(page, key, x, y, w, h, paras or [(" ", 8, color, False)], z=z)
    d["visual"]["visualContainerObjects"]["background"] = [{"properties": {
        "show": lit("true"), "color": {"solid": {"color": lit(f"'{color}'")}}, "transparency": lit("0D")}}]
    d["visual"]["visualContainerObjects"]["padding"] = [{"properties": {k: lit("16D") for k in ("top", "bottom", "left", "right")}}]
    return name, d


PAGE_IDS = {}


def accent_bar(page, key, x, y, w, h, color, z=0):
    """Barra vertical de acento junto al título (bloque de color sin padding)."""
    name, d = block(page, key, x, y, w, h, color, z=z)
    d["visual"]["visualContainerObjects"]["padding"] = [{"properties": {k: lit("0D") for k in ("top", "bottom", "left", "right")}}]
    return name, d


def logo(page, key, x, y, w, h, z=0):
    name, d = visual(page, key, "image", x, y, w, h, z=z)
    d["visual"]["objects"] = {"general": [{"properties": {"imageUrl": {"expr": {"ResourcePackageItem": {
        "PackageName": "RegisteredResources", "PackageType": 1, "ItemName": LOGO_NAME}}}}}]}
    d["visual"]["drillFilterOtherVisuals"] = True
    return name, d


def header(page, title, subtitle):
    return [textbox(page, "title", 30, 12, 1070, 34, [(title, 22, IOL_VIOLETA, True)]),
            textbox(page, "subtitle", 30, 44, 1070, 22, [(subtitle, 12, C_MUTED, False)], z=1),
            accent_bar(page, "accent", 16, 16, 6, 48, IOL_MENTA, z=9),
            nav_button(page, "back", 1120, 16, 140, 36, "← Portada", PAGE_IDS["portada"], fill=IOL_VIOLETA_CLARO,
                       font=IOL_VIOLETA, size=11, z=10)]


PAGES = []


# La primera página reutiliza el ID que creó Desktop en el esqueleto vacío
FIRST_PAGE_ID = "aae62411ec2e9f5efcf6"


ORDER = ["portada", "resumen", "exploracion", "patrones", "cola", "detalle", "api"]
for _k in ORDER:
    PAGE_IDS[_k] = FIRST_PAGE_ID if _k == "portada" else hid("page" + _k)


def page(key, display, visuals, extra=None):
    PAGES.append((PAGE_IDS[key], display, visuals, extra or {}))


def build_report():
    # ---------------- 0. Portada
    p = "portada"
    v = [block(p, "panel", 0, 0, 440, 720, IOL_VIOLETA, [
            (" ", 60, "#FFFFFF", False),
            (" ", 52, "#FFFFFF", False),
            ("PREVENCIÓN DE FRAUDE · PLAFT", 13, IOL_MENTA, True),
            ("Monitor de operaciones inusuales", 34, "#FFFFFF", True),
            (" ", 10, "#FFFFFF", False),
            ("Operaciones bursátiles · 2 de enero al 13 de marzo de 2026", 14, "#FFFFFF", False),
            ("100.000 operaciones · 57.655 clientes · 5 canales", 14, "#FFFFFF", False),
            (" ", 60, "#FFFFFF", False),
            ("Challenge técnico · Analista BI", 12, "#C8B8FE", False),
         ]),
         block(p, "menta", 40, 660, 120, 6, IOL_MENTA, z=1),
         logo(p, "logo", 36, 28, 140, 104, z=40),
         textbox(p, "nav_t", 500, 48, 740, 40, [("¿Qué querés ver?", 24, C_TEXT, True)], z=2),
         textbox(p, "nav_s", 500, 88, 740, 24, [("Elegí una sección. En cada página, el botón «← Portada» te trae de vuelta.", 12, C_MUTED, False)], z=3)]
    secciones = [
        ("resumen", "Resumen", "Indicadores clave y los 3 hallazgos principales."),
        ("exploracion", "Exploración", "Horarios, canales, instrumentos y concentración de la actividad."),
        ("patrones", "Patrones anómalos", "Actividad extrema, cambios bruscos y precios fuera de mercado."),
        ("cola", "Cola de revisión", "Clientes con alerta, priorizados por score de riesgo."),
        ("api", "Datos externos (API)", "Feriados y dólar MEP: fuente usada y log de llamadas."),
    ]
    for i, (k, label, desc) in enumerate(secciones):
        y = 140 + i * 78
        v.append(nav_button(p, "btn_" + k, 500, y, 260, 58, label, PAGE_IDS[k], z=10 + i))
        v.append(textbox(p, "desc_" + k, 784, y + 16, 470, 30, [(desc, 13, C_TEXT, False)], z=20 + i))
    v.append(visual(p, "kpis", "cardVisual", 500, 548, 760, 120, {"Data": [
        meas("Operaciones totales"), meas("Clientes con alerta"), meas("Riesgo alto"), meas("Fuera de horario (%)")]}, z=30))
    page(p, "Portada", v)

    # ---------------- 1. Resumen
    p = "resumen"
    v = header(p, "Prevención de Fraude · Operaciones ene–13 mar 2026",
               "100.000 operaciones · 57.655 clientes · montos en ARS (USD convertidos a dólar MEP)")
    v.append(visual(p, "kpis", "cardVisual", 20, 76, 1240, 110, {"Data": [
        meas("Operaciones totales"), meas("Clientes activos"), meas("Monto ARS M"), meas("Fuera de horario (%)"),
        meas("Clientes con alerta"), meas("Riesgo alto")]}, z=2))
    v.append(visual(p, "diario", "columnChart", 20, 200, 820, 250,
                    {"Category": [col("Calendario", "fecha")], "Series": [col("Operaciones", "tipo_dia")],
                     "Y": [meas("Cant. operaciones")]}, title="Operaciones por día (hábil vs. fin de semana)", z=3))
    v.append(visual(p, "canal", "barChart", 860, 200, 400, 250,
                    {"Category": [col("Operaciones", "canal")], "Y": [meas("Cant. operaciones")]},
                    title="Operaciones por canal", sort=[(meas("Cant. operaciones"), "Descending")], z=4))
    v.append(visual(p, "nivel", "clusteredColumnChart", 20, 464, 600, 240,
                    {"Category": [col("Clientes", "nivel_riesgo")], "Y": [meas("Monto clientes (M)")]},
                    title="Monto total (ARS M) por nivel de riesgo del cliente", z=5))
    v.append(textbox(p, "hallazgos", 640, 464, 620, 240, [
        ("Hallazgos clave", 15, C_ACCENT, True),
        ("1. 13 operaciones a precio fuera de mercado (≈ ARS 741 M de diferencia de valor), concentradas en IOLnet.", 12, C_TEXT, False),
        ("2. 68 clientes con cambio brusco de comportamiento entre enero y feb-mar; 270 sin historial en enero con montos > ARS 5 M.", 12, C_TEXT, False),
        ("3. 113 clientes (0,2%) concentran el 35% del volumen; uno solo explica el 18%.", 12, C_TEXT, False),
        ("La actividad nocturna y de sábado es pareja en todos los canales: es una característica del dato, no del cliente.", 11, C_MUTED, False),
    ], z=6))
    page(p, "Resumen", v)

    # ---------------- 2. Exploración
    p = "exploracion"
    v = header(p, "Exploración del dataset", "¿Cuándo se opera, por dónde, en qué instrumentos y qué tan concentrada está la actividad?")
    v.append(visual(p, "heat", "pivotTable", 20, 76, 520, 630,
                    {"Rows": [col("Operaciones", "hora_art")], "Columns": [col("Calendario", "dia_semana")],
                     "Values": [meas("Cant. operaciones")]}, objects=table_objects(),
                    title="Operaciones por hora (ART) y día de semana", z=2))
    v.append(visual(p, "franja", "hundredPercentStackedBarChart", 560, 76, 700, 260,
                    {"Category": [col("Operaciones", "canal")], "Series": [col("Operaciones", "franja_horaria")],
                     "Y": [meas("Cant. operaciones")]}, title="Franja horaria por canal (mismo patrón en todos → estructural)", z=3))
    v.append(visual(p, "top", "barChart", 560, 350, 340, 356,
                    {"Category": [col("TopInstrumentos", "instrumento")], "Y": [agg("TopInstrumentos", "ops")]},
                    title="Top 15 instrumentos (operaciones)", sort=[(agg("TopInstrumentos", "ops"), "Descending")], z=4))
    v.append(visual(p, "tramos", "columnChart", 920, 350, 340, 170,
                    {"Category": [col("TramosClientes", "tramo")], "Y": [agg("TramosClientes", "clientes")]},
                    title="Clientes según cantidad de operaciones", z=5))
    v.append(visual(p, "pareto", "lineChart", 920, 534, 340, 172,
                    {"Category": [col("Pareto", "pct_clientes")], "Y": [agg("Pareto", "pct_monto")]},
                    title="Concentración: % del monto según % de clientes", z=6))
    page(p, "Exploración", v)

    # ---------------- 3. Patrones
    p = "patrones"
    v = header(p, "Patrones anómalos", "P1 actividad extrema · P2 horarios (estructural) · P3 cambio brusco · P4 precio fuera de mercado")
    v.append(visual(p, "scatter", "scatterChart", 20, 76, 620, 330,
                    {"Category": [col("Clientes", "id_cliente")], "Series": [col("Clientes", "nivel_riesgo")],
                     "X": [agg("Clientes", "log10_ops")], "Y": [agg("Clientes", "log10_monto_ars")]},
                    title="P1 · Clientes: log10(operaciones) vs log10(monto ARS)", z=2))
    v.append(visual(p, "p3", "clusteredColumnChart", 660, 76, 600, 330,
                    {"Category": [col("P3Top", "id_cliente")], "Series": [col("P3Top", "mes")], "Y": [agg("P3Top", "ops")]},
                    title="P3 · Top 12 cambios bruscos: operaciones por mes", z=3))
    v.append(visual(p, "p4", "tableEx", 20, 420, 1240, 220,
                    {"Values": [col("P4PrecioFueraMercado", c) for c in
                                ("id_cliente", "fecha", "canal", "tipo_tran", "simbolo_titulo", "cantidad", "precio",
                                 "precio_mediana_dia", "ratio_vs_mercado", "diferencia_ars_mill")]},
                    objects=table_objects(), title="P4 · Operaciones a precio fuera de mercado (diferencia de valor en ARS M)",
                    sort=[(col("P4PrecioFueraMercado", "diferencia_ars_mill"), "Descending")], z=4))
    v.append(textbox(p, "p2", 20, 652, 1240, 54, [
        ("P2 · Horarios atípicos: 70% de las operaciones cae fuera de 11–17 hs y 10% en sábado, en la misma proporción en todos los canales. "
         "Medido por cliente (z ≥ 3), solo 9 de 649 clientes se apartan de la línea base: señal débil.", 12, C_MUTED, False)], z=5))
    page(p, "Patrones", v)

    # ---------------- 4. Cola de revisión
    p = "cola"
    v = header(p, "Cola de revisión priorizada", "Clientes con al menos una alerta, ordenados por score · clic derecho sobre un cliente → Obtener detalles")
    v.append(visual(p, "s_nivel", "slicer", 20, 76, 300, 80, {"Values": [col("Clientes", "nivel_riesgo")]},
                    objects={"data": [{"properties": {"mode": lit("'Dropdown'")}}],
                             "header": [{"properties": {"show": lit("true"), "text": lit("'Nivel de riesgo'")}}]}, z=2))
    v.append(visual(p, "s_canal", "slicer", 340, 76, 300, 80, {"Values": [col("Clientes", "canal_principal")]},
                    objects={"data": [{"properties": {"mode": lit("'Dropdown'")}}],
                             "header": [{"properties": {"show": lit("true"), "text": lit("'Canal principal'")}}]}, z=3))
    v.append(visual(p, "kpi", "cardVisual", 660, 76, 600, 80, {"Data": [meas("Clientes con alerta"), meas("Riesgo alto"), meas("Monto en alerta (ARS M)")]}, z=4))
    v.append(visual(p, "tabla", "tableEx", 20, 170, 1240, 536,
                    {"Values": [col("Clientes", c) for c in
                                ("id_cliente", "nivel_riesgo", "score_riesgo", "motivos", "canal_principal", "ops", "monto_ars",
                                 "ops_ene", "ops_feb", "ops_mar")]},
                    objects=table_objects(), sort=[(col("Clientes", "score_riesgo"), "Descending")],
                    filters=[in_filter("cola_nivel", "Clientes", "nivel_riesgo", ["'Alto'", "'Medio'", "'Bajo'"])], z=5))
    page(p, "Cola de revisión", v)

    # ---------------- 5. Detalle de cliente (drillthrough)
    p = "detalle"
    fname = "Filter" + hid("drill_cliente", 24)
    v = header(p, "Detalle de cliente", "Página de obtención de detalles: llegar desde la Cola de revisión con clic derecho → Obtener detalles")
    v.append(visual(p, "perfil", "tableEx", 20, 76, 1240, 90,
                    {"Values": [col("Clientes", c) for c in ("id_cliente", "nivel_riesgo", "score_riesgo", "motivos",
                                                             "canal_principal", "ops", "dias_activos", "monto_ars")]},
                    objects=table_objects(), z=2))
    v.append(visual(p, "serie", "columnChart", 20, 180, 1240, 220,
                    {"Category": [col("Calendario", "fecha")], "Series": [col("Operaciones", "tipo_tran")], "Y": [meas("Cant. operaciones")]},
                    title="Operaciones por día", z=3))
    v.append(visual(p, "ops", "tableEx", 20, 414, 1240, 292,
                    {"Values": [col("Operaciones", c) for c in ("fecha_art", "canal", "tipo_tran", "simbolo_titulo",
                                                                "cantidad", "precio", "monto_ars", "flag_precio_fuera_mercado")]},
                    objects=table_objects(), sort=[(col("Operaciones", "fecha_art"), "Ascending")], title="Operaciones", z=4))
    extra = {
        "filterConfig": {"filters": [{"name": fname, "field": col("Clientes", "id_cliente"), "type": "Categorical",
                                      "howCreated": "Drillthrough"}]},
        "pageBinding": {"name": "Pod", "type": "Drillthrough",
                        "parameters": [{"name": "Param_" + fname, "boundFilter": fname, "fieldExpr": col("Clientes", "id_cliente")}]},
    }
    page(p, "Detalle de cliente", v, extra)

    # ---------------- 6. Datos externos (API)
    p = "api"
    v = header(p, "Datos externos (APIs)", "Feriados 2026 y dólar MEP: qué fuente respondió en la última corrida y cómo se usó")
    v.append(visual(p, "tc", "lineChart", 20, 76, 800, 300,
                    {"Category": [col("Calendario", "fecha")], "Series": [col("Calendario", "fuente_tc")],
                     "Y": [agg("Calendario", "tc_ars_por_usd")]}, title="Tipo de cambio usado (ARS por USD)", z=2))
    v.append(visual(p, "feriados", "tableEx", 840, 76, 420, 300,
                    {"Values": [col("Calendario", "fecha"), col("Calendario", "dia_semana"), col("Calendario", "feriado")]},
                    objects=table_objects(), title="Feriados del período (API)",
                    filters=[in_filter("feriado_no_vacio", "Calendario", "feriado", ["null", "''"], negate=True)], z=3))
    v.append(visual(p, "log", "tableEx", 20, 390, 1240, 316,
                    {"Values": [col("ApiLog", c) for c in ("api", "estado", "filas", "detalle", "url")]},
                    objects=table_objects(), title="Log de llamadas a las APIs", z=4))
    page(p, "Datos externos (API)", v)


def write_theme():
    rr = os.path.join(PBI, "IOL_PLAFT.Report", "StaticResources", "RegisteredResources")
    os.makedirs(rr, exist_ok=True)
    for f in os.listdir(rr):
        if f.startswith("IOL-PLAFT-") and f != THEME_NAME:
            os.remove(os.path.join(rr, f))
    with open(os.path.join(rr, THEME_NAME), "w", encoding="utf-8") as fh:
        json.dump(THEME, fh, indent=2)
    rpath = os.path.join(RP, "report.json")
    rep = json.load(open(rpath, encoding="utf-8"))
    base = rep["themeCollection"]["baseTheme"]
    rep["themeCollection"]["customTheme"] = {"name": THEME_NAME, "reportVersionAtImport": base["reportVersionAtImport"],
                                             "type": "RegisteredResources"}
    rep["resourcePackages"] = [r for r in rep["resourcePackages"] if r["type"] != "RegisteredResources"]
    rep["resourcePackages"].append({"name": "RegisteredResources", "type": "RegisteredResources",
                                    "items": [{"name": THEME_NAME, "path": THEME_NAME, "type": "CustomTheme"},
                                              {"name": LOGO_NAME, "path": LOGO_NAME, "type": "Image"}]})
    with open(rpath, "w", encoding="utf-8") as fh:
        json.dump(rep, fh, ensure_ascii=False, indent=2)


# Nombres de visuales que quedaron en la carpeta de la primera página de una versión anterior:
# la portada los reutiliza para sobrescribirlos (evita visuales huérfanos sin borrar archivos).
LEGACY_FIRST_PAGE_VISUALS = ["01828dda5934f0e61da7", "5757051e536eb92bd9c6", "6cba54b914789bf202f2", "9b25e3820f8db11b7e33",
                             "a0f6866af8b7922bd17c", "ae3e8a959d4bed6b4421", "aeb10b421d2e9e9ee90d"]


def write_report():
    pages_dir = os.path.join(RP, "pages")
    for d in os.listdir(pages_dir):
        full = os.path.join(pages_dir, d)
        if os.path.isdir(full):
            shutil.rmtree(full)
    order = []
    for pid, display, visuals, extra in PAGES:
        order.append(pid)
        pdir = os.path.join(pages_dir, pid)
        os.makedirs(os.path.join(pdir, "visuals"))
        pg = {"$schema": PAGE_SCHEMA, "name": pid, "displayName": display, "displayOption": "FitToPage",
              "height": H, "width": W}
        pg.update(extra)
        if extra.get("pageBinding"):
            pg["visibility"] = "HiddenInViewMode"
        with open(os.path.join(pdir, "page.json"), "w", encoding="utf-8") as fh:
            json.dump(pg, fh, ensure_ascii=False, indent=2)
        if pid == FIRST_PAGE_ID:
            visuals = [(LEGACY_FIRST_PAGE_VISUALS[i], {**d, "name": LEGACY_FIRST_PAGE_VISUALS[i]})
                       if i < len(LEGACY_FIRST_PAGE_VISUALS) else (n, d) for i, (n, d) in enumerate(visuals)]
        for name, d in visuals:
            vdir = os.path.join(pdir, "visuals", name)
            os.makedirs(vdir)
            with open(os.path.join(vdir, "visual.json"), "w", encoding="utf-8") as fh:
                json.dump(d, fh, ensure_ascii=False, indent=2)
    with open(os.path.join(pages_dir, "pages.json"), "w", encoding="utf-8") as fh:
        json.dump({"$schema": PAGES_SCHEMA, "pageOrder": order, "activePageName": order[0]}, fh, indent=2)


if __name__ == "__main__":
    build_model()
    build_report()
    write_report()
    write_theme()
    n = sum(len(v) for _, _, v, _ in PAGES)
    print(f"PBIP generado: {len(T) + 1} tablas, {len(MEASURES)} medidas, {len(PAGES)} páginas, {n} visuales")
