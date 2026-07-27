import 'platform_clock.dart';

/// Fixed clock for deterministic tests.
class FixedPlatformClock implements PlatformClock {
  FixedPlatformClock({
    required this.fixedIso,
    required this.fixedMicroseconds,
  });

  final String fixedIso;
  final int fixedMicroseconds;

  @override
  String nowUtcIso() => fixedIso;

  @override
  int nowMicrosecondsSinceEpoch() => fixedMicroseconds;
}
