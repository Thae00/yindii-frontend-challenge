import 'package:get/get.dart';

import '../feature/cart/cart_controller.dart';

class CartBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => CartController(
          cartService: Get.find(),
          orderRepo: Get.find(),
        ));
  }
}
