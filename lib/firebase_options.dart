import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

/// مشروع Firebase المشترك لكل تطبيقات معًا. يمكن تجاوز أي قيمة بـ --dart-define.
/// هذه المفاتيح عامة بطبيعتها؛ الحماية الفعلية تأتي من firestore.rules.
///
/// ملاحظة: القيمة الافتراضية لمعرّف تطبيق Android هي التطبيق المسجل حاليًا (com.sikka.eg).
/// سجّل تطبيق Android لهذا التطبيق (com.maa.delivery.maa_driver) في Firebase
/// ثم مرّر معرّفه عبر FIREBASE_ANDROID_APP_ID_DRIVER ليعمل FCM بشكل صحيح.
FirebaseOptions? maaFirebaseOptions() {
  const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  const _apiKeyDefault = 'AIzaSyCEHwyKZBC4o1bo3sfAj8Czn7VdfV5Rw_0';
  final apiKey = _apiKey.isEmpty ? _apiKeyDefault : _apiKey;
  const _iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
  const _iosApiKeyDefault = 'AIzaSyBM2YY3IBXVoCKEqA6BJNm0fx4I2m93udU';
  final iosApiKey = _iosApiKey.isEmpty ? _iosApiKeyDefault : _iosApiKey;
  const _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  const _senderIdDefault = '979261642656';
  final senderId = _senderId.isEmpty ? _senderIdDefault : _senderId;
  const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  const _projectIdDefault = 'independent-6c331';
  final projectId = _projectId.isEmpty ? _projectIdDefault : _projectId;
  const _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID_DRIVER');
  const _androidAppIdDefault = '1:979261642656:android:64aa61de216223def176c5';
  final androidAppId = _androidAppId.isEmpty ? _androidAppIdDefault : _androidAppId;
  const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID_DRIVER');
  const _iosAppIdDefault = '1:979261642656:ios:a215fb5884fc885af176c5';
  final iosAppId = _iosAppId.isEmpty ? _iosAppIdDefault : _iosAppId;
  if (Platform.isAndroid) {
    return FirebaseOptions(
        apiKey: apiKey,
        appId: androidAppId,
        messagingSenderId: senderId,
        projectId: projectId);
  }
  if (Platform.isIOS) {
    return FirebaseOptions(
        apiKey: iosApiKey,
        appId: iosAppId,
        messagingSenderId: senderId,
        projectId: projectId,
        iosBundleId: 'com.sikka.eg');
  }
  return null;
}
