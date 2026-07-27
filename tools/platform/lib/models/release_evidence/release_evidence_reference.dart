import 'release_evidence_enums.dart';

/// Resolved source reference for evidence collection.
class ReleaseEvidenceSourceReference {
  const ReleaseEvidenceSourceReference({
    required this.sourceType,
    required this.resolutionMode,
    required this.requestedId,
    this.resolvedId,
    this.fingerprint,
    this.projectId,
    this.policyId,
    this.policyVersion,
    this.commitId,
    this.availability = ReleaseEvidenceAvailabilityStatus.unavailable,
    this.compatibility = ReleaseEvidenceCompatibilityStatus.unknown,
    this.limitations = const [],
  });

  final ReleaseEvidenceType sourceType;
  final ReleaseEvidenceSourceResolutionMode resolutionMode;
  final String requestedId;
  final String? resolvedId;
  final String? fingerprint;
  final String? projectId;
  final String? policyId;
  final int? policyVersion;
  final String? commitId;
  final ReleaseEvidenceAvailabilityStatus availability;
  final ReleaseEvidenceCompatibilityStatus compatibility;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'sourceType': sourceType.wireName,
        'resolutionMode': resolutionMode.wireName,
        'requestedId': requestedId,
        if (resolvedId != null) 'resolvedId': resolvedId,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (projectId != null) 'projectId': projectId,
        if (policyId != null) 'policyId': policyId,
        if (policyVersion != null) 'policyVersion': policyVersion,
        if (commitId != null) 'commitId': commitId,
        'availability': availability.wireName,
        'compatibility': compatibility.wireName,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseEvidenceSourceReference.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceSourceReference(
      sourceType: ReleaseEvidenceTypeX.fromWireName(
        json['sourceType'] as String,
      ),
      resolutionMode: ReleaseEvidenceSourceResolutionModeX.fromWireName(
        json['resolutionMode'] as String,
      ),
      requestedId: json['requestedId'] as String,
      resolvedId: json['resolvedId'] as String?,
      fingerprint: json['fingerprint'] as String?,
      projectId: json['projectId'] as String?,
      policyId: json['policyId'] as String?,
      policyVersion: json['policyVersion'] as int?,
      commitId: json['commitId'] as String?,
      availability: ReleaseEvidenceAvailabilityStatusX.fromWireName(
        json['availability'] as String? ?? 'unavailable',
      ),
      compatibility: ReleaseEvidenceCompatibilityStatusX.fromWireName(
        json['compatibility'] as String? ?? 'unknown',
      ),
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  ReleaseEvidenceSourceReference copyWith({
    ReleaseEvidenceType? sourceType,
    ReleaseEvidenceSourceResolutionMode? resolutionMode,
    String? requestedId,
    String? resolvedId,
    String? fingerprint,
    String? projectId,
    String? policyId,
    int? policyVersion,
    String? commitId,
    ReleaseEvidenceAvailabilityStatus? availability,
    ReleaseEvidenceCompatibilityStatus? compatibility,
    List<String>? limitations,
  }) {
    return ReleaseEvidenceSourceReference(
      sourceType: sourceType ?? this.sourceType,
      resolutionMode: resolutionMode ?? this.resolutionMode,
      requestedId: requestedId ?? this.requestedId,
      resolvedId: resolvedId ?? this.resolvedId,
      fingerprint: fingerprint ?? this.fingerprint,
      projectId: projectId ?? this.projectId,
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      commitId: commitId ?? this.commitId,
      availability: availability ?? this.availability,
      compatibility: compatibility ?? this.compatibility,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceSourceReference &&
          runtimeType == other.runtimeType &&
          sourceType == other.sourceType &&
          resolutionMode == other.resolutionMode &&
          requestedId == other.requestedId &&
          resolvedId == other.resolvedId &&
          fingerprint == other.fingerprint &&
          projectId == other.projectId &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          commitId == other.commitId &&
          availability == other.availability &&
          compatibility == other.compatibility &&
          _listEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        sourceType,
        resolutionMode,
        requestedId,
        resolvedId,
        fingerprint,
        projectId,
        policyId,
        policyVersion,
        commitId,
        availability,
        compatibility,
        Object.hashAll(limitations),
      );
}

/// Typed reference to a published evidence artifact (no full payload).
class ReleaseEvidenceReference {
  const ReleaseEvidenceReference({
    required this.evidenceId,
    required this.evidenceType,
    required this.artifactType,
    required this.artifactId,
    required this.artifactFingerprint,
    required this.projectId,
    required this.schemaVersion,
    required this.observedAt,
    required this.status,
    this.releaseId,
    this.commitId,
    this.calculationVersion,
    this.canonicalizationVersion,
    this.sourceReference,
    this.publishedAt,
    this.metadata = const {},
  });

  final String evidenceId;
  final ReleaseEvidenceType evidenceType;
  final ReleaseEvidenceArtifactType artifactType;
  final String artifactId;
  final String artifactFingerprint;
  final String projectId;
  final String? releaseId;
  final String? commitId;
  final int schemaVersion;
  final int? calculationVersion;
  final int? canonicalizationVersion;
  final ReleaseEvidenceSourceReference? sourceReference;
  final String observedAt;
  final String? publishedAt;
  final ReleaseEvidenceReferenceStatus status;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'evidenceId': evidenceId,
        'evidenceType': evidenceType.wireName,
        'artifactType': artifactType.wireName,
        'artifactId': artifactId,
        'artifactFingerprint': artifactFingerprint,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        'schemaVersion': schemaVersion,
        if (calculationVersion != null)
          'calculationVersion': calculationVersion,
        if (canonicalizationVersion != null)
          'canonicalizationVersion': canonicalizationVersion,
        if (sourceReference != null)
          'sourceReference': sourceReference!.toJson(),
        'observedAt': observedAt,
        if (publishedAt != null) 'publishedAt': publishedAt,
        'status': status.wireName,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseEvidenceReference.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceReference(
      evidenceId: json['evidenceId'] as String,
      evidenceType: ReleaseEvidenceTypeX.fromWireName(
        json['evidenceType'] as String,
      ),
      artifactType: ReleaseEvidenceArtifactTypeX.fromWireName(
        json['artifactType'] as String,
      ),
      artifactId: json['artifactId'] as String,
      artifactFingerprint: json['artifactFingerprint'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      commitId: json['commitId'] as String?,
      schemaVersion: json['schemaVersion'] as int,
      calculationVersion: json['calculationVersion'] as int?,
      canonicalizationVersion: json['canonicalizationVersion'] as int?,
      sourceReference: json['sourceReference'] == null
          ? null
          : ReleaseEvidenceSourceReference.fromJson(
              json['sourceReference'] as Map<String, dynamic>,
            ),
      observedAt: json['observedAt'] as String,
      publishedAt: json['publishedAt'] as String?,
      status: ReleaseEvidenceReferenceStatusX.fromWireName(
        json['status'] as String,
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  ReleaseEvidenceReference copyWith({
    String? evidenceId,
    ReleaseEvidenceType? evidenceType,
    ReleaseEvidenceArtifactType? artifactType,
    String? artifactId,
    String? artifactFingerprint,
    String? projectId,
    String? releaseId,
    String? commitId,
    int? schemaVersion,
    int? calculationVersion,
    int? canonicalizationVersion,
    ReleaseEvidenceSourceReference? sourceReference,
    String? observedAt,
    String? publishedAt,
    ReleaseEvidenceReferenceStatus? status,
    Map<String, String>? metadata,
  }) {
    return ReleaseEvidenceReference(
      evidenceId: evidenceId ?? this.evidenceId,
      evidenceType: evidenceType ?? this.evidenceType,
      artifactType: artifactType ?? this.artifactType,
      artifactId: artifactId ?? this.artifactId,
      artifactFingerprint: artifactFingerprint ?? this.artifactFingerprint,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      commitId: commitId ?? this.commitId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      calculationVersion: calculationVersion ?? this.calculationVersion,
      canonicalizationVersion:
          canonicalizationVersion ?? this.canonicalizationVersion,
      sourceReference: sourceReference ?? this.sourceReference,
      observedAt: observedAt ?? this.observedAt,
      publishedAt: publishedAt ?? this.publishedAt,
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceReference &&
          runtimeType == other.runtimeType &&
          evidenceId == other.evidenceId &&
          evidenceType == other.evidenceType &&
          artifactType == other.artifactType &&
          artifactId == other.artifactId &&
          artifactFingerprint == other.artifactFingerprint &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          commitId == other.commitId &&
          schemaVersion == other.schemaVersion &&
          calculationVersion == other.calculationVersion &&
          canonicalizationVersion == other.canonicalizationVersion &&
          sourceReference == other.sourceReference &&
          observedAt == other.observedAt &&
          publishedAt == other.publishedAt &&
          status == other.status &&
          _mapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        evidenceId,
        evidenceType,
        artifactType,
        artifactId,
        artifactFingerprint,
        projectId,
        releaseId,
        commitId,
        schemaVersion,
        calculationVersion,
        canonicalizationVersion,
        sourceReference,
        observedAt,
        publishedAt,
        status,
        Object.hashAll(metadata.entries),
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
