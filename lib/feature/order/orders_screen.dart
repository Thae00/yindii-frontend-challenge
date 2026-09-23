import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../model/order_model.dart';
import '../shared_widget/the_network_image.dart';
import 'orders_controller.dart';
import 'widget/pickup_countdown.dart';

class OrdersScreen extends GetView<OrdersController> {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My orders')),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.orders.isEmpty) {
          return const Center(child: Text('No orders yet'));
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (controller.activeOrders.isNotEmpty) ...[
              const _SectionHeader('Active'),
              ...controller.activeOrders
                  .map((o) => _OrderTile(order: o, showCountdown: true)),
            ],
            if (controller.pastOrders.isNotEmpty) ...[
              const _SectionHeader('Past'),
              ...controller.pastOrders
                  .map((o) => _OrderTile(order: o, showCountdown: false)),
            ],
          ],
        );
      }),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final OrderModel order;
  final bool showCountdown;

  const _OrderTile({required this.order, required this.showCountdown});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.white,
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            TheNetworkImage(
              url: order.imageUrl,
              width: 64,
              height: 64,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.dealName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  Text(order.storeName,
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.grey.shade600)),
                  const SizedBox(height: 6),
                  if (showCountdown)
                    PickupCountdown(pickupStart: order.pickupStart)
                  else
                    Text(order.status,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('฿${order.total.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('x${order.quantity}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
