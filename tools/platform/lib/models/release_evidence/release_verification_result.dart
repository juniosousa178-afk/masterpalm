import 'release_evidence_compatibility.dart';
import 'release_evidence_enums.dart';
import 'release_evidence_messages.dart';
import 'release_evidence_subject.dart';
import 'release_verification_check.dart';
import 'release_verification_policy.dart';

/// Result of structural and normative verification of release evidence.
class ReleaseVerificationResult {
  ReleaseVerificationResult({
    required this.verificationId,
    required this.subject,
    required this.policyReference,
    required this.status,
    required this.compatibility,
    required this.eligibility,
    required this.coverage,
    required this.evaluatedAt,
    required this.referenceTime,
    required this.fingerprint,
    required this.schemaVersion,
    List<ReleaseVerificationCheck> checks = const [],
    List<String> verifiedEvidenceIds = const [],
    List<String> rejectedEvidenceIds = const [],
    List<String> verifiedAttestationIds = const [],
    List<String> rejectedAttestationIds = const [],
    List<ReleaseEvidenceExplanation> explanations = const [],
    List<ReleaseEvidenceWarning> warnings = const [],
    List<ReleaseEvidenceError> errors = const [],
    List<ReleaseEvidenceLimitation> limitations = const [],
  })  : checks = List.unmodifiable(checks),
        verifiedEvidenceIds = List.unmodifiable(verifiedEvidenceIds),
        rejectedEvidenceIds = List.unmodifiable(rejectedEvidenceIds),
        verifiedAttestationIds = List.unmodifiable(verifiedAttestationIds),
        rejectedAttestationIds = List.unmodifiable(rejectedAttestationIds),
        explanations = List.unmodifiable(explanations),
        warnings = List.unmodifiable(warnings),
        errors = List.unmodifiable(errors),
        limitations = List.unmodifiable(limitations);

  final String verificationId;
  final ReleaseEvidenceSubject subject;
  final ReleaseVerificationPolicyReference policyReference;
  final ReleaseVerificationStatus status;
  final List<ReleaseVerificationCheck> checks;
  final ReleaseEvidenceCompatibility compatibility;
  final ReleaseEvidenceEligibility eligibility;
  final ReleaseEvidenceCoverage coverage;
  final List<String> verifiedEvidenceIds;
  final List<String> rejectedEvidenceIds;
  final List<String> verifiedAttestationIds;
  final List<String> rejectedAttestationIds;
  final List<ReleaseEvidenceExplanation> explanations;
  final List<ReleaseEvidenceWarning> warnings;
  final List<ReleaseEvidenceError> errors;
  final List<ReleaseEvidenceLimitation> limitations;
  final String evaluatedAt;
  final String referenceTime;
  final String fingerprint;
  final int schemaVersion;

  Map<String, dynamic> toJson() => {
        'verificationId': verificationId,
        'subject': subject.toJson(),
        'policyReference': policyReference.toJson(),
        'status': status.wireName,
        'checks': checks.map((e) => e.toJson()).toList(),
        'compatibility': compatibility.toJson(),
        'eligibility': eligibility.toJson(),
        'coverage': coverage.toJson(),
        if (verifiedEvidenceIds.isNotEmpty)
          'verifiedEvidenceIds': verifiedEvidenceIds,
        if (rejectedEvidenceIds.isNotEmpty)
          'rejectedEvidenceIds': rejectedEvidenceIds,
        if (verifiedAttestationIds.isNotEmpty)
          'verifiedAttestationIds': verifiedAttestationIds,
        if (rejectedAttestationIds.isNotEmpty)
          'rejectedAttestationIds': rejectedAttestationIds,
        if (explanations.isNotEmpty)
          'explanations': explanations.map((e) => e.toJson()).toList(),
        if (warnings.isNotEmpty)
          'warnings': warnings.map((e) => e.toJson()).toList(),
        if (errors.isNotEmpty) 'errors': errors.map((e) => e.toJson()).toList(),
        if (limitations.isNotEmpty)
          'limitations': limitations.map((e) => e.toJson()).toList(),
        'evaluatedAt': evaluatedAt,
        'referenceTime': referenceTime,
        'fingerprint': fingerprint,
        'schemaVersion': schemaVersion,
      };

  factory ReleaseVerificationResult.fromJson(Map<String, dynamic> json) {
    return ReleaseVerificationResult(
      verificationId: json['verificationId'] as String,
      subject: ReleaseEvidenceSubject.fromJson(
        json['subject'] as Map<String, dynamic>,
      ),
      policyReference: ReleaseVerificationPolicyReference.fromJson(
        json['policyReference'] as Map<String, dynamic>,
      ),
      status: ReleaseVerificationStatusX.fromWireName(
        json['status'] as String,
      ),
      checks: (json['checks'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseVerificationCheck.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      compatibility: ReleaseEvidenceCompatibility.fromJson(
        json['compatibility'] as Map<String, dynamic>,
      ),
      eligibility: ReleaseEvidenceEligibility.fromJson(
        json['eligibility'] as Map<String, dynamic>,
      ),
      coverage: ReleaseEvidenceCoverage.fromJson(
        json['coverage'] as Map<String, dynamic>,
      ),
      verifiedEvidenceIds: (json['verifiedEvidenceIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      rejectedEvidenceIds: (json['rejectedEvidenceIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      verifiedAttestationIds:
          (json['verifiedAttestationIds'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
      rejectedAttestationIds:
          (json['rejectedAttestationIds'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
      explanations: (json['explanations'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseEvidenceExplanation.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseEvidenceWarning.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      errors: (json['errors'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseEvidenceError.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseEvidenceLimitation.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      evaluatedAt: json['evaluatedAt'] as String,
      referenceTime: json['referenceTime'] as String,
      fingerprint: json['fingerprint'] as String,
      schemaVersion: json['schemaVersion'] as int,
    );
  }
}
