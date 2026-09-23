import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../service/analytics_service.dart';

/// Developer screen: shows every analytics event recorded this session.
/// Useful for verifying the impression-tracking feature task.
class AnalyticsDebugScreen extends StatelessWidget {
  const AnalyticsDebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final analytics = Get.find<AnalyticsService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics debug')),
      body: Obx(() {
        final events = analytics.events.reversed.toList();
        if (events.isEmpty) {
          return const Center(child: Text('No events yet'));
        }
        return ListView.builder(
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            return ListTile(
              dense: true,
              leading: Text(
                event.at.toIso8601String().substring(11, 19),
                style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Colors.grey.shade600),
              ),
              title: Text(event.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text('${event.properties}',
                  style: const TextStyle(fontSize: 12)),
            );
          },
        );
      }),
    );
  }
}
