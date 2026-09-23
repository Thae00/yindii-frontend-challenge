import 'package:get/get.dart';

import '../model/store_model.dart';
import '../service/fake_api_service.dart';

class StoreRepo extends GetxService {
  final FakeApiService api;

  StoreRepo({required this.api});

  Future<List<StoreModel>> fetchStores() async {
    final json = await api.getStores();
    return json.map(StoreModel.fromJson).toList();
  }
}
