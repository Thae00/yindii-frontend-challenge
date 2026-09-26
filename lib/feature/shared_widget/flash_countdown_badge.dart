import 'dart:async';

import 'package:flutter/material.dart';

/// A live "mm:ss" (or "h:mm:ss" once past an hour) countdown to [endsAt].
///
/// Ticks once a second, rebuilding only this small badge — never the card or
/// list item around it. That per-second-rebuild scoping is what keeps a feed
/// with 100+ of these smooth: each instance owns a single `Timer.periodic`
/// that is cancelled in [dispose] (see RES-102 for what happens if that's
/// forgotten).
///
/// When the countdown reaches zero, the badge switches to an "Expired"
/// label and calls [onExpired] exactly once, deferred to after the current
/// frame so it's safe to trigger state changes (like removing the deal from
/// the cart) from the callback.
class FlashCountdownBadge extends StatefulWidget {
  final DateTime endsAt;
  final VoidCallback? onExpired;
  final TextStyle? style;
  final EdgeInsetsGeometry padding;
  final Color activeColor;
  final Color expiredColor;

  const FlashCountdownBadge({
    super.key,
    required this.endsAt,
    this.onExpired,
    this.style,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    this.activeColor = const Color(0xFFD32F2F),
    this.expiredColor = const Color(0xFF9E9E9E),
  });

  @override
  State<FlashCountdownBadge> createState() => _FlashCountdownBadgeState();
}

class _FlashCountdownBadgeState extends State<FlashCountdownBadge> {
  Timer? _timer;
  late Duration _remaining = _computeRemaining();
  bool _expiredNotified = false;

  Duration _computeRemaining() {
    final d = widget.endsAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void initState() {
    super.initState();
    if (_remaining > Duration.zero) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _notifyExpiredOnce();
    }
  }

  void _tick() {
    if (!mounted) return;
    final remaining = _computeRemaining();
    setState(() => _remaining = remaining);
    if (remaining <= Duration.zero) {
      _timer?.cancel();
      _notifyExpiredOnce();
    }
  }

  void _notifyExpiredOnce() {
    if (_expiredNotified) return;
    _expiredNotified = true;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => widget.onExpired?.call());
  }

  String get _label {
    if (_remaining <= Duration.zero) return 'Expired';
    final hours = _remaining.inHours;
    final minutes = _remaining.inMinutes.remainder(60);
    final seconds = _remaining.inSeconds.remainder(60);
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expired = _remaining <= Duration.zero;
    return Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: (expired ? widget.expiredColor : widget.activeColor)
            .withValues(alpha: expired ? 0.15 : 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        expired ? 'Expired' : _label,
        style: widget.style?.copyWith(
              color: expired ? widget.expiredColor : widget.activeColor,
            ) ??
            TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: expired ? widget.expiredColor : widget.activeColor,
            ),
      ),
    );
  }
}
