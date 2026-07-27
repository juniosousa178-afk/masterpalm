import 'release_evidence_enums.dart';

/// Base class for typed attestation predicates.
abstract class ReleaseAttestationPredicate {
  const ReleaseAttestationPredicate({
    required this.predicateType,
    required this.predicateVersion,
    required this.result,
    required this.evidenceIds,
    required this.limitations,
    required this.fingerprint,
  });

  final ReleaseAttestationPredicateType predicateType;
  final String predicateVersion;
  final ReleaseAttestationPredicateResult result;
  final List<String> evidenceIds;
  final List<String> limitations;
  final String fingerprint;

  Map<String, dynamic> get expected;
  Map<String, dynamic> get observed;

  Map<String, dynamic> toJson() => {
        'predicateType': predicateType.wireName,
        'predicateVersion': predicateVersion,
        'expected': expected,
        'observed': observed,
        'result': result.wireName,
        if (evidenceIds.isNotEmpty) 'evidenceIds': evidenceIds,
        if (limitations.isNotEmpty) 'limitations': limitations,
        'fingerprint': fingerprint,
      };

  static ReleaseAttestationPredicate fromJson(Map<String, dynamic> json) {
    final type = ReleaseAttestationPredicateTypeX.fromWireName(
      json['predicateType'] as String,
    );
    switch (type) {
      case ReleaseAttestationPredicateType.evidenceBundle:
        return EvidenceBundlePredicate.fromJson(json);
      case ReleaseAttestationPredicateType.qualityGate:
        return QualityGatePredicate.fromJson(json);
      case ReleaseAttestationPredicateType.releaseDecision:
        return ReleaseDecisionPredicate.fromJson(json);
      case ReleaseAttestationPredicateType.approval:
        return ApprovalPredicate.fromJson(json);
      case ReleaseAttestationPredicateType.waiver:
        return WaiverPredicate.fromJson(json);
      case ReleaseAttestationPredicateType.provenance:
        return ProvenancePredicate.fromJson(json);
      case ReleaseAttestationPredicateType.artifactIntegrity:
        return ArtifactIntegrityPredicate.fromJson(json);
      case ReleaseAttestationPredicateType.readiness:
        return ReadinessPredicate.fromJson(json);
      case ReleaseAttestationPredicateType.compliance:
        return CompliancePredicate.fromJson(json);
      case ReleaseAttestationPredicateType.custom:
        return CustomPredicate.fromJson(json);
    }
  }
}

List<String> _unmodifiableStringList(dynamic value) => List.unmodifiable(
      (value as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
    );

Map<String, dynamic> _unmodifiableMap(dynamic value) => Map.unmodifiable(
      (value as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, v),
      ),
    );

class EvidenceBundlePredicate extends ReleaseAttestationPredicate {
  const EvidenceBundlePredicate({
    required super.predicateVersion,
    required super.result,
    required super.evidenceIds,
    required super.limitations,
    required super.fingerprint,
    required this.expectedBundleId,
    required this.expectedBundleFingerprint,
    required this.observedBundleId,
    required this.observedBundleFingerprint,
  }) : super(predicateType: ReleaseAttestationPredicateType.evidenceBundle);

  final String expectedBundleId;
  final String expectedBundleFingerprint;
  final String observedBundleId;
  final String observedBundleFingerprint;

  @override
  Map<String, dynamic> get expected => {
        'bundleId': expectedBundleId,
        'bundleFingerprint': expectedBundleFingerprint,
      };

  @override
  Map<String, dynamic> get observed => {
        'bundleId': observedBundleId,
        'bundleFingerprint': observedBundleFingerprint,
      };

