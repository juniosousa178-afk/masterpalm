import 'release_evidence_enums.dart';

/// Structured normative claim within an attestation statement.
class ReleaseAttestationClaim {
  const ReleaseAttestationClaim({
    required this.claimKind,
    this.artifactId,
    this.artifactFingerprint,
    this.evidenceBundleId,
    this.evidenceBundleFingerprint,
    this.qualityGateSnapshotId,
    this.qualityGateFingerprint,
    this.qualityGateDecision,
    this.releaseDecisionSnapshotId,
    this.releaseDecisionFingerprint,
    this.releaseGovernanceDecision,
    this.approvalSetId,
    this.waiverSetId,
    this.provenanceId,
    this.provenanceFingerprint,
    this.completenessSatisfied,
    this.integritySatisfied,
    this.readinessSatisfied,
    this.authorizationConsistent,
    this.requiredCount,
    this.observedCount,
    this.complianceCode,
    this.attributes = const {},
  });

  final String claimKind;
  final String? artifactId;
  final String? artifactFingerprint;
  final String? evidenceBundleId;
  final String? evidenceBundleFingerprint;
  final String? qualityGateSnapshotId;
  final String? qualityGateFingerprint;
  final String? qualityGateDecision;
  final String? releaseDecisionSnapshotId;
  final String? releaseDecisionFingerprint;
  final String? releaseGovernanceDecision;
  final String? approvalSetId;
  final String? waiverSetId;
  final String? provenanceId;
  final String? provenanceFingerprint;
  final bool? completenessSatisfied;
  final bool? integritySatisfied;
  final bool? readinessSatisfied;
  final bool? authorizationConsistent;
  final int? requiredCount;
  final int? observedCount;
  final String? complianceCode;
  final Map<String, String> attributes;

  Map<String, dynamic> toJson() => {
        'claimKind': claimKind,
        if (artifactId != null) 'artifactId': artifactId,
        if (artifactFingerprint != null)
          'artifactFingerprint': artifactFingerprint,
        if (evidenceBundleId != null) 'evidenceBundleId': evidenceBundleId,
        if (evidenceBundleFingerprint != null)
          'evidenceBundleFingerprint': evidenceBundleFingerprint,
        if (qualityGateSnapshotId != null)
          'qualityGateSnapshotId': qualityGateSnapshotId,
        if (qualityGateFingerprint != null)
          'qualityGateFingerprint': qualityGateFingerprint,
        if (qualityGateDecision != null)
          'qualityGateDecision': qualityGateDecision,
        if (releaseDecisionSnapshotId != null)
          'releaseDecisionSnapshotId': releaseDecisionSnapshotId,
        if (releaseDecisionFingerprint != null)
          'releaseDecisionFingerprint': releaseDecisionFingerprint,
        if (releaseGovernanceDecision != null)
          'releaseGovernanceDecision': releaseGovernanceDecision,
        if (approvalSetId != null) 'approvalSetId': approvalSetId,
        if (waiverSetId != null) 'waiverSetId': waiverSetId,
        if (provenanceId != null) 'provenanceId': provenanceId,
        if (provenanceFingerprint != null)
          'provenanceFingerprint': provenanceFingerprint,
        if (completenessSatisfied != null)
          'completenessSatisfied': completenessSatisfied,
        if (integritySatisfied != null)
          'integritySatisfied': integritySatisfied,
        if (readinessSatisfied != null)
          'readinessSatisfied': readinessSatisfied,
        if (authorizationConsistent != null)
          'authorizationConsistent': authorizationConsistent,
        if (requiredCount != null) 'requiredCount': requiredCount,
        if (observedCount != null) 'observedCount': observedCount,
        if (complianceCode != null) 'complianceCode': complianceCode,
        if (attributes.isNotEmpty) 'attributes': attributes,
      };

  factory ReleaseAttestationClaim.fromJson(Map<String, dynamic> json) {
    return ReleaseAttestationClaim(
      claimKind: json['claimKind'] as String,
      artifactId: json['artifactId'] as String?,
      artifactFingerprint: json['artifactFingerprint'] as String?,
      evidenceBundleId: json['evidenceBundleId'] as String?,
      evidenceBundleFingerprint: json['evidenceBundleFingerprint'] as String?,
      qualityGateSnapshotId: json['qualityGateSnapshotId'] as String?,
      qualityGateFingerprint: json['qualityGateFingerprint'] as String?,
      qualityGateDecision: json['qualityGateDecision'] as String?,
      releaseDecisionSnapshotId: json['releaseDecisionSnapshotId'] as String?,
      releaseDecisionFingerprint: json['releaseDecisionFingerprint'] as String?,
      releaseGovernanceDecision: json['releaseGovernanceDecision'] as String?,
      approvalSetId: json['approvalSetId'] as String?,
      waiverSetId: json['waiverSetId'] as String?,
      provenanceId: json['provenanceId'] as String?,
      provenanceFingerprint: json['provenanceFingerprint'] as String?,
      completenessSatisfied: json['completenessSatisfied'] as bool?,
      integritySatisfied: json['integritySatisfied'] as bool?,
      readinessSatisfied: json['readinessSatisfied'] as bool?,
      authorizationConsistent: json['authorizationConsistent'] as bool?,
      requiredCount: json['requiredCount'] as int?,
      observedCount: json['observedCount'] as int?,
      complianceCode: json['complianceCode'] as String?,
      attributes: Map.unmodifiable(
        (json['attributes'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }
}

/// Normative statement within an attestation.
class ReleaseAttestationStatement {
  const ReleaseAttestationStatement({
    required this.statementId,
    required this.statementType,
    required this.predicateType,
    required this.predicateVersion,
    required this.claim,
    required this.outcome,
    required this.confidence,
    required this.issuedUnderPolicy,
    required this.evidenceBasis,
    required this.fingerprint,
    this.limitations = const [],
  });

  final String statementId;
  final String statementType;
  final ReleaseAttestationPredicateType predicateType;
  final String predicateVersion;
  final ReleaseAttestationClaim claim;
  final String outcome;
  final double confidence;
  final String issuedUnderPolicy;
  final List<String> evidenceBasis;
  final List<String> limitations;
  final String fingerprint;

  Map<String, dynamic> toJson() => {
        'statementId': statementId,
        'statementType': statementType,
        'predicateType': predicateType.wireName,
        'predicateVersion': predicateVersion,
        'claim': claim.toJson(),
        'outcome': outcome,
        'confidence': confidence,
        'issuedUnderPolicy': issuedUnderPolicy,
        if (evidenceBasis.isNotEmpty) 'evidenceBasis': evidenceBasis,
        if (limitations.isNotEmpty) 'limitations': limitations,
        'fingerprint': fingerprint,
      };

  factory ReleaseAttestationStatement.fromJson(Map<String, dynamic> json) {
    return ReleaseAttestationStatement(
      statementId: json['statementId'] as String,
      statementType: json['statementType'] as String,
      predicateType: ReleaseAttestationPredicateTypeX.fromWireName(
        json['predicateType'] as String,
      ),
      predicateVersion: json['predicateVersion'] as String,
      claim: ReleaseAttestationClaim.fromJson(
        json['claim'] as Map<String, dynamic>,
      ),
      outcome: json['outcome'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      issuedUnderPolicy: json['issuedUnderPolicy'] as String,
      evidenceBasis: List.unmodifiable(
        (json['evidenceBasis'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      fingerprint: json['fingerprint'] as String,
    );
  }
}
