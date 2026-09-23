import 'pickup_window_model.dart';

class StoreModel {
  final int id;
  final String name;
  final String category;
  final String address;
  final double lat;
  final double lng;
  final String currencyCode;
  final String imageUrl;
  final double? rating;
  final PickupWindowModel pickupWindow;

  const StoreModel({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.lat,
    required this.lng,
    required this.currencyCode,
    required this.imageUrl,
    required this.rating,
    required this.pickupWindow,
  });

  factory StoreModel.fromJson(Map<String, dynamic> json) {
    return StoreModel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      address: json['address'] as String? ?? '',
      lat: (json['lat'] as num? ?? 0).toDouble(),
      lng: (json['lng'] as num? ?? 0).toDouble(),
      currencyCode: json['currencyCode'] as String? ?? 'THB',
      imageUrl: json['imageUrl'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble(),
      pickupWindow: PickupWindowModel.fromJson(
          json['pickupWindow'] as Map<String, dynamic>? ?? {}),
    );
  }
}
