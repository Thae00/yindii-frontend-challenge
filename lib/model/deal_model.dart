import 'pickup_window_model.dart';

class DealModel {
  final int id;
  final String name;
  final String description;
  final String imageUrl;
  final num originalPrice;
  final num price;
  final String currencyCode;
  final int quantityLeft;
  final int storeId;
  final String storeName;
  final String storeAddress;
  final double lat;
  final double lng;
  final double? rating;
  final List<String> tags;
  final PickupWindowModel pickupWindow;
  final DateTime? flashSaleEndsAt;

  const DealModel({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.originalPrice,
    required this.price,
    required this.currencyCode,
    required this.quantityLeft,
    required this.storeId,
    required this.storeName,
    required this.storeAddress,
    required this.lat,
    required this.lng,
    required this.rating,
    required this.tags,
    required this.pickupWindow,
    required this.flashSaleEndsAt,
  });

  factory DealModel.fromJson(Map<String, dynamic> json) {
    return DealModel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      originalPrice: json['originalPrice'] as num? ?? 0,
      price: json['price'] as num? ?? 0,
      currencyCode: json['currencyCode'] as String? ?? 'THB',
      quantityLeft: json['quantityLeft'] as int? ?? 0,
      storeId: json['storeId'] as int? ?? 0,
      storeName: json['storeName'] as String? ?? '',
      storeAddress: json['storeAddress'] as String? ?? '',
      lat: (json['lat'] as num? ?? 0).toDouble(),
      lng: (json['lng'] as num? ?? 0).toDouble(),
      rating: (json['rating'] as num?)?.toDouble(),
      tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
      pickupWindow: PickupWindowModel.fromJson(
          json['pickupWindow'] as Map<String, dynamic>? ?? {}),
      flashSaleEndsAt: json['flashSaleEndsAt'] == null
          ? null
          : DateTime.parse(json['flashSaleEndsAt'] as String),
    );
  }

  bool get isFlashSale => flashSaleEndsAt != null;

  int get discountPercent =>
      originalPrice <= 0 ? 0 : (100 - (price / originalPrice * 100)).round();
}
