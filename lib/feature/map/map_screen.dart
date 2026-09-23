import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../../app_config.dart';
import '../../model/store_model.dart';
import 'map_controller.dart';

class MapScreen extends GetView<StoresMapController> {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stores near you')),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return FlutterMap(
          options: MapOptions(
            center: StoresMapController.initialCenter,
            zoom: 12,
            maxZoom: 18,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'dev.rescu.rescu',
            ),
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                maxClusterRadius: 60,
                size: const Size(40, 40),
                markers: controller.stores
                    .map((store) => Marker(
                          point: LatLng(store.lat, store.lng),
                          width: 40,
                          height: 40,
                          builder: (context) => GestureDetector(
                            onTap: () => _showStoreSheet(context, store),
                            child: const Icon(Icons.location_pin,
                                size: 40, color: AppConfig.primaryGreen),
                          ),
                        ))
                    .toList(),
                builder: (context, markers) => Container(
                  decoration: const BoxDecoration(
                    color: AppConfig.primaryGreen,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text('${markers.length}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  void _showStoreSheet(BuildContext context, StoreModel store) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(store.name,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${store.category} · ${store.address}',
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.schedule,
                    size: 16, color: AppConfig.primaryGreen),
                const SizedBox(width: 6),
                Text('Pickup ${store.pickupWindow.label}',
                    style: const TextStyle(fontSize: 14)),
                const Spacer(),
                if (store.rating != null) ...[
                  const Icon(Icons.star_rounded,
                      size: 16, color: Colors.amber),
                  Text(' ${store.rating!.toStringAsFixed(1)}'),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
