import 'deal_model.dart';
import 'reservation_model.dart';

class CartItemModel {
  final DealModel deal;
  int quantity;

  /// Stock hold for this line item, obtained via
  /// `FakeApiService.reserveDeal`. Null while a reservation is still being
  /// requested (see [isReserving]) or if one was never successfully made.
  ReservationModel? reservation;

  /// True while a reservation request for this line's current quantity is
  /// in flight — set the instant the line is optimistically added/changed,
  /// cleared once the backend call resolves (success or failure). The UI
  /// uses this to show a "holding your item…" state and to disable
  /// quantity controls / checkout while a hold is still being confirmed,
  /// so a second request can't race the first for the same line.
  bool isReserving;

  CartItemModel({
    required this.deal,
    this.quantity = 1,
    this.reservation,
    this.isReserving = false,
  });

  num get lineTotal => deal.price * quantity;

  /// The moment this line stops being valid: whichever comes first of the
  /// 5-minute stock hold running out and the flash sale ending. Null only
  /// when there is nothing to count down to (no hold yet, not a flash deal).
  DateTime? get effectiveDeadline {
    final hold = reservation?.expiresAt;
    final flash = deal.flashSaleEndsAt;
    if (hold == null) return flash;
    if (flash == null) return hold;
    return hold.isBefore(flash) ? hold : flash;
  }

  /// True when the flash sale (not the stock hold) is what ends this line
  /// first. Drives the bag label ("Flash sale ends in" vs "Held for").
  bool get endsByFlashSale {
    final flash = deal.flashSaleEndsAt;
    if (flash == null) return false;
    final hold = reservation?.expiresAt;
    return hold == null || !hold.isBefore(flash);
  }
}
