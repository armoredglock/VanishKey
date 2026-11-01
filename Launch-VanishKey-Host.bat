@echo off
title VanishKey Desktop Host Launcher
cd /d "%~dp0agent-cli"
echo ===================================================
echo           Starting VanishKey Desktop Host...
echo ===================================================
call npm run show-qr
start "" "%~dp0agent-cli\pairing-qr.html"
echo.
echo Host Agent is active. Minimizing or keep this window open.
echo.
node src/index.js
pause
