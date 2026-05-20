@echo off
REM Avvia SOLEM Progress Server in localhost:9000 + apre browser
REM Doppio-click su questo file per partire.
set DIR=%~dp0
cd /d "%DIR%"
start "" "http://localhost:9000"
python server.py
