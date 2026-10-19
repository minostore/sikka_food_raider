import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

/// مشروع Firebase المشترك لكل تطبيقات معًا. يمكن تجاوز أي قيمة بـ --dart-define.
/// هذه المفاتيح عامة بطبيعتها؛ الحماية الفعلية تأتي من firestore.rules.
///
/// ملاحظة: القيمة الافتراضية لمعرّف تطبيق Android هي التطبيق المسجل حاليًا (com.sikka.eg).
/// سجّل تطبيق Android لهذا التطبيق (com.maa.delivery.maa_driver) في Firebase
/// ثم مرّر معرّفه عبر FIREBASE_ANDROID_APP_ID_DRIVER ليعمل FCM بشكل صحيح.
FirebaseOptions? maaFirebaseOptions() {
  const apiKey = String.fromEnvironment('FIREBASE_API_KEY',
      defaultValue: 'AIzaSyCEHwyKZBC4o1bo3sfAj8Czn7VdfV5Rw_0');
  const iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY',
      defaultValue: 'AIzaSyBM2YY3IBXVoCKEqA6BJNm0fx4I2m93udU');
  const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID',
      defaultValue: '979261642656');
  const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID',
      defaultValue: 'independent-6c331');
  const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID_DRIVER',
      defaultValue: '1:979261642656:android:64aa61de216223def176c5');
  const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID_DRIVER',
      defaultValue: '1:979261642656:ios:a215fb5884fc885af176c5');
  if (Platform.isAndroid) {
    return const FirebaseOptions(
        apiKey: apiKey,
        appId: androidAppId,
        messagingSenderId: senderId,
        projectId: projectId);
  }
  if (Platform.isIOS) {
    return const FirebaseOptions(
        apiKey: iosApiKey,
        appId: iosAppId,
        messagingSenderId: senderId,
        projectId: projectId,
        iosBundleId: 'com.sikka.eg');
  }
  return null;
}
