/// Monotonic timer abstraction for telemetry durations.
abstract class TelemetryTimer {
  void start();
  int elapsedMicroseconds();
}

class MonotonicTelemetryTimer implements TelemetryTimer {
  MonotonicTelemetryTimer({required this.startMicroseconds});

  final int startMicroseconds;
  int? _endMicroseconds;

  @override
  void start() {}

  void stop(int endMicroseconds) {
    _endMicroseconds = endMicroseconds;
  }

  @override
  int elapsedMicroseconds() {
    final end = _endMicroseconds ?? startMicroseconds;
    return end - startMicroseconds;
  }
}

abstract class TelemetryTimerFactory {
  MonotonicTelemetryTimer create({required int startMicroseconds});
}

class DefaultTelemetryTimerFactory implements TelemetryTimerFactory {
  const DefaultTelemetryTimerFactory();

  @override
  MonotonicTelemetryTimer create({required int startMicroseconds}) {
    return MonotonicTelemetryTimer(startMicroseconds: startMicroseconds);
  }
}
