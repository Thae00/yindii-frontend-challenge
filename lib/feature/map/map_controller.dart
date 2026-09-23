import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../../model/store_model.dart';
import '../../repository/store_repo.dart';
import '../../util/log_service.dart';

class StoresMapController extends GetxController {
  final StoreRepo storeRepo;

  StoresMapController({required this.storeRepo});

  final stores = <StoreModel>[].obs;
  final isLoading = true.obs;

  /// Bangkok city center.
  static final initialCenter = LatLng(13.7563, 100.5018);

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  Future<void> _load() async {
    isLoading.value = true;
    try {
      stores.assignAll(await storeRepo.fetchStores());
    } catch (e) {
      LogService.error('load stores failed', e);
    }
    isLoading.value = false;
  }
}
