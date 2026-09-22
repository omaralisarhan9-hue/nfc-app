@echo off
chcp 65001 > nul
echo ========================================================
echo       Building NFC Card Manager APK...
echo ========================================================
cd flutter_app
call flutter build apk --release
echo.
echo ========================================================
if exist build\app\outputs\flutter-apk\app-release.apk (
    echo [SUCCESS] APK Created successfully!
    copy build\app\outputs\flutter-apk\app-release.apk ..\NFC_Card_Manager_Release.apk
    echo Copied to NFC_Card_Manager_Release.apk in main folder!
) else (
    echo If Flutter is not installed, install via: winget install Google.Flutter
    echo Or build via GitHub Actions in the cloud for free!
)
echo ========================================================
pause
