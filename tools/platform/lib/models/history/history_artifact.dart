import 'history_artifact_payload.dart';
import 'history_artifact_type.dart';
import 'history_compatibility.dart';

/// Single versioned artifact within a [HistorySnapshot].
class HistoryArtifact {
  const HistoryArtifact({
    required this.artifactType,
    required this.artifactId,
    required this.schemaVersion,
    required this.fingerprint,
    required this.payload,
    this.canonicalizationVersion,
    this.calculationVersion,
    this.sourceSnapshotId,
    this.payloadEncoding = HistoryArtifactPayload.jsonEncoding,
    this.compatibility = const HistoryCompatibility(
      status: HistoryCompatibilityStatus.compatible,
    ),
  });

  final HistoryArtifactType artifactType;
  final String artifactId;
  final int schemaVersion;
  final int? canonicalizationVersion;
  final int? calculationVersion;
  final String fingerprint;
  final String? sourceSnapshotId;
  final String payloadEncoding;
  final HistoryArtifactPayload payload;
  final HistoryCompatibility compatibility;

  Map<String, dynamic> toJson() => {
        'artifactType': artifactType.wireName,
        'artifactId': artifactId,
        'schemaVersion': schemaVersion,
        if (canonicalizationVersion != null)
          'canonicalizationVersion': canonicalizationVersion,
        if (calculationVersion != null)
          'calculationVersion': calculationVersion,
        'fingerprint': fingerprint,
        if (sourceSnapshotId != null) 'sourceSnapshotId': sourceSnapshotId,
        'payloadEncoding': payloadEncoding,
        'payload': payload.toJson(),
        'compatibility': compatibility.toJson(),
      };

  factory HistoryArtifact.fromJson(Map<String, dynamic> json) {
    return HistoryArtifact(
      artifactType:
          HistoryArtifactTypeX.fromWireName(json['artifactType'] as String),
      artifactId: json['artifactId'] as String,
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      canonicalizationVersion: json['canonicalizationVersion'] as int?,
      calculationVersion: json['calculationVersion'] as int?,
      fingerprint: json['fingerprint'] as String,
      sourceSnapshotId: json['sourceSnapshotId'] as String?,
      payloadEncoding: json['payloadEncoding'] as String? ??
          HistoryArtifactPayload.jsonEncoding,
      payload: HistoryArtifactPayload.fromJson(
        json['payload'] as Map<String, dynamic>,
      ),
      compatibility: HistoryCompatibility.fromJson(
        json['compatibility'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}