  factory EvidenceBundlePredicate.fromJson(Map<String, dynamic> json) {
    final expected = json['expected'] as Map<String, dynamic>;
    final observed = json['observed'] as Map<String, dynamic>;
    return EvidenceBundlePredicate(
      predicateVersion: json['predicateVersion'] as String,
      result: ReleaseAttestationPredicateResultX.fromWireName(
        json['result'] as String,
      ),
      evidenceIds: _unmodifiableStringList(json['evidenceIds']),
      limitations: _unmodifiableStringList(json['limitations']),
      fingerprint: json['fingerprint'] as String,
      expectedBundleId: expected['bundleId'] as String,
      expectedBundleFingerprint: expected['bundleFingerprint'] as String,
      observedBundleId: observed['bundleId'] as String,
      observedBundleFingerprint: observed['bundleFingerprint'] as String,
    );
  }
}

class QualityGatePredicate extends ReleaseAttestationPredicate {
  const QualityGatePredicate({
    required super.predicateVersion,
    required super.result,
    required super.evidenceIds,
    required super.limitations,
    required super.fingerprint,
    required this.expectedSnapshotId,
    required this.expectedFingerprint,
    required this.expectedDecision,
    required this.observedSnapshotId,
    required this.observedFingerprint,
    required this.observedDecision,
  }) : super(predicateType: ReleaseAttestationPredicateType.qualityGate);

  final String expectedSnapshotId;
  final String expectedFingerprint;
  final String expectedDecision;
  final String observedSnapshotId;
  final String observedFingerprint;
  final String observedDecision;

  @override
  Map<String, dynamic> get expected => {
        'snapshotId': expectedSnapshotId,
        'fingerprint': expectedFingerprint,
        'decision': expectedDecision,
      };

  @override
  Map<String, dynamic> get observed => {
        'snapshotId': observedSnapshotId,
        'fingerprint': observedFingerprint,
        'decision': observedDecision,
      };

  factory QualityGatePredicate.fromJson(Map<String, dynamic> json) {
    final expected = json['expected'] as Map<String, dynamic>;
    final observed = json['observed'] as Map<String, dynamic>;
    return QualityGatePredicate(
      predicateVersion: json['predicateVersion'] as String,
      result: ReleaseAttestationPredicateResultX.fromWireName(
        json['result'] as String,
      ),
      evidenceIds: _unmodifiableStringList(json['evidenceIds']),
      limitations: _unmodifiableStringList(json['limitations']),
      fingerprint: json['fingerprint'] as String,
      expectedSnapshotId: expected['snapshotId'] as String,
      expectedFingerprint: expected['fingerprint'] as String,
      expectedDecision: expected['decision'] as String,
      observedSnapshotId: observed['snapshotId'] as String,
      observedFingerprint: observed['fingerprint'] as String,
      observedDecision: observed['decision'] as String,
    );
  }
}

class ReleaseDecisionPredicate extends ReleaseAttestationPredicate {
  const ReleaseDecisionPredicate({
    required super.predicateVersion,
    required super.result,
    required super.evidenceIds,
    required super.limitations,
    required super.fingerprint,
    required this.expectedSnapshotId,
    required this.expectedFingerprint,
    required this.expectedDecision,
    required this.observedSnapshotId,
    required this.observedFingerprint,
    required this.observedDecision,
  }) : super(predicateType: ReleaseAttestationPredicateType.releaseDecision);

  final String expectedSnapshotId;
  final String expectedFingerprint;
  final String expectedDecision;
  final String observedSnapshotId;
  final String observedFingerprint;
  final String observedDecision;

  @override
  Map<String, dynamic> get expected => {
        'snapshotId': expectedSnapshotId,
        'fingerprint': expectedFingerprint,
        'decision': expectedDecision,
      };

  @override
  Map<String, dynamic> get observed => {
        'snapshotId': observedSnapshotId,
        'fingerprint': observedFingerprint,
        'decision': observedDecision,
      };

  factory ReleaseDecisionPredicate.fromJson(Map<String, dynamic> json) {
    final expected = json['expected'] as Map<String, dynamic>;
    final observed = json['observed'] as Map<String, dynamic>;
    return ReleaseDecisionPredicate(
      predicateVersion: json['predicateVersion'] as String,
      result: ReleaseAttestationPredicateResultX.fromWireName(
        json['result'] as String,
      ),
      evidenceIds: _unmodifiableStringList(json['evidenceIds']),
      limitations: _unmodifiableStringList(json['limitations']),
      fingerprint: json['fingerprint'] as String,
      expectedSnapshotId: expected['snapshotId'] as String,
      expectedFingerprint: expected['fingerprint'] as String,
      expectedDecision: expected['decision'] as String,
      observedSnapshotId: observed['snapshotId'] as String,
      observedFingerprint: observed['fingerprint'] as String,
      observedDecision: observed['decision'] as String,
    );
  }
}

