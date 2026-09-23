/// A short-lived hold on a deal's stock. Reservations expire server-side at
/// [expiresAt]; an expired reservation id is rejected at checkout.
class ReservationModel {
  final String id;
  final int dealId;
  final int quantity;
  final DateTime expiresAt;

  const ReservationModel({
    required this.id,
    required this.dealId,
    required this.quantity,
    required this.expiresAt,
  });

  factory ReservationModel.fromJson(Map<String, dynamic> json) {
    return ReservationModel(
      id: json['id'] as String? ?? '',
      dealId: json['dealId'] as int? ?? 0,
      quantity: json['quantity'] as int? ?? 1,
      expiresAt: DateTime.parse(json['expiresAt'] as String? ?? ''),
    );
  }

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);
}
