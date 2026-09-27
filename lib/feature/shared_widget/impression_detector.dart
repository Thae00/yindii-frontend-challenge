import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../service/impression_tracking_service.dart';

/// Wraps a deal card so a `deal_impression` event fires once the card has
/// been at least 50% visible for one continuous second.
///
/// This widget only owns the "has *this* card instance been sufficiently
/// visible for long enough" timer. Session-level dedupe ("at most once per
/// deal per session") and batching live in [ImpressionTrackingService] —
/// deliberately not duplicated here, since the same deal can appear in more
/// than one list (e.g. home feed + flash rail) and each needs its own
/// independent visibility timer, but only one of them should ever win.
class ImpressionDetector extends StatefulWidget {
  final int dealId;
  final String source;
  final int position;
  final Widget child;

  const ImpressionDetector({
    super.key,
    required this.dealId,
    required this.source,
    required this.position,
    required this.child,
  });

  @override
  State<ImpressionDetector> createState() => _ImpressionDetectorState();
}

class _ImpressionDetectorState extends State<ImpressionDetector> {
  Timer? _dwellTimer;
  bool _fired = false;

  void _onVisibilityChanged(VisibilityInfo info) {
    if (_fired) return; // already recorded — stop reacting to further scroll

    final isSufficientlyVisible = info.visibleFraction >= 0.5;
    if (isSufficientlyVisible) {
      // Start a fresh 1s dwell timer only if one isn't already running —
      // a card that stays >=50% visible across several VisibilityDetector
      // callbacks must not have its timer restarted each time.
      _dwellTimer ??= Timer(const Duration(seconds: 1), _fire);
    } else {
      // Dropped below 50% before the second was up: not a continuous
      // second, so cancel and require a fresh continuous second next time.
      _dwellTimer?.cancel();
      _dwellTimer = null;
    }
  }

  void _fire() {
    _dwellTimer = null;
    if (_fired || !mounted) return;
    _fired = true;
    Get.find<ImpressionTrackingService>().recordImpression(
      dealId: widget.dealId,
      source: widget.source,
      position: widget.position,
    );
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      // Unique per (source, deal, position) so distinct rails/lists showing
      // the same deal are tracked independently, as VisibilityDetector
      // requires globally-unique keys.
      key: Key('impression-${widget.source}-${widget.dealId}-${widget.position}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: widget.child,
    );
  }
}
