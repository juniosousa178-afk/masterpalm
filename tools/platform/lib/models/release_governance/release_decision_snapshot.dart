import 'release_context.dart';
import 'release_governance_enums.dart';
import 'release_governance_evidence.dart';
import 'release_governance_messages.dart';
import 'release_governance_policy.dart';
import 'release_approval.dart';

/// Normative metadata for a release decision snapshot.
class ReleaseDecisionSnapshotMetadata {
  const ReleaseDecisionSnapshotMetadata({
    required this.snapshotId,
    required this.projectId,
    required this.releaseId,
    required this.releaseVersion,
    required this.commitId,
    required this.branch,
    required this.environment,
    required this.releaseType,
    required this.policyId,
    required this.policyVersion,
    required this.policyFingerprint,
    required this.qualityGateSnapshotId,
    required this.qualityGateFingerprint,
    required this.schemaVersion,
    required this.calculationVersion,
    required this.canonicalizationVersion,
    required this.evaluatedAt,
    required this.createdAt,
    required this.decision,
    this.resultStatus,
    this.sourceSetFingerprint,
    this.requestFingerprint,
    this.releaseGovernanceFingerprint,
  });

  static const int currentSchemaVersion = 1;

  final String snapshotId;
  final String projectId;
  final String releaseId;
  final String releaseVersion;
  final String commitId;
  final String branch;
  final ReleaseEnvironment environment;
  final ReleaseType releaseType;
  final String policyId;
  final int policyVersion;
  final String policyFingerprint;
  final String qualityGateSnapshotId;
  final String qualityGateFingerprint;
  final int schemaVersion;
  final int calculationVersion;
  final int canonicalizationVersion;
  final String evaluatedAt;
  final String createdAt;
  final ReleaseGovernanceDecision decision;
  final ReleaseGovernanceResultStatus? resultStatus;
  final String? sourceSetFingerprint;
  final String? requestFingerprint;
  final String? releaseGovernanceFingerprint;

  Map<String, dynamic> toJson() => {
        'snapshotId': snapshotId,
        'projectId': projectId,
        'releaseId': releaseId,
        'releaseVersion': releaseVersion,
        'commitId': commitId,
        'branch': branch,
        'environment': environment.wireName,
        'releaseType': releaseType.wireName,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'policyFingerprint': policyFingerprint,
        'qualityGateSnapshotId': qualityGateSnapshotId,
        'qualityGateFingerprint': qualityGateFingerprint,
        'schemaVersion': schemaVersion,
        'calculationVersion': calculationVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'evaluatedAt': evaluatedAt,
        'createdAt': createdAt,
        'decision': decision.wireName,
        if (resultStatus != null) 'resultStatus': resultStatus!.wireName,
        if (sourceSetFingerprint != null)
          'sourceSetFingerprint': sourceSetFingerprint,
        if (requestFingerprint != null)
          'requestFingerprint': requestFingerprint,
        if (releaseGovernanceFingerprint != null)
          'releaseGovernanceFingerprint': releaseGovernanceFingerprint,
      };

  factory ReleaseDecisionSnapshotMetadata.fromJson(Map<String, dynamic> json) {
    return ReleaseDecisionSnapshotMetadata(
      snapshotId: json['snapshotId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String,
      releaseVersion: json['releaseVersion'] as String,
      commitId: json['commitId'] as String,
      branch: json['branch'] as String,
      environment: ReleaseEnvironmentX.fromWireName(
        json['environment'] as String,
      ),
      releaseType: ReleaseTypeX.fromWireName(json['releaseType'] as String),
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      policyFingerprint: json['policyFingerprint'] as String,
      qualityGateSnapshotId: json['qualityGateSnapshotId'] as String,
      qualityGateFingerprint: json['qualityGateFingerprint'] as String,
      schemaVersion: json['schemaVersion'] as int,
      calculationVersion: json['calculationVersion'] as int,
      canonicalizationVersion: json['canonicalizationVersion'] as int,
      evaluatedAt: json['evaluatedAt'] as String,
      createdAt: json['createdAt'] as String,
      decision: ReleaseGovernanceDecisionX.fromWireName(
        json['decision'] as String,
      ),
      resultStatus: json['resultStatus'] == null
          ? null
          : ReleaseGovernanceResultStatusX.fromWireName(
              json['resultStatus'] as String,
            ),
      sourceSetFingerprint: json['sourceSetFingerprint'] as String?,
      requestFingerprint: json['requestFingerprint'] as String?,
      releaseGovernanceFingerprint:
          json['releaseGovernanceFingerprint'] as String?,
    );
  }
}

/// Immutable normative release decision artifact.
class ReleaseDecisionSnapshot {
  const ReleaseDecisionSnapshot({
    required this.metadata,
    required this.releaseContext,
    required this.policyReference,
    required this.qualityGateReference,
    required this.decision,
    required this.compatibility,
    required this.eligibility,
    required this.coverage,
    required this.fingerprint,
    this.evaluations = const [],
    this.approvalEvaluations = const [],
    this.waiverEvaluations = const [],
    this.conditions = const [],
    this.evidence = const [],
    this.sourceReferences = const [],
    this.explanations = const [],
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
  });

