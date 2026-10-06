# Ejecuta el pipeline completo en Windows (PowerShell).
# Requiere PostgreSQL (psql.exe y createdb.exe en el PATH, p.ej. C:\Program Files\PostgreSQL\16\bin) y Python 3.
# Usuario/clave: definir $env:PGUSER y $env:PGPASSWORD antes de correr (por defecto usuario "postgres").
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
if (-not $env:PGUSER) { $env:PGUSER = "postgres" }
$env:PGCLIENTENCODING = "UTF8"
$DB = "iol"
& createdb $DB 2>$null
function Run-Sql($file, $out) {
    if ($out) { & psql -d $DB -v ON_ERROR_STOP=1 -q -f $file | Out-File -Encoding utf8 $out }
    else      { & psql -d $DB -v ON_ERROR_STOP=1 -q -f $file }
    if ($LASTEXITCODE -ne 0) { throw "Falló $file" }
}
Run-Sql "sql/00_carga.sql"
Run-Sql "sql/01_exploracion.sql"         "outputs/01_exploracion.txt"
& python scripts/fetch_api.py
if ($LASTEXITCODE -ne 0) { throw "Falló fetch_api.py" }
Run-Sql "sql/02_api_enriquecimiento.sql" "outputs/02_api_enriquecimiento.txt"
Run-Sql "sql/03_patrones_anomalos.sql"   "outputs/03_patrones_anomalos.txt"
Run-Sql "sql/04_vistas_powerbi.sql"
New-Item -ItemType Directory -Force -Path "powerbi/data" | Out-Null
Run-Sql "sql/05_export_powerbi.sql"
Write-Host "OK - resultados en outputs/, vistas iol.vw_* listas para Power BI"
