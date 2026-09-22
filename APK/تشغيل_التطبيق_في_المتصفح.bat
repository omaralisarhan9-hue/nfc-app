@echo off
chcp 65001 > nul
echo ========================================================
echo     جاري تشغيل خادم تطبيق NFC Card Manager...
echo ========================================================
start http://localhost:8080
python -m http.server 8080
