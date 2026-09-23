import 'package:get/get.dart';

import '../feature/order/orders_controller.dart';

class OrdersBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => OrdersController(orderRepo: Get.find()));
  }
}
