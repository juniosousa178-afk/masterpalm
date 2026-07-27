import 'history_artifact_type.dart';
import 'history_compatibility.dart';
import 'history_snapshot_status.dart';

/// Metadata for a [HistorySnapshot].
class HistoryMetadata {
  const HistoryMetadata({
    required this.historySnapshotId,
    required this.historySchemaVersion,
    required this.historyCanonicalizationVersion,
    required this.projectId,
    required this.createdAt,
    required this.snapshotFingerprint,
    required this.artifactCount,
    required this.artifactTypes,
    required this.status,
    this.sequence,
    this.gitRef,
    this.branch,
    this.sourceEventId,
    this.missingArtifacts = const [],
    this.warnings = const [],
    this.tags = const [],
    this.extra = const {},
    this.compatibility = const HistoryCompatibility(
      status: HistoryCompatibilityStatus.compatible,
    ),
  });

  static const int currentSchemaVersion = 1;
  static const int currentCanonicalizationVersion = 1;
  static const String fingerprintAlgorithm = 'sha256';

  final String historySnapshotId;
  final int historySchemaVersion;
  final int historyCanonicalizationVersion;
  final String projectId;
  final String createdAt;
  final String snapshotFingerprint;
  final int artifactCount;
  final List<HistoryArtifactType> artifactTypes;
  final HistorySnapshotStatus status;
  final int? sequence;
  final String? gitRef;
  final String? branch;
  final String? sourceEventId;
  final List<HistoryArtifactType> missingArtifacts;
  final List<String> warnings;
  final List<String> tags;
  final Map<String, String> extra;
  final HistoryCompatibility compatibility;

  Map<String, dynamic> toJson() => {
        'historySnapshotId': historySnapshotId,
        'historySchemaVersion': historySchemaVersion,
        'historyCanonicalizationVersion': historyCanonicalizationVersion,
        'fingerprintAlgorithm': fingerprintAlgorithm,
        'projectId': projectId,
        'createdAt': createdAt,
        'snapshotFingerprint': snapshotFingerprint,
        'artifactCount': artifactCount,
        'artifactTypes': artifactTypes.map((t) => t.wireName).toList()..sort(),
        'status': status.wireName,
        if (sequence != null) 'sequence': sequence,
        if (gitRef != null) 'gitRef': gitRef,
        if (branch != null) 'branch': branch,
        if (sourceEventId != null) 'sourceEventId': sourceEventId,
        if (missingArtifacts.isNotEmpty)
          'missingArtifacts': missingArtifacts.map((t) => t.wireName).toList()
            ..sort(),
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (tags.isNotEmpty) 'tags': tags,
        if (extra.isNotEmpty) 'extra': extra,
        'compatibility': compatibility.toJson(),
      };

  factory HistoryMetadata.fromJson(Map<String, dynamic> json) {
    return HistoryMetadata(
      historySnapshotId: json['historySnapshotId'] as String,
      historySchemaVersion:
          json['historySchemaVersion'] as int? ?? currentSchemaVersion,
      historyCanonicalizationVersion:
          json['historyCanonicalizationVersion'] as int? ??
              currentCanonicalizationVersion,
      projectId: json['projectId'] as String,
      createdAt: json['createdAt'] as String,
      snapshotFingerprint: json['snapshotFingerprint'] as String,
      artifactCount: json['artifactCount'] as int? ?? 0,
      artifactTypes: (json['artifactTypes'] as List<dynamic>? ?? [])
          .map((e) => HistoryArtifactTypeX.fromWireName(e.toString()))
          .toList(),
      status: HistorySnapshotStatusX.fromWireName(json['status'] as String),
      sequence: json['sequence'] as int?,
      gitRef: json['gitRef'] as String?,
      branch: json['branch'] as String?,
      sourceEventId: json['sourceEventId'] as String?,
      missingArtifacts: (json['missingArtifacts'] as List<dynamic>? ?? [])
          .map((e) => HistoryArtifactTypeX.fromWireName(e.toString()))
          .toList(),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      extra: (json['extra'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
      compatibility: HistoryCompatibility.fromJson(
        json['compatibility'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toComparableJson() {
    final json = toJson();
    json.remove('createdAt');
    json.remove('sequence');
    return json;
  }

  HistoryMetadata copyWith({
    String? historySnapshotId,
    int? historySchemaVersion,
    int? historyCanonicalizationVersion,
    String? projectId,
    String? createdAt,
    String? snapshotFingerprint,
    int? artifactCount,
    List<HistoryArtifactType>? artifactTypes,
    HistorySnapshotStatus? status,
    int? sequence,
    String? gitRef,
    String? branch,
    String? sourceEventId,
    List<HistoryArtifactType>? missingArtifacts,
    List<String>? warnings,
    List<String>? tags,
    Map<String, String>? extra,
    HistoryCompatibility? compatibility,
  }) {
    return HistoryMetadata(
      historySnapshotId: historySnapshotId ?? this.historySnapshotId,
      historySchemaVersion: historySchemaVersion ?? this.historySchemaVersion,
      historyCanonicalizationVersion:
          historyCanonicalizationVersion ?? this.historyCanonicalizationVersion,
      projectId: projectId ?? this.projectId,
      createdAt: createdAt ?? this.createdAt,
      snapshotFingerprint: snapshotFingerprint ?? this.snapshotFingerprint,
      artifactCount: artifactCount ?? this.artifactCount,
      artifactTypes: artifactTypes ?? this.artifactTypes,
      status: status ?? this.status,
      sequence: sequence ?? this.sequence,
      gitRef: gitRef ?? this.gitRef,
      branch: branch ?? this.branch,
      sourceEventId: sourceEventId ?? this.sourceEventId,
      missingArtifacts: missingArtifacts ?? this.missingArtifacts,
      warnings: warnings ?? this.warnings,
      tags: tags ?? this.tags,
      extra: extra ?? this.extra,
      compatibility: compatibility ?? this.compatibility,
    );
  }
}
