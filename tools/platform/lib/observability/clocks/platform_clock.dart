/// Platform clock abstraction for deterministic time.
abstract class PlatformClock {
  String nowUtcIso();
  int nowMicrosecondsSinceEpoch();
}
