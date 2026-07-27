/// Date and time formatting helpers for platform snapshots and reports.
class DateHelpers {
  const DateHelpers();

  static DateTime utcNow() => DateTime.now().toUtc();

  static String toIso8601(DateTime value) => value.toUtc().toIso8601String();

  static DateTime? parseIso8601(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  static String fileSafeTimestamp([DateTime? value]) {
    final dt = (value ?? utcNow()).toUtc();
    return '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}_'
        '${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}
