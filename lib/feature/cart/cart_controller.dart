import 'package:get/get.dart';

import '../../repository/order_repo.dart';
import '../../service/api_exception.dart';
import '../../service/cart_service.dart';
import '../../util/log_service.dart';

class CartController extends GetxController {
  final CartService cartService;
  final OrderRepo orderRepo;

  CartController({required this.cartService, required this.orderRepo});

  final isCheckingOut = false.obs;

  /// True while any line is still waiting on its reservation to confirm.
  /// Checking out with a line in this state would send a null
  /// `reservationId` for it — the fake backend only validates reservation
  /// ids it's given, so an unconfirmed line would silently checkout
  /// without ever actually holding stock. The UI disables the checkout
  /// button while this is true rather than handling that gap server-side
  /// (which is off-limits — see PROBLEM.md).
  bool get hasPendingReservations =>
      cartService.items.any((i) => i.isReserving);

  Future<void> checkout() async {
    if (cartService.items.isEmpty ||
        isCheckingOut.value ||
        hasPendingReservations) {
      return;
    }
    // Flash sales can end while the hold is still valid, and the backend
    // never checks that. Drop ended ones here and make the user re-confirm
    // the bag (the total just changed) instead of silently charging them
    // the flash price.
    final endedFlash = cartService.pruneFlashExpired();
    if (endedFlash.isNotEmpty) {
      Get.snackbar(
        'Flash sale ended',
        endedFlash.length == 1
            ? '${endedFlash.first.deal.name} was removed from your bag. '
                'Please review your bag and check out again.'
            : '${endedFlash.length} items were removed from your bag. '
                'Please review your bag and check out again.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    isCheckingOut.value = true;
    try {
      final order = await orderRepo.checkout(cartService.items.toList());
      cartService.clearAfterCheckout();
      Get.snackbar(
        'Order confirmed',
        'Order #${order.id} — pick up soon!',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on ApiException catch (e) {
      LogService.error('checkout failed', e);
      if (e.statusCode == 410) {
        // A reservation expired somewhere between the user opening
        // checkout and this request landing. The response doesn't say
        // which line — CartService re-checks each line's own expiresAt
        // and drops whatever actually timed out, leaving the rest ready
        // for an immediate retry.
        cartService.pruneExpiredReservations();
        Get.snackbar(
          'Some holds expired',
          "A couple of items' 5-minute holds ran out while you were "
              'checking out. We removed them — please review your bag and '
              'try again.',
          snackPosition: SnackPosition.BOTTOM,
        );
      } else {
        Get.snackbar(
          'Checkout failed',
          e.message,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
    isCheckingOut.value = false;
  }
}
