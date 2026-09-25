import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../service/analytics_service.dart';
import '../../service/cart_service.dart';
import '../../util/log_service.dart';

class DealDetailsController extends GetxController {
  final DealRepo dealRepo;
  final CartService cartService;
  final AnalyticsService analytics;

  DealDetailsController({
    required this.dealRepo,
    required this.cartService,
    required this.analytics,
  });

  final _deal = Rxn<DealModel>();
  DealModel? get dealOrNull => _deal.value;
  final isLoading = true.obs;
  final loadFailed = false.obs;

  final _quantityLeft = RxnInt();
  int? get quantityLeft => _quantityLeft.value;

  Worker? _cartWorker;

  @override
  void onInit() {
    super.onInit();
    _loadDeal();
  }

  Future<void> _loadDeal() async {
    final arg = Get.arguments;
    if (arg is DealModel) {
      // Opened from within the app (home feed, flash rail, search) — the
      // full deal was already passed, no fetch needed.
      _deal.value = arg;
    } else {
      // Opened via deep link — only the id is available as a route param.
      final id = int.tryParse(Get.parameters['id'] ?? '');
      if (id == null) {
        loadFailed.value = true;
        isLoading.value = false;
        return;
      }
      try {
        _deal.value = await dealRepo.fetchById(id);
      } catch (e) {
        LogService.error('failed to load deal $id from deep link', e);
        loadFailed.value = true;
        isLoading.value = false;
        return;
      }
    }
    _quantityLeft.value = _deal.value!.quantityLeft;
    analytics.logEvent('deal_details_view', {
      'deal_id': _deal.value!.id,
      'source': Get.parameters['source'] ?? 'unknown',
    });
    // Whenever the cart changes, re-check this deal's remaining stock so the
    // details screen never shows stale availability.
    _cartWorker = ever(cartService.itemCount, (_) => _recheckAvailability());
    isLoading.value = false;
  }

  Future<void> _recheckAvailability() async {
    final deal = _deal.value;
    if (deal == null) return;
    LogService.log('re-checking availability for deal ${deal.id}');
    final fresh = await dealRepo.fetchById(deal.id);
    _quantityLeft.value = fresh.quantityLeft;
  }

  void addToCart() {
    final deal = _deal.value;
    if (deal == null) return;
    cartService.add(deal);
    Get.snackbar(
      'Added to bag',
      '${deal.name} — pick up ${deal.pickupWindow.label}',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void onClose() {
    _cartWorker?.dispose();
    super.onClose();
  }
}
