@echo off
title VanishKey Relay Server
cd /d "%~dp0server"
echo ===================================================
echo           Starting VanishKey Relay Server...
echo ===================================================
node src/index.js
pause
