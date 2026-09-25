import 'package:intl/intl.dart';

/// A store's pickup window. The API sends instants as ISO-8601 UTC strings.
class PickupWindowModel {
  final DateTime start;
  final DateTime end;

  const PickupWindowModel({required this.start, required this.end});

  factory PickupWindowModel.fromJson(Map<String, dynamic> json) {
    return PickupWindowModel(
      start: DateTime.parse(json['start'] as String? ?? ''),
      end: DateTime.parse(json['end'] as String? ?? ''),
    );
  }

  /// Human readable label, e.g. "17:30 – 21:00" — in the device's local time.
  String get label =>
      '${DateFormat('HH:mm').format(start.toLocal())} – ${DateFormat('HH:mm').format(end.toLocal())}';

  /// Whether pickup starts today, in the device's local calendar day.
  bool get isToday {
    final localStart = start.toLocal();
    final now = DateTime.now();
    return localStart.year == now.year &&
        localStart.month == now.month &&
        localStart.day == now.day;
  }

  /// Whether the store is currently accepting pickups.
  bool get isOpenNow {
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(end);
  }

  Duration get untilStart => start.difference(DateTime.now());
}
