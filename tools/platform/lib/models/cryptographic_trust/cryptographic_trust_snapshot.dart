import 'cryptographic_attestation_models.dart';
import 'cryptographic_key_reference.dart';
import 'cryptographic_revocation_record.dart';
import 'cryptographic_signature_envelope.dart';
import 'cryptographic_transparency_log_reference.dart';
import 'cryptographic_trust_anchor.dart';
import 'cryptographic_trust_chain.dart';
import 'cryptographic_trust_digest.dart';
import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_enums.dart';
import 'cryptographic_trust_identity.dart';
import 'cryptographic_trust_policy.dart';
import 'cryptographic_trust_source_reference.dart';
import 'cryptographic_trust_subject.dart';
import 'cryptographic_verification_models.dart';

/// Metadata for a published Cryptographic Trust snapshot.
class CryptographicTrustSnapshotMetadata {
  const CryptographicTrustSnapshotMetadata({
    required this.cryptographicTrustSnapshotId,
    required this.projectId,
    required this.schemaVersion,
    required this.canonicalizationVersion,
    required this.createdAt,
    required this.fingerprint,
    required this.status,
    this.releaseId,
    this.evaluatedAt,
    this.publishedAt,
    this.subjectsFingerprint,
    this.signaturesFingerprint,
    this.attestationsFingerprint,
    this.policiesFingerprint,
    this.trustChainsFingerprint,
    this.verificationFingerprint,
    this.limitations = const [],
  });

  static const int currentSchemaVersion = 1;
  static const int currentCanonicalizationVersion = 1;

