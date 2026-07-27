import 'cryptographic_attestation_models.dart';
import 'cryptographic_key_reference.dart';
import 'cryptographic_revocation_record.dart';
import 'cryptographic_signature_envelope.dart';
import 'cryptographic_transparency_log_reference.dart';
import 'cryptographic_trust_anchor.dart';
import 'cryptographic_trust_chain.dart';
import 'cryptographic_trust_digest.dart';
import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_policy.dart';
import 'cryptographic_trust_source_reference.dart';
import 'cryptographic_trust_subject.dart';
import 'cryptographic_verification_models.dart';

/// Material collected for cryptographic trust evaluation.
///
/// Collection preserves upstream fingerprints and does not mutate inputs.
class CollectedCryptographicTrustMaterial {
  const CollectedCryptographicTrustMaterial({
    this.subjects = const [],
    this.digests = const [],
    this.keyReferences = const [],
    this.signatures = const [],
    this.attestations = const [],
    this.trustAnchors = const [],
    this.policies = const [],
    this.revocations = const [],
    this.transparencyLogReferences = const [],
    this.trustChains = const [],
    this.verificationRequests = const [],
    this.sourceReferences = const [],
    this.metadata = const {},
  });

  final List<CryptographicTrustSubject> subjects;
  final List<CryptographicDigest> digests;
  final List<CryptographicKeyReference> keyReferences;
  final List<CryptographicSignatureEnvelope> signatures;
  final List<CryptographicAttestationStatement> attestations;
  final List<CryptographicTrustAnchorReference> trustAnchors;
  final List<CryptographicTrustPolicy> policies;
  final List<CryptographicRevocationRecord> revocations;
  final List<CryptographicTransparencyLogReference> transparencyLogReferences;
  final List<CryptographicTrustChain> trustChains;
  final List<CryptographicVerificationRequest> verificationRequests;
  final List<CryptographicTrustSourceReference> sourceReferences;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
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
        if (policies.isNotEmpty)
          'policies': policies.map((e) => e.toJson()).toList(),
        if (revocations.isNotEmpty)
          'revocations': revocations.map((e) => e.toJson()).toList(),
        if (transparencyLogReferences.isNotEmpty)
          'transparencyLogReferences':
              transparencyLogReferences.map((e) => e.toJson()).toList(),
        if (trustChains.isNotEmpty)
          'trustChains': trustChains.map((e) => e.toJson()).toList(),
        if (verificationRequests.isNotEmpty)
          'verificationRequests':
              verificationRequests.map((e) => e.toJson()).toList(),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CollectedCryptographicTrustMaterial.fromJson(
    Map<String, dynamic> json,
  ) {
    return CollectedCryptographicTrustMaterial(
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
      policies: List.unmodifiable(
        (json['policies'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicTrustPolicy.fromJson(
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
      trustChains: List.unmodifiable(
        (json['trustChains'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicTrustChain.fromJson(
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
        if (policies.isNotEmpty)
          'policies': (policies.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) =>
                  a['policyId'].toString().compareTo(b['policyId'].toString()),
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
        if (trustChains.isNotEmpty)
          'trustChains': (trustChains.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) =>
                  a['chainId'].toString().compareTo(b['chainId'].toString()),
            )),
        if (verificationRequests.isNotEmpty)
          'verificationRequests':
              (verificationRequests.map((e) => e.toComparableJson()).toList()
                ..sort(
                  (a, b) => a['requestId']
                      .toString()
                      .compareTo(b['requestId'].toString()),
                )),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': (sourceReferences
              .map((e) => e.toComparableJson())
              .toList()
            ..sort(
              (a, b) =>
                  a['sourceId'].toString().compareTo(b['sourceId'].toString()),
            )),
      };

  CollectedCryptographicTrustMaterial copyWith({
    List<CryptographicTrustSubject>? subjects,
    List<CryptographicDigest>? digests,
    List<CryptographicKeyReference>? keyReferences,
    List<CryptographicSignatureEnvelope>? signatures,
    List<CryptographicAttestationStatement>? attestations,
    List<CryptographicTrustAnchorReference>? trustAnchors,
    List<CryptographicTrustPolicy>? policies,
    List<CryptographicRevocationRecord>? revocations,
    List<CryptographicTransparencyLogReference>? transparencyLogReferences,
    List<CryptographicTrustChain>? trustChains,
    List<CryptographicVerificationRequest>? verificationRequests,
    List<CryptographicTrustSourceReference>? sourceReferences,
    Map<String, String>? metadata,
  }) {
    return CollectedCryptographicTrustMaterial(
      subjects: subjects ?? this.subjects,
      digests: digests ?? this.digests,
      keyReferences: keyReferences ?? this.keyReferences,
      signatures: signatures ?? this.signatures,
      attestations: attestations ?? this.attestations,
      trustAnchors: trustAnchors ?? this.trustAnchors,
      policies: policies ?? this.policies,
      revocations: revocations ?? this.revocations,
      transparencyLogReferences:
          transparencyLogReferences ?? this.transparencyLogReferences,
      trustChains: trustChains ?? this.trustChains,
      verificationRequests: verificationRequests ?? this.verificationRequests,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CollectedCryptographicTrustMaterial &&
          trustListEquals(subjects, other.subjects) &&
          trustListEquals(digests, other.digests) &&
          trustListEquals(keyReferences, other.keyReferences) &&
          trustListEquals(signatures, other.signatures) &&
          trustListEquals(attestations, other.attestations) &&
          trustListEquals(trustAnchors, other.trustAnchors) &&
          trustListEquals(policies, other.policies) &&
          trustListEquals(revocations, other.revocations) &&
          trustListEquals(
            transparencyLogReferences,
            other.transparencyLogReferences,
          ) &&
          trustListEquals(trustChains, other.trustChains) &&
          trustListEquals(verificationRequests, other.verificationRequests) &&
          trustListEquals(sourceReferences, other.sourceReferences) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(subjects),
        Object.hashAll(digests),
        Object.hashAll(keyReferences),
        Object.hashAll(signatures),
        Object.hashAll(attestations),
        Object.hashAll(trustAnchors),
        Object.hashAll(policies),
        Object.hashAll(revocations),
        Object.hashAll(transparencyLogReferences),
        Object.hashAll(trustChains),
        Object.hashAll(verificationRequests),
        Object.hashAll(sourceReferences),
        Object.hashAll(metadata.entries),
      );
}
