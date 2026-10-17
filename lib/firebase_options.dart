import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

/// تُمرر القيم العامة عند البناء عبر --dart-define. لا تضع هنا مفتاح Admin الخاص.
FirebaseOptions? maaFirebaseOptions() {
  const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID_DRIVER');
  const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID_DRIVER');
  if (apiKey.isEmpty || senderId.isEmpty || projectId.isEmpty) return null;
  if (Platform.isAndroid && androidAppId.isNotEmpty) {
    return FirebaseOptions(
        apiKey: apiKey,
        appId: androidAppId,
        messagingSenderId: senderId,
        projectId: projectId);
  }
  if (Platform.isIOS && iosAppId.isNotEmpty) {
    return FirebaseOptions(
        apiKey: apiKey,
        appId: iosAppId,
        messagingSenderId: senderId,
        projectId: projectId,
        iosBundleId: 'com.maa.delivery.maaDriver');
  }
  return null;
}
