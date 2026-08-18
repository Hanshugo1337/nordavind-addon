@echo off
title NordavindLC Companion (utviklingsmodus)
cd /d "%~dp0"

REM Normalt skal du bruke den INSTALLERTE appen - den ligger i Start-menyen
REM og starter automatisk med Windows. Denne fila er kun en reserve for aa
REM kjoere rett fra kildekoden, f.eks. etter en kodeendring uten nytt bygg.
REM
REM (Tidligere kjoerte denne "node index.js watch". Den fila ble slettet da
REM  appen ble skrevet om til Electron, saa skriptet krasjet.)

echo Starter NordavindLC Companion fra kildekode...
call npm start
if errorlevel 1 (
  echo.
  echo Start feilet. Har du kjoert "npm install" i denne mappa?
  pause
)
