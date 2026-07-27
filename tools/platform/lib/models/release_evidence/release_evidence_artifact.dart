import 'release_evidence_enums.dart';
import 'release_evidence_subject.dart';

/// Structural integrity assessment for an evidence artifact.
class ReleaseEvidenceIntegrity {
  const ReleaseEvidenceIntegrity({
    required this.status,
    required this.fingerprintPresent,
    required this.identityPresent,
    required this.schemaKnown,
    required this.canonicalizationKnown,
    required this.sourceTrustedByPolicy,
    required this.verificationMethod,
    this.fingerprintMatches,
    this.reasons = const [],
    this.limitations = const [],
  });

  final ReleaseEvidenceIntegrityStatus status;
  final bool fingerprintPresent;
  final bool? fingerprintMatches;
  final bool identityPresent;
  final bool schemaKnown;
  final bool canonicalizationKnown;
  final bool sourceTrustedByPolicy;
  final String verificationMethod;
  final List<String> reasons;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'fingerprintPresent': fingerprintPresent,
        if (fingerprintMatches != null)
          'fingerprintMatches': fingerprintMatches,
        'identityPresent': identityPresent,
        'schemaKnown': schemaKnown,
        'canonicalizationKnown': canonicalizationKnown,
        'sourceTrustedByPolicy': sourceTrustedByPolicy,
        'verificationMethod': verificationMethod,
        if (reasons.isNotEmpty) 'reasons': reasons,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseEvidenceIntegrity.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceIntegrity(
      status: ReleaseEvidenceIntegrityStatusX.fromWireName(
        json['status'] as String,
      ),
      fingerprintPresent: json['fingerprintPresent'] as bool,
      fingerprintMatches: json['fingerprintMatches'] as bool?,
      identityPresent: json['identityPresent'] as bool,
      schemaKnown: json['schemaKnown'] as bool,
      canonicalizationKnown: json['canonicalizationKnown'] as bool,
      sourceTrustedByPolicy: json['sourceTrustedByPolicy'] as bool,
      verificationMethod: json['verificationMethod'] as String,
      reasons: List.unmodifiable(
        (json['reasons'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceIntegrity &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          fingerprintPresent == other.fingerprintPresent &&
          fingerprintMatches == other.fingerprintMatches &&
          identityPresent == other.identityPresent &&
          schemaKnown == other.schemaKnown &&
          canonicalizationKnown == other.canonicalizationKnown &&
          sourceTrustedByPolicy == other.sourceTrustedByPolicy &&
          verificationMethod == other.verificationMethod &&
          _listEquals(reasons, other.reasons) &&
          _listEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        status,
        fingerprintPresent,
        fingerprintMatches,
        identityPresent,
        schemaKnown,
        canonicalizationKnown,
        sourceTrustedByPolicy,
        verificationMethod,
        Object.hashAll(reasons),
        Object.hashAll(limitations),
      );
}

/// Reference to a published artifact within an evidence bundle item.
class ReleaseEvidenceArtifactReference {
  const ReleaseEvidenceArtifactReference({
    required this.artifactId,
    required this.artifactType,
    required this.fingerprint,
    this.schemaVersion,
    this.metadata = const {},
  });

  final String artifactId;
  final ReleaseEvidenceArtifactType artifactType;
  final String fingerprint;
  final int? schemaVersion;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'artifactId': artifactId,
        'artifactType': artifactType.wireName,
        'fingerprint': fingerprint,
        if (schemaVersion != null) 'schemaVersion': schemaVersion,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseEvidenceArtifactReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseEvidenceArtifactReference(
      artifactId: json['artifactId'] as String,
      artifactType: ReleaseEvidenceArtifactTypeX.fromWireName(
        json['artifactType'] as String,
      ),
      fingerprint: json['fingerprint'] as String,
      schemaVersion: json['schemaVersion'] as int?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceArtifactReference &&
          runtimeType == other.runtimeType &&
          artifactId == other.artifactId &&
          artifactType == other.artifactType &&
          fingerprint == other.fingerprint &&
          schemaVersion == other.schemaVersion &&
          _mapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        artifactId,
        artifactType,
        fingerprint,
        schemaVersion,
        Object.hashAll(metadata.entries),
      );
}

/// Evidence artifact collected into a release evidence bundle.
class ReleaseEvidenceArtifact {
  const ReleaseEvidenceArtifact({
    required this.artifactReference,
    required this.subject,
    required this.evidenceClass,
    required this.evidenceRole,
    required this.integrity,
    required this.availability,
    required this.compatibility,
    required this.collectedAt,
    this.provenanceReference,
    this.authorityReference,
    this.expiresAt,
    this.limitations = const [],
    this.metadata = const {},
  });

  final ReleaseEvidenceArtifactReference artifactReference;
  final ReleaseEvidenceSubject subject;
  final ReleaseEvidenceClass evidenceClass;
  final ReleaseEvidenceRole evidenceRole;
  final ReleaseEvidenceIntegrity integrity;
  final ReleaseEvidenceAvailabilityStatus availability;
  final ReleaseEvidenceCompatibilityStatus compatibility;
  final String? provenanceReference;
  final String? authorityReference;
  final String collectedAt;
  final String? expiresAt;
  final List<String> limitations;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'artifactReference': artifactReference.toJson(),
        'subject': subject.toJson(),
        'evidenceClass': evidenceClass.wireName,
        'evidenceRole': evidenceRole.wireName,
        'integrity': integrity.toJson(),
        'availability': availability.wireName,
        'compatibility': compatibility.wireName,
        if (provenanceReference != null)
          'provenanceReference': provenanceReference,
        if (authorityReference != null)
          'authorityReference': authorityReference,
        'collectedAt': collectedAt,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (limitations.isNotEmpty) 'limitations': limitations,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseEvidenceArtifact.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceArtifact(
      artifactReference: ReleaseEvidenceArtifactReference.fromJson(
        json['artifactReference'] as Map<String, dynamic>,
      ),
      subject: ReleaseEvidenceSubject.fromJson(
        json['subject'] as Map<String, dynamic>,
      ),
      evidenceClass: ReleaseEvidenceClassX.fromWireName(
        json['evidenceClass'] as String,
      ),
      evidenceRole: ReleaseEvidenceRoleX.fromWireName(
        json['evidenceRole'] as String,
      ),
      integrity: ReleaseEvidenceIntegrity.fromJson(
        json['integrity'] as Map<String, dynamic>,
      ),
      availability: ReleaseEvidenceAvailabilityStatusX.fromWireName(
        json['availability'] as String,
      ),
      compatibility: ReleaseEvidenceCompatibilityStatusX.fromWireName(
        json['compatibility'] as String,
      ),
      provenanceReference: json['provenanceReference'] as String?,
      authorityReference: json['authorityReference'] as String?,
      collectedAt: json['collectedAt'] as String,
      expiresAt: json['expiresAt'] as String?,
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceArtifact &&
          runtimeType == other.runtimeType &&
          artifactReference == other.artifactReference &&
          subject == other.subject &&
          evidenceClass == other.evidenceClass &&
          evidenceRole == other.evidenceRole &&
          integrity == other.integrity &&
          availability == other.availability &&
          compatibility == other.compatibility &&
          provenanceReference == other.provenanceReference &&
          authorityReference == other.authorityReference &&
          collectedAt == other.collectedAt &&
          expiresAt == other.expiresAt &&
          _listEquals(limitations, other.limitations) &&
          _mapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        artifactReference,
        subject,
        evidenceClass,
        evidenceRole,
        integrity,
        availability,
        compatibility,
        provenanceReference,
        authorityReference,
        collectedAt,
        expiresAt,
        Object.hashAll(limitations),
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
