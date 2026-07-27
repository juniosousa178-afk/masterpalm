import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';
import 'persistent_artifact_reference_models.dart';
import 'persistent_artifact_validation_result.dart';

/// Declarative deletion request for a persistent artifact.
///
/// Represents intent only — does not execute physical deletion.
/// Force does not automatically bypass legal hold.
class PersistentArtifactDeletionRequest {
  const PersistentArtifactDeletionRequest({
    required this.deletionRequestId,
    required this.artifactId,
    required this.reasonCode,
    required this.requestedAt,
    required this.force,
    this.versionId,
    this.requestedByIdentityId,
    this.reason,
    this.metadata = const {},
  });

  final String deletionRequestId;
  final String artifactId;
  final String? versionId;
  final String? requestedByIdentityId;
  final String reasonCode;
  final String? reason;
  final String requestedAt;
  final bool force;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'deletionRequestId': deletionRequestId,
        'artifactId': artifactId,
        if (versionId != null) 'versionId': versionId,
        if (requestedByIdentityId != null)
          'requestedByIdentityId': requestedByIdentityId,
        'reasonCode': reasonCode,
        if (reason != null) 'reason': reason,
        'requestedAt': requestedAt,
        'force': force,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactDeletionRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactDeletionRequest(
      deletionRequestId: json['deletionRequestId'] as String,
      artifactId: json['artifactId'] as String,
      versionId: json['versionId'] as String?,
      requestedByIdentityId: json['requestedByIdentityId'] as String?,
      reasonCode: json['reasonCode'] as String,
      reason: json['reason'] as String?,
      requestedAt: json['requestedAt'] as String,
      force: json['force'] as bool,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'deletionRequestId': deletionRequestId,
        'artifactId': artifactId,
        if (versionId != null) 'versionId': versionId,
        if (requestedByIdentityId != null)
          'requestedByIdentityId': requestedByIdentityId,
        'reasonCode': reasonCode,
        if (reason != null) 'reason': reason,
        'force': force,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactDeletionRequest copyWith({
    String? deletionRequestId,
    String? artifactId,
    String? versionId,
    String? requestedByIdentityId,
    String? reasonCode,
    String? reason,
    String? requestedAt,
    bool? force,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactDeletionRequest(
      deletionRequestId: deletionRequestId ?? this.deletionRequestId,
      artifactId: artifactId ?? this.artifactId,
      versionId: versionId ?? this.versionId,
      requestedByIdentityId:
          requestedByIdentityId ?? this.requestedByIdentityId,
      reasonCode: reasonCode ?? this.reasonCode,
      reason: reason ?? this.reason,
      requestedAt: requestedAt ?? this.requestedAt,
      force: force ?? this.force,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactDeletionRequest &&
          deletionRequestId == other.deletionRequestId &&
          artifactId == other.artifactId &&
          versionId == other.versionId &&
          requestedByIdentityId == other.requestedByIdentityId &&
          reasonCode == other.reasonCode &&
          reason == other.reason &&
          requestedAt == other.requestedAt &&
          force == other.force &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        deletionRequestId,
        artifactId,
        versionId,
        requestedByIdentityId,
        reasonCode,
        reason,
        requestedAt,
        force,
        Object.hashAll(metadata.entries),
      );
}

/// Declarative deletion result for a persistent artifact.
///
/// Declared outcome only — deleted does not prove physical removal.
class PersistentArtifactDeletionResult {
  const PersistentArtifactDeletionResult({
    required this.deletionResultId,
    required this.deletionRequestId,
    required this.artifactId,
    required this.status,
    this.versionId,
    this.tombstoneId,
    this.issues = const [],
    this.evaluatedAt,
    this.metadata = const {},
  });

  final String deletionResultId;
  final String deletionRequestId;
  final String artifactId;
  final String? versionId;
  final PersistentArtifactDeletionStatus status;
  final String? tombstoneId;
  final List<PersistentArtifactIssue> issues;
  final String? evaluatedAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'deletionResultId': deletionResultId,
        'deletionRequestId': deletionRequestId,
        'artifactId': artifactId,
        if (versionId != null) 'versionId': versionId,
        'status': status.wireName,
        if (tombstoneId != null) 'tombstoneId': tombstoneId,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (evaluatedAt != null) 'evaluatedAt': evaluatedAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactDeletionResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactDeletionResult(
      deletionResultId: json['deletionResultId'] as String,
      deletionRequestId: json['deletionRequestId'] as String,
      artifactId: json['artifactId'] as String,
      versionId: json['versionId'] as String?,
      status: PersistentArtifactDeletionStatusX.fromWireName(
        json['status'] as String,
      ),
      tombstoneId: json['tombstoneId'] as String?,
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactIssue.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
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
        'deletionResultId': deletionResultId,
        'deletionRequestId': deletionRequestId,
        'artifactId': artifactId,
        if (versionId != null) 'versionId': versionId,
        'status': status.wireName,
        if (tombstoneId != null) 'tombstoneId': tombstoneId,
        if (issues.isNotEmpty)
          'issues': (issues.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => (a['code'] as String).compareTo(b['code'] as String),
            )),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactDeletionResult copyWith({
    String? deletionResultId,
    String? deletionRequestId,
    String? artifactId,
    String? versionId,
    PersistentArtifactDeletionStatus? status,
    String? tombstoneId,
    List<PersistentArtifactIssue>? issues,
    String? evaluatedAt,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactDeletionResult(
      deletionResultId: deletionResultId ?? this.deletionResultId,
      deletionRequestId: deletionRequestId ?? this.deletionRequestId,
      artifactId: artifactId ?? this.artifactId,
      versionId: versionId ?? this.versionId,
      status: status ?? this.status,
      tombstoneId: tombstoneId ?? this.tombstoneId,
      issues: issues ?? this.issues,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactDeletionResult &&
          deletionResultId == other.deletionResultId &&
          deletionRequestId == other.deletionRequestId &&
          artifactId == other.artifactId &&
          versionId == other.versionId &&
          status == other.status &&
          tombstoneId == other.tombstoneId &&
          paListEquals(issues, other.issues) &&
          evaluatedAt == other.evaluatedAt &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        deletionResultId,
        deletionRequestId,
        artifactId,
        versionId,
        status,
        tombstoneId,
        Object.hashAll(issues),
        evaluatedAt,
        Object.hashAll(metadata.entries),
      );
}

/// Declarative tombstone for a deleted persistent artifact.
///
/// Tombstone does not contain content and does not execute physical deletion.
/// Does not authorize ID reuse.
class PersistentArtifactTombstone {
  const PersistentArtifactTombstone({
    required this.tombstoneId,
    required this.artifactId,
    required this.previousContentFingerprint,
    required this.deletionRequestId,
    required this.deletionStatus,
    required this.createdAt,
    required this.reasonCode,
    this.versionId,
    this.expiresAt,
    this.sourceReferences = const [],
    this.metadata = const {},
  });

  final String tombstoneId;
  final String artifactId;
  final String? versionId;
  final String previousContentFingerprint;
  final String deletionRequestId;
  final PersistentArtifactDeletionStatus deletionStatus;
  final String createdAt;
  final String? expiresAt;
  final String reasonCode;
  final List<PersistentArtifactSourceReference> sourceReferences;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'tombstoneId': tombstoneId,
        'artifactId': artifactId,
        if (versionId != null) 'versionId': versionId,
        'previousContentFingerprint': previousContentFingerprint,
        'deletionRequestId': deletionRequestId,
        'deletionStatus': deletionStatus.wireName,
        'createdAt': createdAt,
        if (expiresAt != null) 'expiresAt': expiresAt,
        'reasonCode': reasonCode,
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactTombstone.fromJson(Map<String, dynamic> json) {
    return PersistentArtifactTombstone(
      tombstoneId: json['tombstoneId'] as String,
      artifactId: json['artifactId'] as String,
      versionId: json['versionId'] as String?,
      previousContentFingerprint: json['previousContentFingerprint'] as String,
      deletionRequestId: json['deletionRequestId'] as String,
      deletionStatus: PersistentArtifactDeletionStatusX.fromWireName(
        json['deletionStatus'] as String,
      ),
      createdAt: json['createdAt'] as String,
      expiresAt: json['expiresAt'] as String?,
      reasonCode: json['reasonCode'] as String,
      sourceReferences: List.unmodifiable(
        (json['sourceReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactSourceReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'tombstoneId': tombstoneId,
        'artifactId': artifactId,
        if (versionId != null) 'versionId': versionId,
        'previousContentFingerprint': previousContentFingerprint,
        'deletionRequestId': deletionRequestId,
        'deletionStatus': deletionStatus.wireName,
        'reasonCode': reasonCode,
        if (sourceReferences.isNotEmpty)
          'sourceReferences': paSortedComparableList(
            sourceReferences.map((e) => e.toComparableJson()),
            'sourceId',
          ),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactTombstone copyWith({
    String? tombstoneId,
    String? artifactId,
    String? versionId,
    String? previousContentFingerprint,
    String? deletionRequestId,
    PersistentArtifactDeletionStatus? deletionStatus,
    String? createdAt,
    String? expiresAt,
    String? reasonCode,
    List<PersistentArtifactSourceReference>? sourceReferences,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactTombstone(
      tombstoneId: tombstoneId ?? this.tombstoneId,
      artifactId: artifactId ?? this.artifactId,
      versionId: versionId ?? this.versionId,
      previousContentFingerprint:
          previousContentFingerprint ?? this.previousContentFingerprint,
      deletionRequestId: deletionRequestId ?? this.deletionRequestId,
      deletionStatus: deletionStatus ?? this.deletionStatus,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      reasonCode: reasonCode ?? this.reasonCode,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactTombstone &&
          tombstoneId == other.tombstoneId &&
          artifactId == other.artifactId &&
          versionId == other.versionId &&
          previousContentFingerprint == other.previousContentFingerprint &&
          deletionRequestId == other.deletionRequestId &&
          deletionStatus == other.deletionStatus &&
          createdAt == other.createdAt &&
          expiresAt == other.expiresAt &&
          reasonCode == other.reasonCode &&
          paListEquals(sourceReferences, other.sourceReferences) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        tombstoneId,
        artifactId,
        versionId,
        previousContentFingerprint,
        deletionRequestId,
        deletionStatus,
        createdAt,
        expiresAt,
        reasonCode,
        Object.hashAll(sourceReferences),
        Object.hashAll(metadata.entries),
      );
}
