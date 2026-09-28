import 'dart:async';

import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/deal_model.dart';
import '../model/reservation_model.dart';
import '../repository/order_repo.dart';
import '../util/log_service.dart';
import 'api_exception.dart';

/// App-wide cart. Lives for the whole session.
///
/// Every line is backed by a 5-minute stock reservation on the backend
/// (`FakeApiService.reserveDeal` / `releaseReservation`). The UI updates
/// optimistically — a line appears/changes instantly — and this service
/// reconciles that with the backend afterward:
///  - if the reservation request fails (stock contention, 409), the line
///    is rolled back out of the cart with a plain-language notice.
///  - if a line's deadline arrives while it's still sitting in the bag,
///    [handleLineExpired] removes it. The deadline is the earlier of the
///    5-minute hold and the flash-sale end (see solutions.md for why
///    "auto-remove, don't silently keep a dead hold" was the chosen
///    behaviour, mirroring F-1's flash-sale-expiry pattern).
///
/// `OrderRepo` is looked up lazily (a getter, not a constructor dependency)
/// because this service is `Get.put` very early in `main()`, before
/// `OrderRepo` is registered — by the time any cart action actually runs,
/// GetX's `fenix: true` lazy registration guarantees it exists.
class CartService extends GetxService {
  final items = <CartItemModel>[].obs;
  final itemCount = 0.obs;

  /// Per-deal-id "which reservation attempt is the current one" token.
  /// Bumped on every add/quantity-change/removal for that line so that if
  /// an older in-flight `reserveDeal` call resolves after a newer one has
  /// already superseded it (rapid +/- taps, or the line being removed
  /// entirely while a reserve was in flight), the stale result is
  /// recognised and discarded — the same epoch-guard shape as RES-104's
  /// refresh/loadMore race, applied here to reserve/release races.
  final _lineOpToken = <int, int>{};

  /// One session-level timer per bag line, aimed at that line's
  /// [CartItemModel.effectiveDeadline] (stock hold OR flash-sale end,
  /// whichever is first). It lives here, not in a widget, so a flash sale
  /// that ends while the user is on another screen — or while the bag
  /// screen is showing a *hold* countdown that is longer than the sale —
  /// still removes the line on time.
  final _deadlineTimers = <int, Timer>{};

  OrderRepo get _orderRepo => Get.find<OrderRepo>();

  void add(DealModel deal) {
    if (deal.isFlashExpired) {
      LogService.log('cart: flash sale ended for deal ${deal.id}, not adding');
      return;
    }
    final existing = items.firstWhereOrNull((i) => i.deal.id == deal.id);
    if (existing != null) {
      if (existing.quantity >= deal.quantityLeft) {
        LogService.log('cart: cannot add more of deal ${deal.id}');
        return;
      }
      existing.quantity++;
      items.refresh();
      _recount();
      unawaited(_reconcileLine(existing));
    } else {
      final item = CartItemModel(deal: deal);
      items.add(item);
      _recount();
      // Flash deals have a deadline before the reservation even comes back.
      _scheduleDeadline(item);
      unawaited(_reconcileLine(item));
    }
  }

  void decrement(int dealId) {
    final existing = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (existing == null) return;
    existing.quantity--;
    if (existing.quantity <= 0) {
      _removeLine(existing, releaseHold: true);
    } else {
      items.refresh();
      _recount();
      unawaited(_reconcileLine(existing));
    }
  }

  void remove(int dealId) {
    final existing = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (existing != null) _removeLine(existing, releaseHold: true);
  }

  /// Called after a successful checkout. The reservations backing these
  /// lines were just consumed by the order (the backend decremented real
  /// stock for them), so — unlike [clear] — this must NOT release them;
  /// releasing a just-spent hold would be asking the backend to give stock
  /// back that was already sold.
  void clearAfterCheckout() {
    items.clear();
    _lineOpToken.clear();
    _cancelAllDeadlines();
    _recount();
  }

  /// Abandons the cart, releasing every line's held reservation. Not
  /// currently wired to a UI action, but kept distinct from
  /// [clearAfterCheckout] so a future "empty my bag" button can't
  /// accidentally reuse the checkout path and skip releasing holds.
  void clear() {
    for (final item in items) {
      unawaited(_releaseQuietly(item.reservation));
    }
    items.clear();
    _lineOpToken.clear();
    _cancelAllDeadlines();
    _recount();
  }

  /// Called after a checkout attempt comes back `410` (a reservation
  /// expired mid-checkout). The response doesn't say *which* line — the
  /// fake backend throws on the first expired reservation it finds — so
  /// this re-checks every line's own `expiresAt` locally
  /// (`ReservationModel.isExpired`) and drops whichever ones have actually
  /// timed out, leaving everything still valid in the bag for a retry.
  void pruneExpiredReservations() {
    final expiredDealIds = items
        .where((i) => i.reservation?.isExpired ?? false)
        .map((i) => i.deal.id)
        .toList();
    for (final dealId in expiredDealIds) {
      final item = items.firstWhereOrNull((i) => i.deal.id == dealId);
      // Already expired server-side — nothing left to release.
      if (item != null) _removeLine(item, releaseHold: false);
    }
  }

  /// Removes every line whose flash sale has already ended and returns the
  /// removed lines. Called right before checkout: the backend only validates
  /// reservation ids, never `flashSaleEndsAt`, so without this guard a line
  /// whose sale ended (but whose 5-minute hold is still valid) could be
  /// bought at the flash price. The still-valid holds are released.
  List<CartItemModel> pruneFlashExpired() {
    final expired = items.where((i) => i.deal.isFlashExpired).toList();
    for (final item in expired) {
      _removeLine(item, releaseHold: true);
    }
    return expired;
  }

