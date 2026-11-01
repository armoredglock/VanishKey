@echo off
title VanishKey Global Cloud Launcher

:: Check for Administrator elevation and self-elevate
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [i] Requesting Administrator privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
echo ===================================================
echo         VanishKey Global Cloud Launcher
echo ===================================================
echo [✔] Administrator privileges confirmed.
echo [✔] Global Cloud Relay URL:
echo     https://rhode-mathematical-less-load.trycloudflare.com
echo.
echo Connecting to Global Cloud Relay...
echo Please KEEP this window open in background.
echo ===================================================
echo.
cd agent-cli
set RELAY_URL=https://rhode-mathematical-less-load.trycloudflare.com
node src/index.js
pause
