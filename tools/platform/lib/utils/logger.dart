/// Lightweight structured logger for platform tools.
class PlatformLogger {
  PlatformLogger({this.prefix = 'platform', this.enabled = true});

  final String prefix;
  final bool enabled;

  void debug(String message) => _log('DEBUG', message);

  void info(String message) => _log('INFO', message);

  void warn(String message) => _log('WARN', message);

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log('ERROR', message);
    if (error != null) {
      // ignore: avoid_print
      print('[$prefix] cause: $error');
    }
    if (stackTrace != null) {
      // ignore: avoid_print
      print(stackTrace);
    }
  }

  void _log(String level, String message) {
    if (!enabled) return;
    // ignore: avoid_print
    print('[$prefix][$level] $message');
  }
}
