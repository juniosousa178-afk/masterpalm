/// Status of report generation.
enum ReportStatus {
  success,
  warning,
  error,
}

extension ReportStatusX on ReportStatus {
  String get wireName => name;

  static ReportStatus fromWireName(String value) {
    return ReportStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown ReportStatus: $value'),
    );
  }
}
