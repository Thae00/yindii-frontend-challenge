import 'dart:async';

import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../util/log_service.dart';

class SearchDealsController extends GetxController {
  final DealRepo dealRepo;

  SearchDealsController({required this.dealRepo});

  final results = <DealModel>[].obs;
  final isLoading = false.obs;
  final hasSearched = false.obs;

  Timer? _debounce;
  // Bumped on every new query. A request only applies its results if it is
  // still the most recent request in flight when it resolves — this is what
  // actually fixes the race (debounce alone only reduces how often it fires).
  int _requestId = 0;

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }

  void onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    final currentRequestId = ++_requestId;

    if (trimmed.isEmpty) {
      results.clear();
      hasSearched.value = false;
      isLoading.value = false; // add: a stale in-flight request no longer resets this
      return;
    }

    isLoading.value = true;
    hasSearched.value = true;
    try {
      final found = await dealRepo.search(trimmed);
      // Discard if a newer query has been issued while this was in flight.
      if (currentRequestId != _requestId) return;
      results.assignAll(found);
    } catch (e) {
      if (currentRequestId != _requestId) return;
      LogService.error('search failed', e);
    } finally {
      if (currentRequestId == _requestId) {
        isLoading.value = false;
      }
    }
  }
}