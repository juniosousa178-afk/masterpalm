import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';

/// Upstream source reference for persistent artifact provenance.
///
/// Reference only — does not resolve providers or recalculate fingerprints.
class PersistentArtifactSourceReference {
  const PersistentArtifactSourceReference({
    required this.sourceType,
    required this.sourceId,
    required this.projectId,
    required this.fingerprint,
    this.releaseId,
    this.version,
    this.metadata = const {},
  });

  final PersistentArtifactSourceType sourceType;
  final String sourceId;
  final String projectId;
  final String? releaseId;
  final String fingerprint;
  final String? version;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'sourceType': sourceType.wireName,
        'sourceId': sourceId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'fingerprint': fingerprint,
        if (version != null) 'version': version,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactSourceReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactSourceReference(
      sourceType: PersistentArtifactSourceTypeX.fromWireName(
        json['sourceType'] as String,
      ),
      sourceId: json['sourceId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      fingerprint: json['fingerprint'] as String,
      version: json['version'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'sourceType': sourceType.wireName,
        'sourceId': sourceId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'fingerprint': fingerprint,
        if (version != null) 'version': version,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactSourceReference copyWith({
    PersistentArtifactSourceType? sourceType,
    String? sourceId,
    String? projectId,
    String? releaseId,
    String? fingerprint,
    String? version,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactSourceReference(
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      fingerprint: fingerprint ?? this.fingerprint,
      version: version ?? this.version,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactSourceReference &&
          sourceType == other.sourceType &&
          sourceId == other.sourceId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          fingerprint == other.fingerprint &&
          version == other.version &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        sourceType,
        sourceId,
        projectId,
        releaseId,
        fingerprint,
        version,
        Object.hashAll(metadata.entries),
      );
}

/// Policy reference for persistent artifact domain.
///
/// Reference only — does not resolve, promote, or execute policies.
class PersistentArtifactPolicyReference {
  const PersistentArtifactPolicyReference({
    required this.policyId,
    required this.policyVersion,
    required this.policyType,
    required this.policyFingerprint,
    required this.status,
    this.metadata = const {},
  });

  final String policyId;
  final int policyVersion;
  final PersistentArtifactPolicyType policyType;
  final String policyFingerprint;
  final PersistentArtifactPolicyStatus status;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'policyType': policyType.wireName,
        'policyFingerprint': policyFingerprint,
        'status': status.wireName,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactPolicyReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactPolicyReference(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      policyType: PersistentArtifactPolicyTypeX.fromWireName(
        json['policyType'] as String,
      ),
      policyFingerprint: json['policyFingerprint'] as String,
      status: PersistentArtifactPolicyStatusX.fromWireName(
        json['status'] as String,
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'policyType': policyType.wireName,
        'policyFingerprint': policyFingerprint,
        'status': status.wireName,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactPolicyReference copyWith({
    String? policyId,
    int? policyVersion,
    PersistentArtifactPolicyType? policyType,
    String? policyFingerprint,
    PersistentArtifactPolicyStatus? status,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactPolicyReference(
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      policyType: policyType ?? this.policyType,
      policyFingerprint: policyFingerprint ?? this.policyFingerprint,
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactPolicyReference &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          policyType == other.policyType &&
          policyFingerprint == other.policyFingerprint &&
          status == other.status &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        policyId,
        policyVersion,
        policyType,
        policyFingerprint,
        status,
        Object.hashAll(metadata.entries),
      );
}