  /// A line reached its [CartItemModel.effectiveDeadline]. Called both by
  /// the line's own session timer and by the bag row's countdown badge;
  /// whichever fires first removes the line and the other becomes a no-op
  /// (the line is already gone), so the user only sees one notice.
  ///
  /// Two different reasons, two different behaviours:
  ///  - flash sale ended: the stock hold may still be valid on the server,
  ///    so it is released (frees the stock straight away).
  ///  - hold ran out: already expired server-side, nothing to release.
  void handleLineExpired(int dealId) {
    final item = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (item == null) return;

    if (item.deal.isFlashExpired) {
      // Checked before `isReserving` on purpose: a flash sale that ends
      // while the hold is still being confirmed must not wait for it.
      // `_removeLine` bumps the op token, so if the reserve call comes back
      // later it is recognised as orphaned and released.
      _removeLine(item, releaseHold: true);
      Get.snackbar(
        'Removed from bag',
        '${item.deal.name} is no longer available — the flash sale ended.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    // While a re-reserve is in flight `item.reservation` is the old, already
    // released hold. Ignore its deadline; `_reconcileLine` reschedules with
    // the new hold when it lands.
    if (item.isReserving) return;

    if (item.reservation?.isExpired ?? false) {
      _removeLine(item, releaseHold: false); // already expired server-side
      Get.snackbar(
        'Hold expired',
        "${item.deal.name}'s 5-minute hold ran out, so it was removed from "
            "your bag. Add it again if it's still available.",
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    // Fired a hair early (clock granularity): aim again at the real deadline.
    _scheduleDeadline(item);
  }

  num get total => items.fold(0, (sum, i) => sum + i.lineTotal);

  void _recount() {
    itemCount.value = items.fold(0, (sum, i) => sum + i.quantity);
  }

  void _removeLine(CartItemModel item, {required bool releaseHold}) {
    final dealId = item.deal.id;
    // Invalidate any in-flight reservation attempt for this line so its
    // result (when it eventually resolves) is recognised as stale.
    _lineOpToken[dealId] = (_lineOpToken[dealId] ?? 0) + 1;
    _cancelDeadline(dealId);
    items.removeWhere((i) => i.deal.id == dealId);
    _recount();
    if (releaseHold && item.reservation != null) {
      unawaited(_releaseQuietly(item.reservation));
    }
  }

  /// Reserves (or re-reserves, on a quantity change) stock for [item]'s
  /// *current* quantity. The optimistic UI update has already happened by
  /// the time this runs — this only reconciles the backend hold to match,
  /// and rolls the whole line back out of the cart if the backend rejects
  /// it (stock contention).
  Future<void> _reconcileLine(CartItemModel item) async {
    final dealId = item.deal.id;
    final myToken = (_lineOpToken[dealId] ?? 0) + 1;
    _lineOpToken[dealId] = myToken;

    final previousReservation = item.reservation;
    item.isReserving = true;
    items.refresh();

    // Release the previous hold (if any) in the background. Its own
    // success/failure doesn't affect this line — worst case a stale
    // reservation simply expires server-side after 5 minutes.
    if (previousReservation != null) {
      unawaited(_releaseQuietly(previousReservation));
    }

    ReservationModel reservation;
    try {
      reservation = await _orderRepo.reserve(dealId, quantity: item.quantity);
    } on ApiException catch (e) {
      if (_lineOpToken[dealId] != myToken) return; // superseded — ignore
      LogService.error('reservation failed for deal $dealId', e);
      final wasStillPresent = items.contains(item);
      _cancelDeadline(dealId);
      items.removeWhere((i) => i.deal.id == dealId);
      _recount();
      if (wasStillPresent) {
        Get.snackbar(
          "Couldn't hold this item",
          '${item.deal.name} just sold out — sorry! It has been removed '
              'from your bag.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
      return;
    }

    if (_lineOpToken[dealId] != myToken || !items.contains(item)) {
      // A newer attempt (or a removal) has already superseded this one by
      // the time the reservation came back — this reservation is now
      // orphaned from the cart's point of view, so give the stock back
      // rather than holding it uselessly for 5 minutes.
      unawaited(_releaseQuietly(reservation));
      return;
    }
    item.reservation = reservation;
    item.isReserving = false;
    items.refresh();
    // The deadline may now be the (shorter) hold, or still the flash end.
    _scheduleDeadline(item);
  }

  void _scheduleDeadline(CartItemModel item) {
    final dealId = item.deal.id;
    _cancelDeadline(dealId);
    final deadline = item.effectiveDeadline;
    if (deadline == null) return;
    var delay = deadline.difference(DateTime.now());
    if (delay.isNegative) delay = Duration.zero;
    _deadlineTimers[dealId] = Timer(delay, () {
      _deadlineTimers.remove(dealId);
      handleLineExpired(dealId);
    });
  }

  void _cancelDeadline(int dealId) => _deadlineTimers.remove(dealId)?.cancel();

  void _cancelAllDeadlines() {
    for (final t in _deadlineTimers.values) {
      t.cancel();
    }
    _deadlineTimers.clear();
  }

  @override
  void onClose() {
    _cancelAllDeadlines();
    super.onClose();
  }

  Future<void> _releaseQuietly(ReservationModel? reservation) async {
    if (reservation == null) return;
    try {
      await _orderRepo.releaseReservation(reservation.id);
    } catch (e) {
      // Best-effort: if this call itself fails, the hold simply expires
      // server-side after 5 minutes on its own — no user-facing
      // consequence worth surfacing for a release that was already
      // invisible to the user (it's freeing stock, not taking it).
      LogService.error('failed to release reservation ${reservation.id}', e);
    }
  }
}