  final String cryptographicTrustSnapshotId;
  final String projectId;
  final String? releaseId;
  final int schemaVersion;
  final int canonicalizationVersion;
  final String createdAt;
  final String? evaluatedAt;
  final String? publishedAt;
  final String fingerprint;
  final CryptographicTrustStatus status;
  final String? subjectsFingerprint;
  final String? signaturesFingerprint;
  final String? attestationsFingerprint;
  final String? policiesFingerprint;
  final String? trustChainsFingerprint;
  final String? verificationFingerprint;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'cryptographicTrustSnapshotId': cryptographicTrustSnapshotId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'schemaVersion': schemaVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'createdAt': createdAt,
        if (evaluatedAt != null) 'evaluatedAt': evaluatedAt,
        if (publishedAt != null) 'publishedAt': publishedAt,
        'fingerprint': fingerprint,
        'status': status.wireName,
        if (subjectsFingerprint != null)
          'subjectsFingerprint': subjectsFingerprint,
        if (signaturesFingerprint != null)
          'signaturesFingerprint': signaturesFingerprint,
        if (attestationsFingerprint != null)
          'attestationsFingerprint': attestationsFingerprint,
        if (policiesFingerprint != null)
          'policiesFingerprint': policiesFingerprint,
        if (trustChainsFingerprint != null)
          'trustChainsFingerprint': trustChainsFingerprint,
        if (verificationFingerprint != null)
          'verificationFingerprint': verificationFingerprint,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory CryptographicTrustSnapshotMetadata.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicTrustSnapshotMetadata(
      cryptographicTrustSnapshotId:
          json['cryptographicTrustSnapshotId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      canonicalizationVersion: json['canonicalizationVersion'] as int? ??
          currentCanonicalizationVersion,
      createdAt: json['createdAt'] as String,
      evaluatedAt: json['evaluatedAt'] as String?,
      publishedAt: json['publishedAt'] as String?,
      fingerprint: json['fingerprint'] as String,
      status: CryptographicTrustStatusX.fromWireName(
        json['status'] as String,
      ),
      subjectsFingerprint: json['subjectsFingerprint'] as String?,
      signaturesFingerprint: json['signaturesFingerprint'] as String?,
      attestationsFingerprint: json['attestationsFingerprint'] as String?,
      policiesFingerprint: json['policiesFingerprint'] as String?,
      trustChainsFingerprint: json['trustChainsFingerprint'] as String?,
      verificationFingerprint: json['verificationFingerprint'] as String?,
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'schemaVersion': schemaVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'status': status.wireName,
        if (subjectsFingerprint != null)
          'subjectsFingerprint': subjectsFingerprint,
        if (signaturesFingerprint != null)
          'signaturesFingerprint': signaturesFingerprint,
        if (attestationsFingerprint != null)
          'attestationsFingerprint': attestationsFingerprint,
        if (policiesFingerprint != null)
          'policiesFingerprint': policiesFingerprint,
        if (trustChainsFingerprint != null)
          'trustChainsFingerprint': trustChainsFingerprint,
        if (verificationFingerprint != null)
          'verificationFingerprint': verificationFingerprint,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  CryptographicTrustSnapshotMetadata copyWith({
    String? cryptographicTrustSnapshotId,
    String? projectId,
    String? releaseId,
    int? schemaVersion,
    int? canonicalizationVersion,
    String? createdAt,
    String? evaluatedAt,
    String? publishedAt,
    String? fingerprint,
    CryptographicTrustStatus? status,
    String? subjectsFingerprint,
    String? signaturesFingerprint,
    String? attestationsFingerprint,
    String? policiesFingerprint,
    String? trustChainsFingerprint,
    String? verificationFingerprint,
    List<String>? limitations,
  }) {
    return CryptographicTrustSnapshotMetadata(
      cryptographicTrustSnapshotId:
          cryptographicTrustSnapshotId ?? this.cryptographicTrustSnapshotId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      canonicalizationVersion:
          canonicalizationVersion ?? this.canonicalizationVersion,
      createdAt: createdAt ?? this.createdAt,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
      publishedAt: publishedAt ?? this.publishedAt,
      fingerprint: fingerprint ?? this.fingerprint,
      status: status ?? this.status,
      subjectsFingerprint: subjectsFingerprint ?? this.subjectsFingerprint,
      signaturesFingerprint:
          signaturesFingerprint ?? this.signaturesFingerprint,
      attestationsFingerprint:
          attestationsFingerprint ?? this.attestationsFingerprint,
      policiesFingerprint: policiesFingerprint ?? this.policiesFingerprint,
      trustChainsFingerprint:
          trustChainsFingerprint ?? this.trustChainsFingerprint,
      verificationFingerprint:
          verificationFingerprint ?? this.verificationFingerprint,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTrustSnapshotMetadata &&
          cryptographicTrustSnapshotId == other.cryptographicTrustSnapshotId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          schemaVersion == other.schemaVersion &&
          canonicalizationVersion == other.canonicalizationVersion &&
          createdAt == other.createdAt &&
          evaluatedAt == other.evaluatedAt &&
          publishedAt == other.publishedAt &&
          fingerprint == other.fingerprint &&
          status == other.status &&
          subjectsFingerprint == other.subjectsFingerprint &&
          signaturesFingerprint == other.signaturesFingerprint &&
          attestationsFingerprint == other.attestationsFingerprint &&
          policiesFingerprint == other.policiesFingerprint &&
          trustChainsFingerprint == other.trustChainsFingerprint &&
          verificationFingerprint == other.verificationFingerprint &&
          trustListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        cryptographicTrustSnapshotId,
        projectId,
        releaseId,
        schemaVersion,
        canonicalizationVersion,
        createdAt,
        evaluatedAt,
        publishedAt,
        fingerprint,
        status,
        subjectsFingerprint,
        signaturesFingerprint,
        attestationsFingerprint,
        policiesFingerprint,
        trustChainsFingerprint,
        verificationFingerprint,
        Object.hashAll(limitations),
      );
}

/// Published aggregate snapshot for Cryptographic Trust domain data.
///
/// Immutable descriptor only — no cryptographic operations or persistence.
class CryptographicTrustSnapshot {
  const CryptographicTrustSnapshot({
    required this.metadata,
    required this.fingerprint,
    required this.status,
    this.subjects = const [],
    this.digests = const [],
    this.keyReferences = const [],
    this.signatures = const [],
    this.attestations = const [],
    this.trustAnchors = const [],
    this.trustChains = const [],
    this.trustPolicies = const [],
    this.verificationRequests = const [],
    this.verificationResults = const [],
    this.revocations = const [],
    this.transparencyLogReferences = const [],
    this.sourceReferences = const [],
    this.identity,
    this.warnings = const [],
    this.limitations = const [],
    this.metadataMap = const {},
  });

  final CryptographicTrustSnapshotMetadata metadata;
  final String fingerprint;
  final CryptographicTrustStatus status;
  final List<CryptographicTrustSubject> subjects;
  final List<CryptographicDigest> digests;
  final List<CryptographicKeyReference> keyReferences;
  final List<CryptographicSignatureEnvelope> signatures;
  final List<CryptographicAttestationStatement> attestations;
  final List<CryptographicTrustAnchorReference> trustAnchors;
  final List<CryptographicTrustChain> trustChains;
  final List<CryptographicTrustPolicy> trustPolicies;
  final List<CryptographicVerificationRequest> verificationRequests;
  final List<CryptographicVerificationResult> verificationResults;
  final List<CryptographicRevocationRecord> revocations;
  final List<CryptographicTransparencyLogReference> transparencyLogReferences;
  final List<CryptographicTrustSourceReference> sourceReferences;
  final CryptographicTrustIdentity? identity;
  final List<String> warnings;
  final List<String> limitations;
  final Map<String, String> metadataMap;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'fingerprint': fingerprint,
        'status': status.wireName,
        if (subjects.isNotEmpty)
          'subjects': subjects.map((e) => e.toJson()).toList(),
        if (digests.isNotEmpty)
          'digests': digests.map((e) => e.toJson()).toList(),
        if (keyReferences.isNotEmpty)
          'keyReferences': keyReferences.map((e) => e.toJson()).toList(),
        if (signatures.isNotEmpty)
          'signatures': signatures.map((e) => e.toJson()).toList(),
        if (attestations.isNotEmpty)
          'attestations': attestations.map((e) => e.toJson()).toList(),
        if (trustAnchors.isNotEmpty)
          'trustAnchors': trustAnchors.map((e) => e.toJson()).toList(),
        if (trustChains.isNotEmpty)
          'trustChains': trustChains.map((e) => e.toJson()).toList(),
        if (trustPolicies.isNotEmpty)
          'trustPolicies': trustPolicies.map((e) => e.toJson()).toList(),
        if (verificationRequests.isNotEmpty)
          'verificationRequests':
              verificationRequests.map((e) => e.toJson()).toList(),
        if (verificationResults.isNotEmpty)
          'verificationResults':
              verificationResults.map((e) => e.toJson()).toList(),
        if (revocations.isNotEmpty)
          'revocations': revocations.map((e) => e.toJson()).toList(),
        if (transparencyLogReferences.isNotEmpty)
          'transparencyLogReferences':
              transparencyLogReferences.map((e) => e.toJson()).toList(),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        if (identity != null) 'identity': identity!.toJson(),
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (limitations.isNotEmpty) 'limitations': limitations,
        if (metadataMap.isNotEmpty) 'metadataMap': metadataMap,
      };

  factory CryptographicTrustSnapshot.fromJson(Map<String, dynamic> json) {
    return CryptographicTrustSnapshot(
      metadata: CryptographicTrustSnapshotMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      fingerprint: json['fingerprint'] as String,
      status: CryptographicTrustStatusX.fromWireName(
        json['status'] as String,
      ),
      subjects: List.unmodifiable(
        (json['subjects'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicTrustSubject.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      digests: List.unmodifiable(
        (json['digests'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicDigest.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
      keyReferences: List.unmodifiable(
        (json['keyReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicKeyReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      signatures: List.unmodifiable(
        (json['signatures'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicSignatureEnvelope.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      attestations: List.unmodifiable(
        (json['attestations'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicAttestationStatement.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      trustAnchors: List.unmodifiable(
        (json['trustAnchors'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicTrustAnchorReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      trustChains: List.unmodifiable(
        (json['trustChains'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicTrustChain.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      trustPolicies: List.unmodifiable(
        (json['trustPolicies'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicTrustPolicy.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      verificationRequests: List.unmodifiable(
        (json['verificationRequests'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicVerificationRequest.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      verificationResults: List.unmodifiable(
        (json['verificationResults'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicVerificationResult.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      revocations: List.unmodifiable(
        (json['revocations'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicRevocationRecord.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      transparencyLogReferences: List.unmodifiable(
        (json['transparencyLogReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicTransparencyLogReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
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
      identity: json['identity'] == null
          ? null
          : CryptographicTrustIdentity.fromJson(
              json['identity'] as Map<String, dynamic>,
            ),
      warnings: List.unmodifiable(
        (json['warnings'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      metadataMap: Map.unmodifiable(
        (json['metadataMap'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'metadata': metadata.toComparableJson(),
        'status': status.wireName,
        if (subjects.isNotEmpty)
          'subjects': (subjects.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => a['subjectId']
                  .toString()
                  .compareTo(b['subjectId'].toString()),
            )),
        if (digests.isNotEmpty)
          'digests': (digests.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => a['subjectId']
                  .toString()
                  .compareTo(b['subjectId'].toString()),
            )),
        if (keyReferences.isNotEmpty)
          'keyReferences': (keyReferences
              .map((e) => e.toComparableJson())
              .toList()
            ..sort(
              (a, b) => a['keyId'].toString().compareTo(b['keyId'].toString()),
            )),
        if (signatures.isNotEmpty)
          'signatures': (signatures.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => a['signatureId']
                  .toString()
                  .compareTo(b['signatureId'].toString()),
            )),
        if (attestations.isNotEmpty)
          'attestations':
              (attestations.map((e) => e.toComparableJson()).toList()
                ..sort(
                  (a, b) => a['attestationId']
                      .toString()
                      .compareTo(b['attestationId'].toString()),
                )),
        if (trustAnchors.isNotEmpty)
          'trustAnchors':
              (trustAnchors.map((e) => e.toComparableJson()).toList()
                ..sort(
                  (a, b) => a['trustAnchorId']
                      .toString()
                      .compareTo(b['trustAnchorId'].toString()),
                )),
        if (trustChains.isNotEmpty)
          'trustChains': (trustChains.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => a['trustChainId']
                  .toString()
                  .compareTo(b['trustChainId'].toString()),
            )),
        if (trustPolicies.isNotEmpty)
          'trustPolicies': (trustPolicies
              .map((e) => e.toComparableJson())
              .toList()
            ..sort(
              (a, b) =>
                  a['policyId'].toString().compareTo(b['policyId'].toString()),
            )),
        if (verificationRequests.isNotEmpty)
          'verificationRequests':
              (verificationRequests.map((e) => e.toComparableJson()).toList()
                ..sort(
                  (a, b) => a['requestId']
                      .toString()
                      .compareTo(b['requestId'].toString()),
                )),
        if (verificationResults.isNotEmpty)
          'verificationResults':
              (verificationResults.map((e) => e.toComparableJson()).toList()
                ..sort(
                  (a, b) => a['verificationId']
                      .toString()
                      .compareTo(b['verificationId'].toString()),
                )),
        if (revocations.isNotEmpty)
          'revocations': (revocations.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => a['revocationId']
                  .toString()
                  .compareTo(b['revocationId'].toString()),
            )),
        if (transparencyLogReferences.isNotEmpty)
          'transparencyLogReferences': (transparencyLogReferences
              .map((e) => e.toComparableJson())
              .toList()
            ..sort(
              (a, b) =>
                  a['entryId'].toString().compareTo(b['entryId'].toString()),
            )),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': (sourceReferences
              .map((e) => e.toComparableJson())
              .toList()
            ..sort(
              (a, b) =>
                  a['sourceId'].toString().compareTo(b['sourceId'].toString()),
            )),
        if (identity != null) 'identity': identity!.toComparableJson(),
        if (warnings.isNotEmpty)
          'warnings': List<String>.from(warnings)..sort(),
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  CryptographicTrustSnapshot copyWith({
    CryptographicTrustSnapshotMetadata? metadata,
    String? fingerprint,
    CryptographicTrustStatus? status,
    List<CryptographicTrustSubject>? subjects,
    List<CryptographicDigest>? digests,
    List<CryptographicKeyReference>? keyReferences,
    List<CryptographicSignatureEnvelope>? signatures,
    List<CryptographicAttestationStatement>? attestations,
    List<CryptographicTrustAnchorReference>? trustAnchors,
    List<CryptographicTrustChain>? trustChains,
    List<CryptographicTrustPolicy>? trustPolicies,
    List<CryptographicVerificationRequest>? verificationRequests,
    List<CryptographicVerificationResult>? verificationResults,
    List<CryptographicRevocationRecord>? revocations,
    List<CryptographicTransparencyLogReference>? transparencyLogReferences,
    List<CryptographicTrustSourceReference>? sourceReferences,
    CryptographicTrustIdentity? identity,
    List<String>? warnings,
    List<String>? limitations,
    Map<String, String>? metadataMap,
  }) {
    return CryptographicTrustSnapshot(
      metadata: metadata ?? this.metadata,
      fingerprint: fingerprint ?? this.fingerprint,
      status: status ?? this.status,
      subjects: subjects ?? this.subjects,
      digests: digests ?? this.digests,
      keyReferences: keyReferences ?? this.keyReferences,
      signatures: signatures ?? this.signatures,
      attestations: attestations ?? this.attestations,
      trustAnchors: trustAnchors ?? this.trustAnchors,
      trustChains: trustChains ?? this.trustChains,
      trustPolicies: trustPolicies ?? this.trustPolicies,
      verificationRequests: verificationRequests ?? this.verificationRequests,
      verificationResults: verificationResults ?? this.verificationResults,
      revocations: revocations ?? this.revocations,
      transparencyLogReferences:
          transparencyLogReferences ?? this.transparencyLogReferences,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      identity: identity ?? this.identity,
      warnings: warnings ?? this.warnings,
      limitations: limitations ?? this.limitations,
      metadataMap: metadataMap ?? this.metadataMap,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTrustSnapshot &&
          metadata == other.metadata &&
          fingerprint == other.fingerprint &&
          status == other.status &&
          trustListEquals(subjects, other.subjects) &&
          trustListEquals(digests, other.digests) &&
          trustListEquals(keyReferences, other.keyReferences) &&
          trustListEquals(signatures, other.signatures) &&
          trustListEquals(attestations, other.attestations) &&
          trustListEquals(trustAnchors, other.trustAnchors) &&
          trustListEquals(trustChains, other.trustChains) &&
          trustListEquals(trustPolicies, other.trustPolicies) &&
          trustListEquals(verificationRequests, other.verificationRequests) &&
          trustListEquals(verificationResults, other.verificationResults) &&
          trustListEquals(revocations, other.revocations) &&
          trustListEquals(
            transparencyLogReferences,
            other.transparencyLogReferences,
          ) &&
          trustListEquals(sourceReferences, other.sourceReferences) &&
          identity == other.identity &&
          trustListEquals(warnings, other.warnings) &&
          trustListEquals(limitations, other.limitations) &&
          trustMapEquals(metadataMap, other.metadataMap);

  @override
  int get hashCode => Object.hash(
        metadata,
        fingerprint,
        status,
        Object.hashAll(subjects),
        Object.hashAll(digests),
        Object.hashAll(keyReferences),
        Object.hashAll(signatures),
        Object.hashAll(attestations),
        Object.hashAll(trustAnchors),
        Object.hashAll(trustChains),
        Object.hashAll(trustPolicies),
        Object.hashAll(verificationRequests),
        Object.hashAll(verificationResults),
        Object.hashAll(revocations),
        Object.hashAll(transparencyLogReferences),
        Object.hashAll(sourceReferences),
        identity,
        Object.hashAll(warnings),
        Object.hashAll(limitations),
        Object.hashAll(metadataMap.entries),
      );
}
