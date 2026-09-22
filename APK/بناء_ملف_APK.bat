@echo off
chcp 65001 > nul
echo ========================================================
echo       جاري بناء ملف الـ APK لتطبيق NFC Card Manager...
echo ========================================================
cd flutter_app
call flutter build apk --release
echo.
echo ========================================================
if exist build\app\outputs\flutter-apk\app-release.apk (
    echo تم إنشاء ملف الـ APK بنجاح!
    copy build\app\outputs\flutter-apk\app-release.apk ..\NFC_Card_Manager_Release.apk
    echo تم نسخ الـ APK إلى المجلد الرئيسي باسم NFC_Card_Manager_Release.apk
) else (
    echo إذا لم يكن فلاتر مثبتًا، يمكنك تثبيته عبر: winget install Google.Flutter
    echo أو بناء الـ APK عبر GitHub Actions في السحابة مجانًا.
)
echo ========================================================
pause
