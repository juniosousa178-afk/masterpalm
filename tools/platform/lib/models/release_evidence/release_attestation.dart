import 'release_evidence_enums.dart';
import 'release_attestation_authority.dart';
import 'release_attestation_issuer.dart';
import 'release_attestation_metadata.dart';
import 'release_attestation_predicate.dart';
import 'release_attestation_statement.dart';
import 'release_attestation_subject.dart';
import 'release_evidence_reference.dart';
import 'release_signature_reference.dart';

/// Immutable published attestation record.
class ReleaseAttestation {
  const ReleaseAttestation({
    required this.metadata,
    required this.statement,
    required this.subjects,
    required this.predicate,
    required this.issuer,
    required this.authority,
    required this.status,
    required this.issuedAt,
    required this.validFrom,
    required this.evidenceReferences,
    required this.fingerprint,
    required this.schemaVersion,
    this.expiresAt,
    this.provenanceReferences = const [],
    this.signatureReference,
    this.verificationReference,
    this.sourceReference,
    this.limitations = const [],
    this.metadataExtensions = const {},
  });

  final ReleaseAttestationMetadata metadata;
  final ReleaseAttestationStatement statement;
  final List<ReleaseAttestationSubject> subjects;
  final ReleaseAttestationPredicate predicate;
  final ReleaseAttestationIssuer issuer;
  final ReleaseAttestationAuthority authority;
  final ReleaseAttestationStatus status;
  final String issuedAt;
  final String validFrom;
  final String? expiresAt;
  final List<ReleaseEvidenceReference> evidenceReferences;
  final List<String> provenanceReferences;
  final ReleaseSignatureReference? signatureReference;
  final String? verificationReference;
  final ReleaseEvidenceReference? sourceReference;
  final String fingerprint;
  final int schemaVersion;
  final List<String> limitations;
  final Map<String, String> metadataExtensions;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'statement': statement.toJson(),
        'subjects': subjects.map((e) => e.toJson()).toList(),
        'predicate': predicate.toJson(),
        'issuer': issuer.toJson(),
        'authority': authority.toJson(),
        'status': status.wireName,
        'issuedAt': issuedAt,
        'validFrom': validFrom,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (evidenceReferences.isNotEmpty)
          'evidenceReferences':
              evidenceReferences.map((e) => e.toJson()).toList(),
        if (provenanceReferences.isNotEmpty)
          'provenanceReferences': provenanceReferences,
        if (signatureReference != null)
          'signatureReference': signatureReference!.toJson(),
        if (verificationReference != null)
          'verificationReference': verificationReference,
        if (sourceReference != null)
          'sourceReference': sourceReference!.toJson(),
        'fingerprint': fingerprint,
        'schemaVersion': schemaVersion,
        if (limitations.isNotEmpty) 'limitations': limitations,
        if (metadataExtensions.isNotEmpty)
          'metadataExtensions': metadataExtensions,
      };

  factory ReleaseAttestation.fromJson(Map<String, dynamic> json) {
    return ReleaseAttestation(
      metadata: ReleaseAttestationMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      statement: ReleaseAttestationStatement.fromJson(
        json['statement'] as Map<String, dynamic>,
      ),
      subjects: List.unmodifiable(
        (json['subjects'] as List<dynamic>)
            .map(
              (e) => ReleaseAttestationSubject.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      predicate: ReleaseAttestationPredicate.fromJson(
        json['predicate'] as Map<String, dynamic>,
      ),
      issuer: ReleaseAttestationIssuer.fromJson(
        json['issuer'] as Map<String, dynamic>,
      ),
      authority: ReleaseAttestationAuthority.fromJson(
        json['authority'] as Map<String, dynamic>,
      ),
      status: ReleaseAttestationStatusX.fromWireName(json['status'] as String),
      issuedAt: json['issuedAt'] as String,
      validFrom: json['validFrom'] as String,
      expiresAt: json['expiresAt'] as String?,
      evidenceReferences: List.unmodifiable(
        (json['evidenceReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => ReleaseEvidenceReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      provenanceReferences: List.unmodifiable(
        (json['provenanceReferences'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      signatureReference: json['signatureReference'] == null
          ? null
          : ReleaseSignatureReference.fromJson(
              json['signatureReference'] as Map<String, dynamic>,
            ),
      verificationReference: json['verificationReference'] as String?,
      sourceReference: json['sourceReference'] == null
          ? null
          : ReleaseEvidenceReference.fromJson(
              json['sourceReference'] as Map<String, dynamic>,
            ),
      fingerprint: json['fingerprint'] as String,
      schemaVersion: json['schemaVersion'] as int,
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      metadataExtensions: Map.unmodifiable(
        (json['metadataExtensions'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }
}
