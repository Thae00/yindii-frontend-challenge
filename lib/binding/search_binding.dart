import 'package:get/get.dart';

import '../feature/search/search_deals_controller.dart';

class SearchBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => SearchDealsController(dealRepo: Get.find()));
  }
}
