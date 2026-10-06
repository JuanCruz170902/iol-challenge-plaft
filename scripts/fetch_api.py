"""
fetch_api.py — TASK 03: consulta a APIs externas y genera CSVs para cargar en PostgreSQL.

Qué trae:
  1) Feriados 2026 (Argentina)  -> data/api/feriados_2026.csv
     Fuente principal: https://nolaborables.com.ar/api/v2/feriados/2026  (la sugerida en la consigna)
     Fallback 1:       https://api.argentinadatos.com/v1/feriados/2026     (mismo dato, API mantenida)
     Fallback 2:       data/api/snapshot/feriados_2026.json                (copia versionada en el repo)

  2) Dólar MEP / "bolsa" diario   -> data/api/tipo_cambio_mep.csv
     Fuente principal: https://api.argentinadatos.com/v1/cotizaciones/dolares/bolsa
     Fallback:         si la API no responde, el CSV queda vacío y el SQL (02_api_enriquecimiento.sql)
                       usa el MEP implícito calculado con el propio dataset (precio AL30 / AL30D).

  Cada intento (exitoso o fallido) queda registrado en data/api/api_log.csv, que también se carga a la base.

Por qué dólar MEP y no oficial: las operaciones en USD del dataset son bursátiles (AL30D, CEDEARs en D…);
el tipo de cambio que "usa" un inversor para pasar de pesos a dólares en el mercado es el MEP, no el oficial.

Solo usa la librería estándar de Python (sin pip install).
Uso:  python scripts/fetch_api.py
"""

from __future__ import annotations

import csv
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import date, datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "data", "api")
SNAPSHOT_FERIADOS = os.path.join(OUT_DIR, "snapshot", "feriados_2026.json")

URL_FERIADOS_NOLAB = "https://nolaborables.com.ar/api/v2/feriados/2026"
URL_FERIADOS_ARGDATOS = "https://api.argentinadatos.com/v1/feriados/2026"
URL_MEP_ARGDATOS = "https://api.argentinadatos.com/v1/cotizaciones/dolares/bolsa"

PERIODO_DESDE = date(2025, 12, 15)  # margen para arrastrar la última cotización conocida
PERIODO_HASTA = date(2026, 3, 31)
TIMEOUT_S = 20

LOG: list[dict] = []


def log(api: str, url: str, estado: str, filas: int, detalle: str = "") -> None:
    LOG.append(
        {
            "ts_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "api": api,
            "url": url,
            "estado": estado,
            "filas": filas,
            "detalle": detalle[:300],
        }
    )
    print(f"[{estado:>8}] {api:<10} {url}  filas={filas} {detalle}")


def http_get_json(url: str):
    """GET con timeout y User-Agent; devuelve el JSON parseado o lanza excepción."""
    req = urllib.request.Request(url, headers={"User-Agent": "iol-challenge-plaft/1.0", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
        if resp.status != 200:
            raise RuntimeError(f"HTTP {resp.status}")
        return json.loads(resp.read().decode("utf-8"))


# ----------------------------------------------------------------------------- feriados
def parse_feriados(payload, anio: int = 2026) -> list[dict]:
    """
    Normaliza los dos formatos conocidos a filas {fecha, nombre, tipo}:
      - nolaborables v2:  [{"motivo": "...", "tipo": "inamovible", "dia": 1, "mes": 1, ...}, ...]
      - argentinadatos:   [{"fecha": "2026-01-01", "tipo": "inamovible", "nombre": "..."}, ...]
    """
    filas = []
    for item in payload:
        if "fecha" in item:
            f = date.fromisoformat(item["fecha"])
            nombre = item.get("nombre", "")
        else:
            f = date(anio, int(item["mes"]), int(item["dia"]))
            nombre = item.get("motivo", "")
        filas.append({"fecha": f.isoformat(), "nombre": nombre, "tipo": item.get("tipo", "")})
    if not filas:
        raise ValueError("respuesta vacía")
    return sorted(filas, key=lambda r: r["fecha"])


def obtener_feriados() -> list[dict]:
    for api, url in (("nolaborables", URL_FERIADOS_NOLAB), ("argdatos", URL_FERIADOS_ARGDATOS)):
        try:
            filas = parse_feriados(http_get_json(url))
            log(api, url, "OK", len(filas))
            for f in filas:
                f["fuente"] = api
            return filas
        except (urllib.error.URLError, TimeoutError, ValueError, KeyError, RuntimeError, OSError) as e:
            log(api, url, "ERROR", 0, f"{type(e).__name__}: {e}")

    # último recurso: snapshot versionado
    with open(SNAPSHOT_FERIADOS, encoding="utf-8") as fh:
        filas = parse_feriados(json.load(fh))
    log("snapshot", os.path.relpath(SNAPSHOT_FERIADOS, ROOT).replace(os.sep, "/"), "FALLBACK", len(filas), "se usó la copia local versionada")
    for f in filas:
        f["fuente"] = "snapshot"
    return filas


# ----------------------------------------------------------------------------- dólar MEP
def parse_cotizaciones(payload) -> list[dict]:
    """argentinadatos: [{"casa": "bolsa", "compra": 1498.8, "venta": 1507.8, "fecha": "2026-01-02"}, ...]"""
    filas = []
    for item in payload:
        f = date.fromisoformat(item["fecha"])
        if PERIODO_DESDE <= f <= PERIODO_HASTA:
            filas.append(
                {
                    "fecha": f.isoformat(),
                    "compra": float(item["compra"]),
                    "venta": float(item["venta"]),
                    "fuente": "argdatos_bolsa",
                }
            )
    return sorted(filas, key=lambda r: r["fecha"])


def obtener_mep() -> list[dict]:
    try:
        filas = parse_cotizaciones(http_get_json(URL_MEP_ARGDATOS))
        if not filas:
            raise ValueError("la API respondió pero sin cotizaciones para el período")
        log("argdatos", URL_MEP_ARGDATOS, "OK", len(filas))
        return filas
    except (urllib.error.URLError, TimeoutError, ValueError, KeyError, RuntimeError, OSError) as e:
        log("argdatos", URL_MEP_ARGDATOS, "ERROR", 0, f"{type(e).__name__}: {e}")
        log("mep_impl", "dataset AL30/AL30D", "FALLBACK", 0, "el SQL calcula el MEP implícito con el dataset")
        return []


# ----------------------------------------------------------------------------- main
def write_csv(path: str, rows: list[dict], cols: list[str]) -> None:
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)

    feriados = obtener_feriados()
    write_csv(os.path.join(OUT_DIR, "feriados_2026.csv"), feriados, ["fecha", "nombre", "tipo", "fuente"])

    mep = obtener_mep()
    write_csv(os.path.join(OUT_DIR, "tipo_cambio_mep.csv"), mep, ["fecha", "compra", "venta", "fuente"])

    write_csv(os.path.join(OUT_DIR, "api_log.csv"), LOG, ["ts_utc", "api", "url", "estado", "filas", "detalle"])
    print(f"\nListo: {len(feriados)} feriados, {len(mep)} cotizaciones MEP. Log en data/api/api_log.csv")
    return 0


if __name__ == "__main__":
    sys.exit(main())
