# تطبيق إدارة وبطاقات NFC (قراءة، تعديل، وكتابة)

يوفر هذا المشروع حلين متكاملين للتعامل مع بطاقات NFC:
1. **تطبيق ويب تفاعلي سريع (Web NFC)**: يعمل مباشرة داخل المتصفح (Google Chrome على Android).
2. **تطبيق Flutter مخصص**: جاهز للتحزيم كـ APK أو تطبيق لنظامي Android و iOS.

---

## 1. تطبيق الويب المباشر (Web NFC PWA)

الملفات:
- `index.html`: واجهة المستخدم.
- `style.css`: التنسيقات والتصميم الداكن الحديث.
- `app.js`: منطق قراءة NFC، فك ترميز السجلات، تعديل البيانات، وإعادة الكتابة، بالإضافة لسجل البطاقات المحفوظة.

### كيفية التشغيل والتجربة:
> [!NOTE]
> تتطلب ميزة Web NFC بيئة آمنة **HTTPS** (أو `localhost`) ومتصفح **Google Chrome** على هاتف يدعم NFC بنظام Android.

يمكنك تجربة التطبيق محلياً عبر أي خادم محلي، مثل:
```bash
npx serve .
# أو بايثون:
python -m http.server 8080
```
أو رفعه مجاناً على **GitHub Pages** أو **Vercel** لفتحه مباشرة من الهاتف برابط HTTPS.

---

## 2. تطبيق الهاتف المتكامل (Flutter)

المسار: `flutter_app/`

### المميزات:
- فحص توفر الـ NFC بالجهاز تلقائياً.
- قراءة المعرف الفريد للبطاقة (UID) ومحتوى NDEF.
- صندوق تعديل مخصص لتحرير القيم.
- كتابة المحتوى المعدل وحفظه على الشريحة بضغطة زر.

### تشغيل تطبيق Flutter:
```bash
cd flutter_app
flutter pub get
flutter run
```

### الأذونات المطلوبة في Android (`AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.NFC" />
<uses-feature android:name="android.hardware.nfc" android:required="true" />
```
