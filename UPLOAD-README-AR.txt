تطبيق driver مستقل
- هذا المجلد مشروع Flutter منفصل، ويتضمن حزمة shared محليًا حتى لا يعتمد على مجلدات المشروع الأم.
- افتح هذا المجلد في Android Studio أو VS Code بعد تثبيت Flutter 3.27 أو أحدث.
- نفّذ: flutter pub get
- ثم: flutter build apk --release
- لإصدار Google Play: flutter build appbundle --release
- يجب إعداد تطبيق Firebase المطابق وإضافة ملفات إعداد Android/iOS المطلوبة قبل البناء النهائي؛ لا توجد مفاتيح أو أسرار إنتاجية مضمّنة.
