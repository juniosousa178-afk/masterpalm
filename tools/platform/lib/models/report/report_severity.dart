/// Severity for report findings.
enum ReportSeverity {
  info,
  low,
  medium,
  high,
  critical,
}

extension ReportSeverityX on ReportSeverity {
  String get wireName => name;

  static ReportSeverity fromWireName(String value) {
    return ReportSeverity.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown ReportSeverity: $value'),
    );
  }
}
