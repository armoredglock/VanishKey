@echo off
title VanishKey Desktop Host

:: Check for Administrator elevation and self-elevate
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [i] Requesting Administrator privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0agent-cli"
echo ===================================================
echo     VanishKey Desktop Host (24/7 Cloud Mode)
echo ===================================================
echo [✔] Administrator privileges confirmed.
echo [✔] Connecting to 24/7 Render Cloud Relay:
echo     https://vanishkey-relay.onrender.com
echo.
echo Host Agent is active. Keep this window open in background.
echo ===================================================
echo.
set RELAY_URL=https://vanishkey-relay.onrender.com
node src/index.js
pause