  final ReleaseDecisionSnapshotMetadata metadata;
  final ReleaseContext releaseContext;
  final ReleaseGovernancePolicyReference policyReference;
  final ReleaseQualityGateReference qualityGateReference;
  final ReleaseGovernanceDecision decision;
  final ReleaseGovernanceCompatibility compatibility;
  final ReleaseGovernanceEligibility eligibility;
  final ReleaseGovernanceCoverage coverage;
  final List<ReleaseGovernanceEvaluation> evaluations;
  final List<ReleaseApprovalEvaluation> approvalEvaluations;
  final List<ReleaseWaiverEvaluation> waiverEvaluations;
  final List<ReleaseCondition> conditions;
  final List<ReleaseGovernanceEvidence> evidence;
  final List<ReleaseGovernanceSourceReference> sourceReferences;
  final List<ReleaseGovernanceExplanation> explanations;
  final List<ReleaseGovernanceWarning> warnings;
  final List<ReleaseGovernanceError> errors;
  final List<ReleaseGovernanceLimitation> limitations;
  final String fingerprint;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'releaseContext': releaseContext.toJson(),
        'policyReference': policyReference.toJson(),
        'qualityGateReference': qualityGateReference.toJson(),
        'decision': decision.wireName,
        'compatibility': compatibility.toJson(),
        'eligibility': eligibility.toJson(),
        'coverage': coverage.toJson(),
        'evaluations': evaluations.map((e) => e.toJson()).toList(),
        'approvalEvaluations':
            approvalEvaluations.map((e) => e.toJson()).toList(),
        'waiverEvaluations': waiverEvaluations.map((e) => e.toJson()).toList(),
        'conditions': conditions.map((e) => e.toJson()).toList(),
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        'explanations': explanations.map((e) => e.toJson()).toList(),
        'warnings': warnings.map((e) => e.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
        'limitations': limitations.map((e) => e.toJson()).toList(),
        'fingerprint': fingerprint,
      };

  factory ReleaseDecisionSnapshot.fromJson(Map<String, dynamic> json) {
    return ReleaseDecisionSnapshot(
      metadata: ReleaseDecisionSnapshotMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      releaseContext: ReleaseContext.fromJson(
        json['releaseContext'] as Map<String, dynamic>,
      ),
      policyReference: ReleaseGovernancePolicyReference.fromJson(
        json['policyReference'] as Map<String, dynamic>,
      ),
      qualityGateReference: ReleaseQualityGateReference.fromJson(
        json['qualityGateReference'] as Map<String, dynamic>,
      ),
      decision: ReleaseGovernanceDecisionX.fromWireName(
        json['decision'] as String,
      ),
      compatibility: ReleaseGovernanceCompatibility.fromJson(
        json['compatibility'] as Map<String, dynamic>,
      ),
      eligibility: ReleaseGovernanceEligibility.fromJson(
        json['eligibility'] as Map<String, dynamic>,
      ),
      coverage: ReleaseGovernanceCoverage.fromJson(
        json['coverage'] as Map<String, dynamic>,
      ),
      evaluations: (json['evaluations'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseGovernanceEvaluation.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      approvalEvaluations: (json['approvalEvaluations'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseApprovalEvaluation.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      waiverEvaluations: (json['waiverEvaluations'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseWaiverEvaluation.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      conditions: (json['conditions'] as List<dynamic>? ?? [])
          .map((e) => ReleaseCondition.fromJson(e as Map<String, dynamic>))
          .toList(),
      evidence: (json['evidence'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseGovernanceEvidence.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      sourceReferences: (json['sourceReferences'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseGovernanceSourceReference.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      explanations: (json['explanations'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseGovernanceExplanation.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseGovernanceWarning.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      errors: (json['errors'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseGovernanceError.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseGovernanceLimitation.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      fingerprint: json['fingerprint'] as String,
    );
  }
}
