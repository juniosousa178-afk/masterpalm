import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';

/// Declarative lifecycle transition record for a persistent artifact.
///
/// Represents transition intent only — does not execute physical lifecycle.
class PersistentArtifactLifecycleRecord {
  const PersistentArtifactLifecycleRecord({
    required this.lifecycleRecordId,
    required this.artifactId,
    required this.versionId,
    required this.lifecycleStatus,
    this.effectiveAt,
    this.previousStatus,
    this.reasonCode,
    this.reason,
    this.policyId,
    this.metadata = const {},
  });

  final String lifecycleRecordId;
  final String artifactId;
  final String versionId;
  final PersistentArtifactLifecycleStatus lifecycleStatus;
  final String? effectiveAt;
  final PersistentArtifactLifecycleStatus? previousStatus;
  final String? reasonCode;
  final String? reason;
  final String? policyId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'lifecycleRecordId': lifecycleRecordId,
        'artifactId': artifactId,
        'versionId': versionId,
        'lifecycleStatus': lifecycleStatus.wireName,
        if (effectiveAt != null) 'effectiveAt': effectiveAt,
        if (previousStatus != null) 'previousStatus': previousStatus!.wireName,
        if (reasonCode != null) 'reasonCode': reasonCode,
        if (reason != null) 'reason': reason,
        if (policyId != null) 'policyId': policyId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactLifecycleRecord.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactLifecycleRecord(
      lifecycleRecordId: json['lifecycleRecordId'] as String,
      artifactId: json['artifactId'] as String,
      versionId: json['versionId'] as String,
      lifecycleStatus: PersistentArtifactLifecycleStatusX.fromWireName(
        json['lifecycleStatus'] as String,
      ),
      effectiveAt: json['effectiveAt'] as String?,
      previousStatus: json['previousStatus'] != null
          ? PersistentArtifactLifecycleStatusX.fromWireName(
              json['previousStatus'] as String,
            )
          : null,
      reasonCode: json['reasonCode'] as String?,
      reason: json['reason'] as String?,
      policyId: json['policyId'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'lifecycleRecordId': lifecycleRecordId,
        'artifactId': artifactId,
        'versionId': versionId,
        'lifecycleStatus': lifecycleStatus.wireName,
        if (previousStatus != null) 'previousStatus': previousStatus!.wireName,
        if (reasonCode != null) 'reasonCode': reasonCode,
        if (reason != null) 'reason': reason,
        if (policyId != null) 'policyId': policyId,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactLifecycleRecord copyWith({
    String? lifecycleRecordId,
    String? artifactId,
    String? versionId,
    PersistentArtifactLifecycleStatus? lifecycleStatus,
    String? effectiveAt,
    PersistentArtifactLifecycleStatus? previousStatus,
    String? reasonCode,
    String? reason,
    String? policyId,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactLifecycleRecord(
      lifecycleRecordId: lifecycleRecordId ?? this.lifecycleRecordId,
      artifactId: artifactId ?? this.artifactId,
      versionId: versionId ?? this.versionId,
      lifecycleStatus: lifecycleStatus ?? this.lifecycleStatus,
      effectiveAt: effectiveAt ?? this.effectiveAt,
      previousStatus: previousStatus ?? this.previousStatus,
      reasonCode: reasonCode ?? this.reasonCode,
      reason: reason ?? this.reason,
      policyId: policyId ?? this.policyId,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactLifecycleRecord &&
          lifecycleRecordId == other.lifecycleRecordId &&
          artifactId == other.artifactId &&
          versionId == other.versionId &&
          lifecycleStatus == other.lifecycleStatus &&
          effectiveAt == other.effectiveAt &&
          previousStatus == other.previousStatus &&
          reasonCode == other.reasonCode &&
          reason == other.reason &&
          policyId == other.policyId &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        lifecycleRecordId,
        artifactId,
        versionId,
        lifecycleStatus,
        effectiveAt,
        previousStatus,
        reasonCode,
        reason,
        policyId,
        Object.hashAll(metadata.entries),
      );
}