class ApprovalPredicate extends ReleaseAttestationPredicate {
  const ApprovalPredicate({
    required super.predicateVersion,
    required super.result,
    required super.evidenceIds,
    required super.limitations,
    required super.fingerprint,
    required this.expectedApprovalCount,
    required this.expectedApprovalTypes,
    required this.observedApprovalCount,
    required this.observedApprovalIds,
  }) : super(predicateType: ReleaseAttestationPredicateType.approval);

  final int expectedApprovalCount;
  final List<String> expectedApprovalTypes;
  final int observedApprovalCount;
  final List<String> observedApprovalIds;

  @override
  Map<String, dynamic> get expected => {
        'approvalCount': expectedApprovalCount,
        'approvalTypes': expectedApprovalTypes,
      };

  @override
  Map<String, dynamic> get observed => {
        'approvalCount': observedApprovalCount,
        'approvalIds': observedApprovalIds,
      };

  factory ApprovalPredicate.fromJson(Map<String, dynamic> json) {
    final expected = json['expected'] as Map<String, dynamic>;
    final observed = json['observed'] as Map<String, dynamic>;
    return ApprovalPredicate(
      predicateVersion: json['predicateVersion'] as String,
      result: ReleaseAttestationPredicateResultX.fromWireName(
        json['result'] as String,
      ),
      evidenceIds: _unmodifiableStringList(json['evidenceIds']),
      limitations: _unmodifiableStringList(json['limitations']),
      fingerprint: json['fingerprint'] as String,
      expectedApprovalCount: expected['approvalCount'] as int,
      expectedApprovalTypes: _unmodifiableStringList(expected['approvalTypes']),
      observedApprovalCount: observed['approvalCount'] as int,
      observedApprovalIds: _unmodifiableStringList(observed['approvalIds']),
    );
  }
}

class WaiverPredicate extends ReleaseAttestationPredicate {
  const WaiverPredicate({
    required super.predicateVersion,
    required super.result,
    required super.evidenceIds,
    required super.limitations,
    required super.fingerprint,
    required this.expectedWaiverCount,
    required this.observedWaiverCount,
    required this.observedWaiverIds,
  }) : super(predicateType: ReleaseAttestationPredicateType.waiver);

  final int expectedWaiverCount;
  final int observedWaiverCount;
  final List<String> observedWaiverIds;

  @override
  Map<String, dynamic> get expected => {
        'waiverCount': expectedWaiverCount,
      };

  @override
  Map<String, dynamic> get observed => {
        'waiverCount': observedWaiverCount,
        'waiverIds': observedWaiverIds,
      };

  factory WaiverPredicate.fromJson(Map<String, dynamic> json) {
    final expected = json['expected'] as Map<String, dynamic>;
    final observed = json['observed'] as Map<String, dynamic>;
    return WaiverPredicate(
      predicateVersion: json['predicateVersion'] as String,
      result: ReleaseAttestationPredicateResultX.fromWireName(
        json['result'] as String,
      ),
      evidenceIds: _unmodifiableStringList(json['evidenceIds']),
      limitations: _unmodifiableStringList(json['limitations']),
      fingerprint: json['fingerprint'] as String,
      expectedWaiverCount: expected['waiverCount'] as int,
      observedWaiverCount: observed['waiverCount'] as int,
      observedWaiverIds: _unmodifiableStringList(observed['waiverIds']),
    );
  }
}

