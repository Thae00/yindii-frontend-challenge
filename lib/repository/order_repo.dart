import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/order_model.dart';
import '../model/reservation_model.dart';
import '../service/fake_api_service.dart';

class OrderRepo extends GetxService {
  final FakeApiService api;

  OrderRepo({required this.api});

  Future<List<OrderModel>> fetchOrders() async {
    final json = await api.getOrders();
    return json.map(OrderModel.fromJson).toList();
  }

  Future<OrderModel> checkout(List<CartItemModel> items) async {
    final json = await api.checkout([
      for (final item in items)
        {
          'dealId': item.deal.id,
          'quantity': item.quantity,
          'reservationId': item.reservation?.id,
        }
    ]);
    return OrderModel.fromJson(json);
  }

  Future<ReservationModel> reserve(int dealId, {int quantity = 1}) async {
    final json = await api.reserveDeal(dealId, quantity: quantity);
    return ReservationModel.fromJson(json);
  }

  Future<void> releaseReservation(String reservationId) =>
      api.releaseReservation(reservationId);
}
