import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const defaultMapCenter = LatLng(30.0444, 31.2357); // القاهرة

class MapPin {
  const MapPin(this.lat, this.lng, this.icon, this.color);
  final double lat, lng;
  final IconData icon;
  final Color color;
}

/// خريطة OpenStreetMap تعرض علامات حقيقية قادمة من Firestore.
class OpenStreetMapPreview extends StatelessWidget {
  const OpenStreetMapPreview(
      {super.key, this.height = 205, this.pins = const [], this.zoom = 13});

  final double height;
  final List<MapPin> pins;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final center = pins.isEmpty
        ? defaultMapCenter
        : LatLng(
            pins.map((p) => p.lat).reduce((a, b) => a + b) / pins.length,
            pins.map((p) => p.lng).reduce((a, b) => a + b) / pins.length);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          key: ValueKey('${center.latitude.toStringAsFixed(3)}:${center.longitude.toStringAsFixed(3)}:${pins.length}'),
          options: MapOptions(
              initialCenter: center, initialZoom: pins.length > 1 ? zoom - 1 : zoom),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.maa.delivery.maaDriver',
              maxZoom: 19,
            ),
            MarkerLayer(markers: [
              for (final p in pins)
                Marker(
                  point: LatLng(p.lat, p.lng),
                  width: 46,
                  height: 50,
                  child: Icon(p.icon, color: p.color, size: 34),
                ),
            ]),
            const RichAttributionWidget(
              alignment: AttributionAlignment.bottomRight,
              attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
            ),
          ],
        ),
      ),
    );
  }
}
