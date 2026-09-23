import 'package:get/get.dart';

import '../feature/deal/deal_details_controller.dart';

class DealDetailsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DealDetailsController(
          dealRepo: Get.find(),
          cartService: Get.find(),
          analytics: Get.find(),
        ));
  }
}