class ProvenancePredicate extends ReleaseAttestationPredicate {
  const ProvenancePredicate({
    required super.predicateVersion,
    required super.result,
    required super.evidenceIds,
    required super.limitations,
    required super.fingerprint,
    required this.expectedProvenanceId,
    required this.expectedCompleteness,
    required this.observedProvenanceId,
    required this.requiredStepCount,
    required this.observedStepCount,
  }) : super(predicateType: ReleaseAttestationPredicateType.provenance);

  final String expectedProvenanceId;
  final bool expectedCompleteness;
  final String observedProvenanceId;
  final int requiredStepCount;
  final int observedStepCount;

  @override
  Map<String, dynamic> get expected => {
        'provenanceId': expectedProvenanceId,
        'completeness': expectedCompleteness,
      };

  @override
  Map<String, dynamic> get observed => {
        'provenanceId': observedProvenanceId,
        'requiredStepCount': requiredStepCount,
        'observedStepCount': observedStepCount,
      };

  factory ProvenancePredicate.fromJson(Map<String, dynamic> json) {
    final expected = json['expected'] as Map<String, dynamic>;
    final observed = json['observed'] as Map<String, dynamic>;
    return ProvenancePredicate(
      predicateVersion: json['predicateVersion'] as String,
      result: ReleaseAttestationPredicateResultX.fromWireName(
        json['result'] as String,
      ),
      evidenceIds: _unmodifiableStringList(json['evidenceIds']),
      limitations: _unmodifiableStringList(json['limitations']),
      fingerprint: json['fingerprint'] as String,
      expectedProvenanceId: expected['provenanceId'] as String,
      expectedCompleteness: expected['completeness'] as bool,
      observedProvenanceId: observed['provenanceId'] as String,
      requiredStepCount: observed['requiredStepCount'] as int,
      observedStepCount: observed['observedStepCount'] as int,
    );
  }
}

class ArtifactIntegrityPredicate extends ReleaseAttestationPredicate {
  const ArtifactIntegrityPredicate({
    required super.predicateVersion,
    required super.result,
    required super.evidenceIds,
    required super.limitations,
    required super.fingerprint,
    required this.expectedArtifactId,
    required this.expectedFingerprint,
    required this.observedArtifactId,
    required this.observedFingerprint,
    required this.integrityStatus,
  }) : super(predicateType: ReleaseAttestationPredicateType.artifactIntegrity);

  final String expectedArtifactId;
  final String expectedFingerprint;
  final String observedArtifactId;
  final String observedFingerprint;
  final ReleaseEvidenceIntegrityStatus integrityStatus;

  @override
  Map<String, dynamic> get expected => {
        'artifactId': expectedArtifactId,
        'fingerprint': expectedFingerprint,
      };

  @override
  Map<String, dynamic> get observed => {
        'artifactId': observedArtifactId,
        'fingerprint': observedFingerprint,
        'integrityStatus': integrityStatus.wireName,
      };

  factory ArtifactIntegrityPredicate.fromJson(Map<String, dynamic> json) {
    final expected = json['expected'] as Map<String, dynamic>;
    final observed = json['observed'] as Map<String, dynamic>;
    return ArtifactIntegrityPredicate(
      predicateVersion: json['predicateVersion'] as String,
      result: ReleaseAttestationPredicateResultX.fromWireName(
        json['result'] as String,
      ),
      evidenceIds: _unmodifiableStringList(json['evidenceIds']),
      limitations: _unmodifiableStringList(json['limitations']),
      fingerprint: json['fingerprint'] as String,
      expectedArtifactId: expected['artifactId'] as String,
      expectedFingerprint: expected['fingerprint'] as String,
      observedArtifactId: observed['artifactId'] as String,
      observedFingerprint: observed['fingerprint'] as String,
      integrityStatus: ReleaseEvidenceIntegrityStatusX.fromWireName(
        observed['integrityStatus'] as String,
      ),
    );
  }
}

class ReadinessPredicate extends ReleaseAttestationPredicate {
  const ReadinessPredicate({
    required super.predicateVersion,
    required super.result,
    required super.evidenceIds,
    required super.limitations,
    required super.fingerprint,
    required this.expectedReadinessStatus,
    required this.observedReadinessStatus,
  }) : super(predicateType: ReleaseAttestationPredicateType.readiness);

