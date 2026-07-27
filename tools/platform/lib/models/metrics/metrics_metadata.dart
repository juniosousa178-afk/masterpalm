/// Metadata for a [MetricsSnapshot].
class MetricsMetadata {
  const MetricsMetadata({
    required this.snapshotId,
    required this.metricsSchemaVersion,
    required this.metricsCalculationVersion,
    required this.metricsCanonicalizationVersion,
    required this.fingerprintAlgorithm,
    required this.projectId,
    required this.sourceGraphFingerprint,
    required this.metricCount,
    required this.unavailableMetricCount,
    required this.warningCount,
    this.generatedAt,
    this.sourceSnapshotId,
    this.gitRef,
    this.extra = const {},
  });

  static const int currentSchemaVersion = 1;
  static const int currentCalculationVersion = 1;
  static const int currentCanonicalizationVersion = 1;
  static const String fingerprintAlgorithmName = 'sha256';

  final String snapshotId;
  final int metricsSchemaVersion;
  final int metricsCalculationVersion;
  final int metricsCanonicalizationVersion;
  final String fingerprintAlgorithm;
  final String projectId;
  final String sourceGraphFingerprint;
  final int metricCount;
  final int unavailableMetricCount;
  final int warningCount;
  final String? generatedAt;
  final String? sourceSnapshotId;
  final String? gitRef;
  final Map<String, String> extra;

  Map<String, dynamic> toJson() => {
        'snapshotId': snapshotId,
        'metricsSchemaVersion': metricsSchemaVersion,
        'metricsCalculationVersion': metricsCalculationVersion,
        'metricsCanonicalizationVersion': metricsCanonicalizationVersion,
        'fingerprintAlgorithm': fingerprintAlgorithm,
        'projectId': projectId,
        'sourceGraphFingerprint': sourceGraphFingerprint,
        'metricCount': metricCount,
        'unavailableMetricCount': unavailableMetricCount,
        'warningCount': warningCount,
        if (generatedAt != null) 'generatedAt': generatedAt,
        if (sourceSnapshotId != null) 'sourceSnapshotId': sourceSnapshotId,
        if (gitRef != null) 'gitRef': gitRef,
        if (extra.isNotEmpty) 'extra': extra,
      };

  factory MetricsMetadata.fromJson(Map<String, dynamic> json) {
    return MetricsMetadata(
      snapshotId: json['snapshotId'] as String,
      metricsSchemaVersion:
          json['metricsSchemaVersion'] as int? ?? currentSchemaVersion,
      metricsCalculationVersion: json['metricsCalculationVersion'] as int? ??
          currentCalculationVersion,
      metricsCanonicalizationVersion:
          json['metricsCanonicalizationVersion'] as int? ??
              currentCanonicalizationVersion,
      fingerprintAlgorithm:
          json['fingerprintAlgorithm'] as String? ?? fingerprintAlgorithmName,
      projectId: json['projectId'] as String,
      sourceGraphFingerprint: json['sourceGraphFingerprint'] as String,
      metricCount: json['metricCount'] as int? ?? 0,
      unavailableMetricCount: json['unavailableMetricCount'] as int? ?? 0,
      warningCount: json['warningCount'] as int? ?? 0,
      generatedAt: json['generatedAt'] as String?,
      sourceSnapshotId: json['sourceSnapshotId'] as String?,
      gitRef: json['gitRef'] as String?,
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
