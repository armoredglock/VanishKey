@echo off
title VanishKey Desktop Host

:: Check for Administrator elevation and self-elevate
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [i] Requesting Administrator privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "D:\PROJECTS\VanishKey\agent-cli"
echo ===================================================
echo   Starting VanishKey Desktop Host (Admin Mode)...
echo ===================================================
echo [✔] Running with Administrator privileges.
echo [✔] Connecting to VanishKey Relay Server...
echo.
echo Please KEEP this window open in the background!
echo ===================================================
echo.
node src/index.js
pause
