import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app_config.dart';
import '../../model/cart_item_model.dart';
import '../../service/cart_service.dart';
import '../shared_widget/flash_countdown_badge.dart';
import '../shared_widget/the_network_image.dart';
import 'cart_controller.dart';

class CartScreen extends GetView<CartController> {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = controller.cartService;
    return Scaffold(
      appBar: AppBar(title: const Text('My bag')),
      body: Obx(() {
        if (cart.items.isEmpty) {
          return const Center(child: Text('Your bag is empty'));
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: cart.items.length,
          itemBuilder: (context, index) {
            final item = cart.items[index];
            return Card(
              // Keyed by deal id (not index) so a line's countdown/holding
              // state stays attached to the right item when another line
              // above it is removed and the list shifts.
              key: ValueKey('cart-line-${item.deal.id}'),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.white,
              elevation: 0.5,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TheNetworkImage(
                      url: item.deal.imageUrl,
                      width: 64,
                      height: 64,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.deal.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600)),
                          Text(item.deal.storeName,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.grey.shade600)),
                          Text('฿${item.deal.price.toStringAsFixed(0)} each',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppConfig.primaryGreen,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          _ReservationStatus(item: item),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: item.isReserving
                              ? null
                              : () => cart.decrement(item.deal.id),
                        ),
                        Text('${item.quantity}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: item.isReserving
                              ? null
                              : () => cart.add(item.deal),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }),
      bottomNavigationBar: Obx(() {
        if (cart.items.isEmpty) return const SizedBox.shrink();
        final pending = controller.hasPendingReservations;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pending)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Confirming stock for your bag…',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey),
                  ),
                ),
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Total', style: TextStyle(fontSize: 13)),
                      Text('฿${cart.total.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: FilledButton(
                      onPressed: controller.isCheckingOut.value || pending
                          ? null
                          : controller.checkout,
                      child: controller.isCheckingOut.value
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Checkout'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// Small status row under a cart line: a "holding…" spinner while the
/// reservation request is in flight, or a live countdown to the line's
/// deadline (5-minute hold or flash-sale end, whichever is first) once it's
/// confirmed.
class _ReservationStatus extends StatelessWidget {
  final CartItemModel item;

  const _ReservationStatus({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.isReserving) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          SizedBox(width: 6),
          Text('Holding your item…',
              style: TextStyle(fontSize: 11.5, color: Colors.grey)),
        ],
      );
    }
    final reservation = item.reservation;
    if (reservation == null) {
      // Shouldn't normally be reachable — a failed reservation removes the
      // line entirely — but shown plainly rather than silently, in case a
      // future change introduces a state that lands here.
      return const Text('No hold on this item',
          style: TextStyle(fontSize: 11.5, color: Colors.orange));
    }
    // Count down to whichever ends this line first: the 5-minute stock hold
    // or the flash sale. Labelling it honestly matters — a "Held for 04:57"
    // on a sale that ends in 2 minutes would be a lie.
    final deadline = item.effectiveDeadline ?? reservation.expiresAt;
    final byFlash = item.endsByFlashSale;
    final color = byFlash ? const Color(0xFFD32F2F) : AppConfig.primaryGreen;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(byFlash ? Icons.flash_on : Icons.timer_outlined,
            size: 13, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(byFlash ? 'Flash sale ends in ' : 'Held for ',
            style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
        FlashCountdownBadge(
          // New key when the deadline changes so the badge restarts its
          // timer instead of keeping the old remaining time.
          key: ValueKey('cart-deadline-${item.deal.id}-'
              '${deadline.millisecondsSinceEpoch}'),
          endsAt: deadline,
          onExpired: () =>
              Get.find<CartService>().handleLineExpired(item.deal.id),
          activeColor: color,
          padding: EdgeInsets.zero,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}
