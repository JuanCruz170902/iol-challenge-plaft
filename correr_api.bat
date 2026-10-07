@echo off
REM Corre la consulta a las APIs externas (Task 03) con el Python instalado en esta PC.
cd /d "%~dp0"
set "PY=%LOCALAPPDATA%\Programs\Python\Python310\python.exe"
if not exist "%PY%" set "PY=python"
"%PY%" scripts\fetch_api.py
echo.
echo Resultado (data\api\api_log.csv):
type data\api\api_log.csv
echo.
echo Listo. Ya podes cerrar esta ventana.
pause
