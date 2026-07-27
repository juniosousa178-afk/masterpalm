import '../../utils/date_helpers.dart';
import 'platform_clock.dart';

/// System clock implementation (outside engines).
class SystemPlatformClock implements PlatformClock {
  const SystemPlatformClock();

  @override
  String nowUtcIso() => DateHelpers.toIso8601(DateHelpers.utcNow());

  @override
  int nowMicrosecondsSinceEpoch() =>
      DateHelpers.utcNow().microsecondsSinceEpoch;
}
