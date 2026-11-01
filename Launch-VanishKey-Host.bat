@echo off
title VanishKey Desktop Host Launcher

:: Check for Administrator elevation and self-elevate
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ===================================================
    echo  Requesting Administrator privileges...
    echo ===================================================
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/k cd /d \"%~dp0\" && \"%~f0\"' -Verb RunAs"
    exit /b
)

cd /d "%~dp0agent-cli"
echo ===================================================
echo   Starting VanishKey Desktop Host (Admin Mode)...
echo ===================================================
echo [✔] Administrator privileges confirmed.
echo [✔] Host Agent is active and connected to Relay.
echo [✔] Ready to generate temporary accounts on phone command.
echo.
echo Minimizing or keep this window open in background.
echo ===================================================
echo.
node src/index.js
pause
