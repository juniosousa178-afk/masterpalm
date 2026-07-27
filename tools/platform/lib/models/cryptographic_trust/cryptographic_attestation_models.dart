import 'cryptographic_signature_envelope.dart';
import 'cryptographic_signer_identity.dart';
import 'cryptographic_trust_digest.dart';
import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_enums.dart';
import 'cryptographic_trust_source_reference.dart';

/// Subject bound by a cryptographic attestation statement.
///
/// Attestation does not authorize release and does not prove claim truth.
class CryptographicAttestationSubject {
  const CryptographicAttestationSubject({
    required this.subjectId,
    required this.subjectType,
    required this.subjectFingerprint,
    required this.projectId,
    this.digest,
    this.releaseId,
    this.artifactId,
    this.metadata = const {},
  });

  final String subjectId;
  final CryptographicTrustSubjectType subjectType;
  final String subjectFingerprint;
  final CryptographicDigest? digest;
  final String projectId;
  final String? releaseId;
  final String? artifactId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'subjectType': subjectType.wireName,
        'subjectFingerprint': subjectFingerprint,
        if (digest != null) 'digest': digest!.toJson(),
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (artifactId != null) 'artifactId': artifactId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicAttestationSubject.fromJson(Map<String, dynamic> json) {
    return CryptographicAttestationSubject(
      subjectId: json['subjectId'] as String,
      subjectType: CryptographicTrustSubjectTypeX.fromWireName(
        json['subjectType'] as String,
      ),
      subjectFingerprint: json['subjectFingerprint'] as String,
      digest: json['digest'] == null
          ? null
          : CryptographicDigest.fromJson(
              json['digest'] as Map<String, dynamic>,
            ),
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      artifactId: json['artifactId'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'subjectId': subjectId,
        'subjectType': subjectType.wireName,
        'subjectFingerprint': subjectFingerprint,
        if (digest != null) 'digest': digest!.toComparableJson(),
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (artifactId != null) 'artifactId': artifactId,
      };

  CryptographicAttestationSubject copyWith({
    String? subjectId,
    CryptographicTrustSubjectType? subjectType,
    String? subjectFingerprint,
    CryptographicDigest? digest,
    String? projectId,
    String? releaseId,
    String? artifactId,
    Map<String, String>? metadata,
  }) {
    return CryptographicAttestationSubject(
      subjectId: subjectId ?? this.subjectId,
      subjectType: subjectType ?? this.subjectType,
      subjectFingerprint: subjectFingerprint ?? this.subjectFingerprint,
      digest: digest ?? this.digest,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      artifactId: artifactId ?? this.artifactId,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicAttestationSubject &&
          subjectId == other.subjectId &&
          subjectType == other.subjectType &&
          subjectFingerprint == other.subjectFingerprint &&
          digest == other.digest &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          artifactId == other.artifactId &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        subjectId,
        subjectType,
        subjectFingerprint,
        digest,
        projectId,
        releaseId,
        artifactId,
        Object.hashAll(metadata.entries),
      );
}

/// Declarative predicate for a cryptographic attestation.
///
/// Claims are data only — not executed, interpreted, or verified here.
class CryptographicAttestationPredicate {
  const CryptographicAttestationPredicate({
    required this.predicateType,
    required this.schemaVersion,
    this.claims = const {},
    this.sourceReferences = const [],
    this.metadata = const {},
  });

  final String predicateType;
  final int schemaVersion;
  final Map<String, String> claims;
  final List<CryptographicTrustSourceReference> sourceReferences;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'predicateType': predicateType,
        'schemaVersion': schemaVersion,
        if (claims.isNotEmpty) 'claims': claims,
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicAttestationPredicate.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicAttestationPredicate(
      predicateType: json['predicateType'] as String,
      schemaVersion: json['schemaVersion'] as int,
      claims: Map.unmodifiable(
        (json['claims'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      sourceReferences: List.unmodifiable(
        (json['sourceReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicTrustSourceReference.fromJson(
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
        'predicateType': predicateType,
        'schemaVersion': schemaVersion,
        if (claims.isNotEmpty)
          'claims': Map.fromEntries(
            claims.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': (sourceReferences
              .map((e) => e.toComparableJson())
              .toList()
            ..sort(
              (a, b) =>
                  a['sourceId'].toString().compareTo(b['sourceId'].toString()),
            )),
      };

  CryptographicAttestationPredicate copyWith({
    String? predicateType,
    int? schemaVersion,
    Map<String, String>? claims,
    List<CryptographicTrustSourceReference>? sourceReferences,
    Map<String, String>? metadata,
  }) {
    return CryptographicAttestationPredicate(
      predicateType: predicateType ?? this.predicateType,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      claims: claims ?? this.claims,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicAttestationPredicate &&
          predicateType == other.predicateType &&
          schemaVersion == other.schemaVersion &&
          trustMapEquals(claims, other.claims) &&
          trustListEquals(sourceReferences, other.sourceReferences) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        predicateType,
        schemaVersion,
        Object.hashAll(claims.entries),
        Object.hashAll(sourceReferences),
        Object.hashAll(metadata.entries),
      );
}

/// Cryptographic attestation already produced — not generated or verified here.
///
/// Attestation != Release Evidence. Verified status does not authorize release.
class CryptographicAttestationStatement {
  const CryptographicAttestationStatement({
    required this.attestationId,
    required this.attestationType,
    required this.schemaVersion,
    required this.subjects,
    required this.predicate,
    required this.issuerIdentity,
    required this.status,
    this.issuedAt,
    this.expiresAt,
    this.signatures = const [],
    this.sourceReferences = const [],
    this.metadata = const {},
  });

  final String attestationId;
  final CryptographicAttestationType attestationType;
  final int schemaVersion;
  final List<CryptographicAttestationSubject> subjects;
  final CryptographicAttestationPredicate predicate;
  final CryptographicSignerIdentity issuerIdentity;
  final String? issuedAt;
  final String? expiresAt;
  final List<CryptographicSignatureEnvelope> signatures;
  final CryptographicAttestationStatus status;
  final List<CryptographicTrustSourceReference> sourceReferences;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'attestationId': attestationId,
        'attestationType': attestationType.wireName,
        'schemaVersion': schemaVersion,
        'subjects': subjects.map((e) => e.toJson()).toList(),
        'predicate': predicate.toJson(),
        'issuerIdentity': issuerIdentity.toJson(),
        if (issuedAt != null) 'issuedAt': issuedAt,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (signatures.isNotEmpty)
          'signatures': signatures.map((e) => e.toJson()).toList(),
        'status': status.wireName,
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicAttestationStatement.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicAttestationStatement(
      attestationId: json['attestationId'] as String,
      attestationType: CryptographicAttestationTypeX.fromWireName(
        json['attestationType'] as String,
      ),
      schemaVersion: json['schemaVersion'] as int,
      subjects: List.unmodifiable(
        (json['subjects'] as List<dynamic>)
            .map(
              (e) => CryptographicAttestationSubject.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      predicate: CryptographicAttestationPredicate.fromJson(
        json['predicate'] as Map<String, dynamic>,
      ),
      issuerIdentity: CryptographicSignerIdentity.fromJson(
        json['issuerIdentity'] as Map<String, dynamic>,
      ),
      issuedAt: json['issuedAt'] as String?,
      expiresAt: json['expiresAt'] as String?,
      signatures: List.unmodifiable(
        (json['signatures'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicSignatureEnvelope.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      status: CryptographicAttestationStatusX.fromWireName(
        json['status'] as String,
      ),
      sourceReferences: List.unmodifiable(
        (json['sourceReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicTrustSourceReference.fromJson(
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
        'attestationId': attestationId,
        'attestationType': attestationType.wireName,
        'schemaVersion': schemaVersion,
        'subjects': (subjects.map((e) => e.toComparableJson()).toList()
          ..sort(
            (a, b) =>
                a['subjectId'].toString().compareTo(b['subjectId'].toString()),
          )),
        'predicate': predicate.toComparableJson(),
        'issuerIdentity': issuerIdentity.toComparableJson(),
        if (signatures.isNotEmpty)
          'signatures': (signatures.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => a['signatureId']
                  .toString()
                  .compareTo(b['signatureId'].toString()),
            )),
        'status': status.wireName,
        if (sourceReferences.isNotEmpty)
          'sourceReferences': (sourceReferences
              .map((e) => e.toComparableJson())
              .toList()
            ..sort(
              (a, b) =>
                  a['sourceId'].toString().compareTo(b['sourceId'].toString()),
            )),
      };

  CryptographicAttestationStatement copyWith({
    String? attestationId,
    CryptographicAttestationType? attestationType,
    int? schemaVersion,
    List<CryptographicAttestationSubject>? subjects,
    CryptographicAttestationPredicate? predicate,
    CryptographicSignerIdentity? issuerIdentity,
    String? issuedAt,
    String? expiresAt,
    List<CryptographicSignatureEnvelope>? signatures,
    CryptographicAttestationStatus? status,
    List<CryptographicTrustSourceReference>? sourceReferences,
    Map<String, String>? metadata,
  }) {
    return CryptographicAttestationStatement(
      attestationId: attestationId ?? this.attestationId,
      attestationType: attestationType ?? this.attestationType,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      subjects: subjects ?? this.subjects,
      predicate: predicate ?? this.predicate,
      issuerIdentity: issuerIdentity ?? this.issuerIdentity,
      issuedAt: issuedAt ?? this.issuedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      signatures: signatures ?? this.signatures,
      status: status ?? this.status,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicAttestationStatement &&
          attestationId == other.attestationId &&
          attestationType == other.attestationType &&
          schemaVersion == other.schemaVersion &&
          trustListEquals(subjects, other.subjects) &&
          predicate == other.predicate &&
          issuerIdentity == other.issuerIdentity &&
          issuedAt == other.issuedAt &&
          expiresAt == other.expiresAt &&
          trustListEquals(signatures, other.signatures) &&
          status == other.status &&
          trustListEquals(sourceReferences, other.sourceReferences) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        attestationId,
        attestationType,
        schemaVersion,
        Object.hashAll(subjects),
        predicate,
        issuerIdentity,
        issuedAt,
        expiresAt,
        Object.hashAll(signatures),
        status,
        Object.hashAll(sourceReferences),
        Object.hashAll(metadata.entries),
      );
}
