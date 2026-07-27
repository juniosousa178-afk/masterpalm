import 'report_severity.dart';

/// Structured finding in a report.
class ReportFinding {
  const ReportFinding({
    required this.code,
    required this.message,
    required this.severity,
    this.source,
    this.details = const {},
  });

  final String code;
  final String message;
  final ReportSeverity severity;
  final String? source;
  final Map<String, String> details;

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        'severity': severity.wireName,
        if (source != null) 'source': source,
        if (details.isNotEmpty) 'details': details,
      };

  factory ReportFinding.fromJson(Map<String, dynamic> json) {
    return ReportFinding(
      code: json['code'] as String,
      message: json['message'] as String,
      severity: ReportSeverityX.fromWireName(json['severity'] as String),
      source: json['source'] as String?,
      details: (json['details'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}
