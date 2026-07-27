import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';

/// Declarative retention record for a persistent artifact.
///
/// Does not execute retention, deletion, or storage modification.
/// Legal hold declaratively prevents deletion eligibility.
class PersistentArtifactRetentionRecord {
  const PersistentArtifactRetentionRecord({
    required this.retentionRecordId,
    required this.artifactId,
    required this.versionId,
    required this.policyId,
    required this.legalHold,
    required this.status,
    this.retainUntil,
    this.immutableUntil,
    this.evaluatedAt,
    this.metadata = const {},
  });

  final String retentionRecordId;
  final String artifactId;
  final String versionId;
  final String policyId;
  final String? retainUntil;
  final bool legalHold;
  final String? immutableUntil;
  final PersistentArtifactRetentionRecordStatus status;
  final String? evaluatedAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'retentionRecordId': retentionRecordId,
        'artifactId': artifactId,
        'versionId': versionId,
        'policyId': policyId,
        if (retainUntil != null) 'retainUntil': retainUntil,
        'legalHold': legalHold,
        if (immutableUntil != null) 'immutableUntil': immutableUntil,
        'status': status.wireName,
        if (evaluatedAt != null) 'evaluatedAt': evaluatedAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactRetentionRecord.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactRetentionRecord(
      retentionRecordId: json['retentionRecordId'] as String,
      artifactId: json['artifactId'] as String,
      versionId: json['versionId'] as String,
      policyId: json['policyId'] as String,
      retainUntil: json['retainUntil'] as String?,
      legalHold: json['legalHold'] as bool,
      immutableUntil: json['immutableUntil'] as String?,
      status: PersistentArtifactRetentionRecordStatusX.fromWireName(
        json['status'] as String,
      ),
      evaluatedAt: json['evaluatedAt'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'retentionRecordId': retentionRecordId,
        'artifactId': artifactId,
        'versionId': versionId,
        'policyId': policyId,
        'legalHold': legalHold,
        'status': status.wireName,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactRetentionRecord copyWith({
    String? retentionRecordId,
    String? artifactId,
    String? versionId,
    String? policyId,
    String? retainUntil,
    bool? legalHold,
    String? immutableUntil,
    PersistentArtifactRetentionRecordStatus? status,
    String? evaluatedAt,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactRetentionRecord(
      retentionRecordId: retentionRecordId ?? this.retentionRecordId,
      artifactId: artifactId ?? this.artifactId,
      versionId: versionId ?? this.versionId,
      policyId: policyId ?? this.policyId,
      retainUntil: retainUntil ?? this.retainUntil,
      legalHold: legalHold ?? this.legalHold,
      immutableUntil: immutableUntil ?? this.immutableUntil,
      status: status ?? this.status,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactRetentionRecord &&
          retentionRecordId == other.retentionRecordId &&
          artifactId == other.artifactId &&
          versionId == other.versionId &&
          policyId == other.policyId &&
          retainUntil == other.retainUntil &&
          legalHold == other.legalHold &&
          immutableUntil == other.immutableUntil &&
          status == other.status &&
          evaluatedAt == other.evaluatedAt &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        retentionRecordId,
        artifactId,
        versionId,
        policyId,
        retainUntil,
        legalHold,
        immutableUntil,
        status,
        evaluatedAt,
        Object.hashAll(metadata.entries),
      );
}
