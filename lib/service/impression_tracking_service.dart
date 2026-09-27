import 'dart:async';

import 'package:get/get.dart';

import '../util/log_service.dart';
import 'analytics_service.dart';
import 'fake_api_service.dart';

/// Records `deal_impression` events (F-2) and batches their delivery to
/// [FakeApiService.sendAnalyticsBatch].
///
/// Responsibilities kept deliberately separate from [AnalyticsService]:
///  - [AnalyticsService] is the in-memory sink the debug screen reads —
///    every impression is logged there immediately, one by one, so the
///    debug screen stays a real-time view of what happened.
///  - This service owns the *delivery* side: session-level "at most once
///    per deal" dedupe, and batching that delivery so we don't hit the
///    fake backend once per card. Those are two different concerns with
///    two different timing requirements, hence two data structures below.
class ImpressionTrackingService extends GetxService {
  static const _batchSize = 10;
  static const _batchWindow = Duration(seconds: 15);

  /// Deal ids already recorded this session, across every screen/source.
  /// A plain Set is enough — impression identity is per deal, not per
  /// (deal, source) or (deal, screen instance).
  final _seenDealIds = <int>{};

  final _pendingBatch = <Map<String, dynamic>>[];
  Timer? _batchTimer;

  /// Records an impression for [dealId] if (and only if) one hasn't already
  /// been recorded this session. Idempotent — safe to call every time a
  /// card crosses the visibility threshold; duplicates are dropped here so
  /// callers (widgets) don't need to coordinate with each other.
  void recordImpression({
    required int dealId,
    required String source,
    required int position,
  }) {
    if (!_seenDealIds.add(dealId)) {
      return; // already recorded this deal this session — no-op.
    }

    final properties = {
      'deal_id': dealId,
      'source': source,
      'position': position,
    };

    Get.find<AnalyticsService>().logEvent('deal_impression', properties);

    _pendingBatch.add({
      'name': 'deal_impression',
      'properties': properties,
      'at': DateTime.now().toIso8601String(),
    });

    // Start the 15s window on the *first* unsent event, not on every add —
    // otherwise a steady trickle of impressions would keep pushing the
    // flush out and the batch window requirement would never trigger.
    _batchTimer ??= Timer(_batchWindow, _flush);

    if (_pendingBatch.length >= _batchSize) {
      _flush();
    }
  }

  Future<void> _flush() async {
    _batchTimer?.cancel();
    _batchTimer = null;
    if (_pendingBatch.isEmpty) return;

    final batch = List<Map<String, dynamic>>.of(_pendingBatch);
    _pendingBatch.clear();

    try {
      await Get.find<FakeApiService>().sendAnalyticsBatch(batch);
    } catch (e) {
      // Delivery failure doesn't affect what's already visible on the
      // debug screen (that's driven by AnalyticsService, independently).
      // F-2's scope is batching/dedupe, not a retry/outbox strategy for a
      // simulated backend that has no real persistence to retry into.
      LogService.error('impression batch send failed', e);
    }
  }

  @override
  void onClose() {
    _batchTimer?.cancel();
    // Best-effort flush of whatever is left so a session-end doesn't
    // silently drop a partial batch during normal app teardown.
    unawaited(_flush());
    super.onClose();
  }
}
