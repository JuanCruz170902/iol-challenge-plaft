#!/usr/bin/env bash
# Ejecuta el pipeline completo. Requiere PostgreSQL (psql en el PATH) y Python 3.
# Variables opcionales: PGHOST, PGPORT, PGUSER, PGPASSWORD (las lee psql). Base: iol.
set -euo pipefail
cd "$(dirname "$0")"
DB="${DB:-iol}"
createdb "$DB" 2>/dev/null || true
PSQL="psql -d $DB -v ON_ERROR_STOP=1 -q"
$PSQL -f sql/00_carga.sql
$PSQL -f sql/01_exploracion.sql          > outputs/01_exploracion.txt
python3 scripts/fetch_api.py
$PSQL -f sql/02_api_enriquecimiento.sql  > outputs/02_api_enriquecimiento.txt
$PSQL -f sql/03_patrones_anomalos.sql    > outputs/03_patrones_anomalos.txt
$PSQL -f sql/04_vistas_powerbi.sql
echo "OK - resultados en outputs/, vistas iol.vw_* listas para Power BI"
