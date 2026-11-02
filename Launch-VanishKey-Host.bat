@echo off
title VanishKey Desktop Host

:: Verify Administrator privileges
powershell -NoProfile -Command "([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)" | findstr "True" >nul
if %errorlevel% neq 0 (
    echo ===================================================
    echo   Elevating to Administrator Privileges...
    echo ===================================================
    echo Please click "Yes" on the Windows prompt!
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -Command Set-Location ''%~dp0agent-cli''; $env:RELAY_URL=''https://vanishkey-relay.onrender.com''; node src/index.js'"
    exit /b
)

cd /d "%~dp0agent-cli"
set RELAY_URL=https://vanishkey-relay.onrender.com
node src/index.js
pause
