import 'report_format.dart';
import 'report_type.dart';

/// Metadata for a [ReportDocument].
class ReportMetadata {
  const ReportMetadata({
    required this.reportId,
    required this.reportType,
    required this.reportSchemaVersion,
    required this.projectId,
    required this.generatorVersion,
    this.generatedAt,
    this.sourceSnapshotId,
    this.gitRef,
    this.supportedFormats = const {
      ReportFormat.markdown,
      ReportFormat.json,
      ReportFormat.html,
    },
    this.warnings = const [],
    this.missingSources = const [],
    this.extra = const {},
  });

  static const int currentSchemaVersion = 1;
  static const String defaultGeneratorVersion = 'masterpalm-report-engine-1.0';

  final String reportId;
  final ReportType reportType;
  final int reportSchemaVersion;
  final String projectId;
  final String generatorVersion;
  final String? generatedAt;
  final String? sourceSnapshotId;
  final String? gitRef;
  final Set<ReportFormat> supportedFormats;
  final List<String> warnings;
  final List<String> missingSources;
  final Map<String, String> extra;

  Map<String, dynamic> toJson() => {
        'reportId': reportId,
        'reportType': reportType.wireName,
        'reportSchemaVersion': reportSchemaVersion,
        'projectId': projectId,
        'generatorVersion': generatorVersion,
        if (generatedAt != null) 'generatedAt': generatedAt,
        if (sourceSnapshotId != null) 'sourceSnapshotId': sourceSnapshotId,
        if (gitRef != null) 'gitRef': gitRef,
        'supportedFormats': supportedFormats.map((f) => f.wireName).toList()
          ..sort(),
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (missingSources.isNotEmpty) 'missingSources': missingSources,
        if (extra.isNotEmpty) 'extra': extra,
      };

  factory ReportMetadata.fromJson(Map<String, dynamic> json) {
    return ReportMetadata(
      reportId: json['reportId'] as String,
      reportType: ReportTypeX.fromWireName(json['reportType'] as String),
      reportSchemaVersion: json['reportSchemaVersion'] as int? ?? 1,
      projectId: json['projectId'] as String,
      generatorVersion:
          json['generatorVersion'] as String? ?? defaultGeneratorVersion,
      generatedAt: json['generatedAt'] as String?,
      sourceSnapshotId: json['sourceSnapshotId'] as String?,
      gitRef: json['gitRef'] as String?,
      supportedFormats: (json['supportedFormats'] as List<dynamic>? ?? [])
          .map((e) => ReportFormatX.fromWireName(e.toString()))
          .toSet(),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      missingSources: (json['missingSources'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      extra: (json['extra'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }

  Map<String, dynamic> toComparableJson() {
    final json = toJson();
    json.remove('generatedAt');
    return json;
  }
}
