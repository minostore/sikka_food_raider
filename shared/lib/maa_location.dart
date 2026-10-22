import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

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

/// يفتح تطبيق الخرائط للتوجه إلى الإحداثيات.
Future<bool> maaOpenMaps(double lat, double lng) => launchUrl(
    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving'),
    mode: LaunchMode.externalApplication);

/// يتصل برقم هاتف.
Future<bool> maaCall(String phone) =>
    launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s'), '')));

/// المسافة بالكيلومتر بين نقطتين (Haversine).
double maaDistanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.sqrt(a));
}

class MaaPlace {
  const MaaPlace(this.address, this.governorate, this.area);
  final String address, governorate, area;
}

/// يحوّل إحداثيات إلى عنوان ومحافظة ومنطقة تلقائيًا (OpenStreetMap Nominatim).
Future<MaaPlace?> maaReverseGeocode(double lat, double lng) async {
  try {
    final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&zoom=17&addressdetails=1&accept-language=ar'),
        headers: {'User-Agent': 'MaaDelivery/1.0'}).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final a = (body['address'] as Map?)?.cast<String, dynamic>() ?? {};
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = (a[k] ?? '').toString();
        if (v.isNotEmpty) return v;
      }
      return '';
    }
    final stateRaw = pick(['state', 'province', 'region']).replaceAll('محافظة', '').trim();
    var governorate = '';
    for (final g in maaGovernorates) {
      if (stateRaw.contains(g) || g.contains(stateRaw) && stateRaw.isNotEmpty) {
        governorate = g;
        break;
      }
    }
    final area = pick(['suburb', 'city_district', 'neighbourhood', 'quarter', 'town', 'village', 'city', 'county']);
    final road = pick(['road', 'pedestrian', 'residential']);
    final text = [road, area, stateRaw].where((e) => e.isNotEmpty).join('، ');
    return MaaPlace(text.isEmpty ? (body['display_name'] ?? '').toString() : text, governorate, area);
  } catch (e) {
    debugPrint('Reverse geocode failed: $e');
    return null;
  }
}
