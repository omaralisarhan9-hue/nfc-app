@echo off
chcp 65001 > nul
echo ========================================================
echo       Starting NFC Card Manager Web Server...
echo ========================================================
start http://localhost:8080
python -m http.server 8080
