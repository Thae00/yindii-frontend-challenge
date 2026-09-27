import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app_config.dart';
import '../../../model/deal_model.dart';
import '../../../routes/routes.dart';
import '../../../service/cart_service.dart';
import '../../shared_widget/flash_countdown_badge.dart';
import '../../shared_widget/impression_detector.dart';
import '../../shared_widget/the_network_image.dart';

/// Horizontal flash-sale rail with a live per-deal countdown.
class FlashDealsSection extends StatelessWidget {
  final List<DealModel> deals;

  const FlashDealsSection({super.key, required this.deals});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.bolt, color: Colors.red, size: 20),
              SizedBox(width: 4),
              Text('Flash sales',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: deals.length,
            itemBuilder: (context, index) =>
                _FlashRailCard(deal: deals[index], position: index),
          ),
        ),
      ],
    );
  }
}

class _FlashRailCard extends StatefulWidget {
  final DealModel deal;
  final int position;

  const _FlashRailCard({required this.deal, required this.position});

  @override
  State<_FlashRailCard> createState() => _FlashRailCardState();
}

class _FlashRailCardState extends State<_FlashRailCard> {
  late bool _expired = widget.deal.flashSaleEndsAt != null &&
      !widget.deal.flashSaleEndsAt!.isAfter(DateTime.now());

  void _handleExpired() {
    if (_expired || !mounted) return;
    setState(() => _expired = true);
    final cart = Get.find<CartService>();
    final wasInCart = cart.items.any((i) => i.deal.id == widget.deal.id);
    if (wasInCart) {
      cart.remove(widget.deal.id);
      Get.snackbar(
        'Removed from bag',
        '${widget.deal.name} is no longer available — the flash sale ended.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final deal = widget.deal;
    return ImpressionDetector(
      dealId: deal.id,
      source: 'flash_rail',
      position: widget.position,
      child: SizedBox(
      width: 200,
      child: Card(
        color: Colors.white,
        elevation: 0.5,
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: _expired
              ? null
              : () => Get.toNamed(
                    Routes.dealRoute(deal.id, source: 'flash_rail'),
                    arguments: deal,
                  ),
          child: Opacity(
            opacity: _expired ? 0.5 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TheNetworkImage(
                    url: deal.imageUrl, height: 90, width: double.infinity),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(deal.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(deal.storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.grey.shade600)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text('฿${deal.price.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppConfig.primaryGreen)),
                          const Spacer(),
                          if (deal.flashSaleEndsAt != null)
                            FlashCountdownBadge(
                              endsAt: deal.flashSaleEndsAt!,
                              onExpired: _handleExpired,
                              activeColor: Colors.red.shade700,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
