/// Output format for report rendering.
enum ReportFormat {
  markdown,
  json,
  html,
}

extension ReportFormatX on ReportFormat {
  String get wireName => name;

  static ReportFormat fromWireName(String value) {
    return ReportFormat.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown ReportFormat: $value'),
    );
  }
}
