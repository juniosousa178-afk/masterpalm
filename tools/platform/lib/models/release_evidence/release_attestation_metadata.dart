import 'release_evidence_enums.dart';

/// Metadata for a published attestation.
class ReleaseAttestationMetadata {
  const ReleaseAttestationMetadata({
    required this.attestationId,
    required this.attestationType,
    required this.policyId,
    required this.policyVersion,
    required this.policyFingerprint,
    required this.projectId,
    required this.schemaVersion,
    required this.predicateType,
    required this.predicateVersion,
    required this.canonicalizationVersion,
    required this.calculationVersion,
    required this.createdAt,
    required this.fingerprint,
    this.releaseId,
    this.commitId,
  });

  final String attestationId;
  final ReleaseAttestationType attestationType;
  final String policyId;
  final int policyVersion;
  final String policyFingerprint;
  final String projectId;
  final String? releaseId;
  final String? commitId;
  final int schemaVersion;
  final ReleaseAttestationPredicateType predicateType;
  final String predicateVersion;
  final int canonicalizationVersion;
  final int calculationVersion;
  final String createdAt;
  final String fingerprint;

  Map<String, dynamic> toJson() => {
        'attestationId': attestationId,
        'attestationType': attestationType.wireName,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'policyFingerprint': policyFingerprint,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        'schemaVersion': schemaVersion,
        'predicateType': predicateType.wireName,
        'predicateVersion': predicateVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'calculationVersion': calculationVersion,
        'createdAt': createdAt,
        'fingerprint': fingerprint,
      };

  factory ReleaseAttestationMetadata.fromJson(Map<String, dynamic> json) {
    return ReleaseAttestationMetadata(
      attestationId: json['attestationId'] as String,
      attestationType: ReleaseAttestationTypeX.fromWireName(
        json['attestationType'] as String,
      ),
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      policyFingerprint: json['policyFingerprint'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      commitId: json['commitId'] as String?,
      schemaVersion: json['schemaVersion'] as int,
      predicateType: ReleaseAttestationPredicateTypeX.fromWireName(
        json['predicateType'] as String,
      ),
      predicateVersion: json['predicateVersion'] as String,
      canonicalizationVersion: json['canonicalizationVersion'] as int,
      calculationVersion: json['calculationVersion'] as int,
      createdAt: json['createdAt'] as String,
      fingerprint: json['fingerprint'] as String,
    );
  }
}