  final String expectedReadinessStatus;
  final String observedReadinessStatus;

  @override
  Map<String, dynamic> get expected => {
        'readinessStatus': expectedReadinessStatus,
      };

  @override
  Map<String, dynamic> get observed => {
        'readinessStatus': observedReadinessStatus,
      };

  factory ReadinessPredicate.fromJson(Map<String, dynamic> json) {
    final expected = json['expected'] as Map<String, dynamic>;
    final observed = json['observed'] as Map<String, dynamic>;
    return ReadinessPredicate(
      predicateVersion: json['predicateVersion'] as String,
      result: ReleaseAttestationPredicateResultX.fromWireName(
        json['result'] as String,
      ),
      evidenceIds: _unmodifiableStringList(json['evidenceIds']),
      limitations: _unmodifiableStringList(json['limitations']),
      fingerprint: json['fingerprint'] as String,
      expectedReadinessStatus: expected['readinessStatus'] as String,
      observedReadinessStatus: observed['readinessStatus'] as String,
    );
  }
}

class CompliancePredicate extends ReleaseAttestationPredicate {
  const CompliancePredicate({
    required super.predicateVersion,
    required super.result,
    required super.evidenceIds,
    required super.limitations,
    required super.fingerprint,
    required this.expectedComplianceCode,
    required this.expectedCompliant,
    required this.observedComplianceCode,
    required this.observedCompliant,
  }) : super(predicateType: ReleaseAttestationPredicateType.compliance);

  final String expectedComplianceCode;
  final bool expectedCompliant;
  final String observedComplianceCode;
  final bool observedCompliant;

  @override
  Map<String, dynamic> get expected => {
        'complianceCode': expectedComplianceCode,
        'compliant': expectedCompliant,
      };

  @override
  Map<String, dynamic> get observed => {
        'complianceCode': observedComplianceCode,
        'compliant': observedCompliant,
      };

  factory CompliancePredicate.fromJson(Map<String, dynamic> json) {
    final expected = json['expected'] as Map<String, dynamic>;
    final observed = json['observed'] as Map<String, dynamic>;
    return CompliancePredicate(
      predicateVersion: json['predicateVersion'] as String,
      result: ReleaseAttestationPredicateResultX.fromWireName(
        json['result'] as String,
      ),
      evidenceIds: _unmodifiableStringList(json['evidenceIds']),
      limitations: _unmodifiableStringList(json['limitations']),
      fingerprint: json['fingerprint'] as String,
      expectedComplianceCode: expected['complianceCode'] as String,
      expectedCompliant: expected['compliant'] as bool,
      observedComplianceCode: observed['complianceCode'] as String,
      observedCompliant: observed['compliant'] as bool,
    );
  }
}

class CustomPredicate extends ReleaseAttestationPredicate {
  const CustomPredicate({
    required super.predicateVersion,
    required super.result,
    required super.evidenceIds,
    required super.limitations,
    required super.fingerprint,
    required this.customType,
    required this.expectedValues,
    required this.observedValues,
  }) : super(predicateType: ReleaseAttestationPredicateType.custom);

  final String customType;
  final Map<String, dynamic> expectedValues;
  final Map<String, dynamic> observedValues;

  @override
  Map<String, dynamic> get expected => expectedValues;

  @override
  Map<String, dynamic> get observed => observedValues;

  factory CustomPredicate.fromJson(Map<String, dynamic> json) {
    return CustomPredicate(
      predicateVersion: json['predicateVersion'] as String,
      result: ReleaseAttestationPredicateResultX.fromWireName(
        json['result'] as String,
      ),
      evidenceIds: _unmodifiableStringList(json['evidenceIds']),
      limitations: _unmodifiableStringList(json['limitations']),
      fingerprint: json['fingerprint'] as String,
      customType: json['customType'] as String? ?? 'custom',
      expectedValues: _unmodifiableMap(json['expected']),
      observedValues: _unmodifiableMap(json['observed']),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'customType': customType,
      };
}
