import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'maa_core.dart';

typedef MaaLatLng = ({double lat, double lng});

/// موقع الجهاز الحالي مرة واحدة (أو null إذا رُفض الإذن/الخدمة معطلة).
Future<MaaLatLng?> maaCurrentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
    return (lat: p.latitude, lng: p.longitude);
  } catch (e) {
    debugPrint('Location unavailable: $e');
    return null;
  }
}

/// ينشر موقع السائق إلى drivers/{uid} ما دام التطبيق مفتوحًا وهو "متاح".
/// تظهر المواقع في خريطة الطلبات المباشرة بلوحة التحكم وعند العميل أثناء التوصيل.
class MaaLocationPublisher {
  MaaLocationPublisher(this.session);
  final MaaSession session;
  StreamSubscription<Position>? _sub;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  bool get running => _sub != null;

  Future<bool> start() async {
    if (_sub != null) return true;
    final first = await maaCurrentPosition();
    if (first == null) return false;
    await _push(first.lat, first.lng);
    _sub = Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high, distanceFilter: 40))
        .listen((p) => _push(p.latitude, p.longitude), onError: (_) {});
    return true;
  }

  Future<void> _push(double lat, double lng) async {
    final now = DateTime.now();
    if (now.difference(_last).inSeconds < 10) return;
    _last = now;
    try {
      await session.profileRef.update({
        'lat': lat,
        'lng': lng,
        'location': '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
        'lastSeen': maaNow(),
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Location publish failed: $e');
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
