import 'package:get/get.dart';

import '../feature/map/map_controller.dart';

class MapBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => StoresMapController(storeRepo: Get.find()));
  }
}
