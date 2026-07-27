/// Prevents recursive telemetry instrumentation.
class TelemetrySuppressionScope {
  TelemetrySuppressionScope._();

  static int _depth = 0;

  static bool get isSuppressed => _depth > 0;

  static T runSuppressed<T>(T Function() action) {
    _depth++;
    try {
      return action();
    } finally {
      _depth--;
    }
  }

  static Future<T> runSuppressedAsync<T>(Future<T> Function() action) async {
    _depth++;
    try {
      return await action();
    } finally {
      _depth--;
    }
  }
}
