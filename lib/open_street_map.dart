import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const cairoDeliveryCenter = LatLng(30.0444, 31.2357);

class OpenStreetMapPreview extends StatelessWidget {
  const OpenStreetMapPreview({super.key, this.height = 205});

  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: height,
          child: FlutterMap(
            options: const MapOptions(
                initialCenter: cairoDeliveryCenter, initialZoom: 12.5),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.maa.delivery.maaDriver',
                maxZoom: 19,
              ),
              MarkerLayer(markers: [
                Marker(
                  point: const LatLng(30.0561, 31.3300),
                  width: 46,
                  height: 50,
                  child: const Icon(Icons.delivery_dining,
                      color: Color(0xFF142443), size: 36),
                ),
                Marker(
                  point: const LatLng(30.0444, 31.2357),
                  width: 46,
                  height: 50,
                  child: const Icon(Icons.restaurant,
                      color: Color(0xFFFF702E), size: 32),
                ),
              ]),
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomRight,
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors')
                ],
              ),
            ],
          ),
        ),
      );
}
