import 'package:flutter/foundation.dart';

/// Lightweight console logger. Watch this output while using the app — it is
/// your main observability tool (network calls, analytics, errors).
class LogService {
  LogService._();

  static void log(String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    debugPrint('[rescu $ts] $message');
  }

  static void error(String message, [Object? error]) {
    log('ERROR: $message${error == null ? '' : ' | $error'}');
  }
}
