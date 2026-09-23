class OrderModel {
  final int id;
  final int dealId;
  final String dealName;
  final String storeName;
  final String imageUrl;
  final String status;
  final int quantity;
  final num total;
  final String currencyCode;
  final DateTime pickupStart;
  final DateTime pickupEnd;

  const OrderModel({
    required this.id,
    required this.dealId,
    required this.dealName,
    required this.storeName,
    required this.imageUrl,
    required this.status,
    required this.quantity,
    required this.total,
    required this.currencyCode,
    required this.pickupStart,
    required this.pickupEnd,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id: json['id'] as int? ?? 0,
      dealId: json['dealId'] as int? ?? 0,
      dealName: json['dealName'] as String? ?? '',
      storeName: json['storeName'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      status: json['status'] as String? ?? 'UNKNOWN',
      quantity: json['quantity'] as int? ?? 1,
      total: json['total'] as num? ?? 0,
      currencyCode: json['currencyCode'] as String? ?? 'THB',
      pickupStart: DateTime.parse(json['pickupStart'] as String? ?? ''),
      pickupEnd: DateTime.parse(json['pickupEnd'] as String? ?? ''),
    );
  }

  bool get isActive => status == 'CONFIRMED' || status == 'READY';
}
