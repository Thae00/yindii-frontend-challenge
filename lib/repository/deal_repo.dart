import 'package:get/get.dart';

import '../model/deal_model.dart';
import '../model/paged_response_model.dart';
import '../service/fake_api_service.dart';

class DealRepo extends GetxService {
  final FakeApiService api;

  DealRepo({required this.api});

  Future<PagedResponseModel<DealModel>> fetchDeals({int page = 1}) async {
    final json = await api.getDeals(page: page);
    return PagedResponseModel.fromJson(json, DealModel.fromJson);
  }

  Future<List<DealModel>> fetchFlashDeals() async {
    final json = await api.getFlashDeals();
    return json.map(DealModel.fromJson).toList();
  }

  Future<DealModel> fetchById(int id) async {
    final json = await api.getDealById(id);
    return DealModel.fromJson(json);
  }

  Future<List<DealModel>> search(String query) async {
    final json = await api.searchDeals(query);
    return json.map(DealModel.fromJson).toList();
  }
}
