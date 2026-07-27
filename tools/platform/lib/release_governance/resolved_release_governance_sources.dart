import '../models/quality_gate/quality_gate_snapshot.dart';
import '../models/release_governance/release_approval.dart';
import '../models/release_governance/release_context.dart';
import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_evidence.dart';
import '../models/release_governance/release_governance_messages.dart';
import '../models/release_governance/release_governance_policy.dart';
import '../models/release_governance/release_governance_request.dart';
import '../models/release_governance/release_governance_rule_value.dart';
import '../models/release_governance/release_waiver.dart';

/// Availability state for a resolved release governance source wrapper.
enum ResolvedReleaseGovernanceSourceState {
  available,
  unavailable,
  notRequested,
  resolutionFailed,
}

/// Wrapper for a resolved source artifact with explicit availability.
class ResolvedReleaseGovernanceSource<T> {
  const ResolvedReleaseGovernanceSource({
    required this.sourceType,
    required this.resolutionMode,
    required this.state,
    this.requestedId,
    this.resolvedArtifact,
    this.resolvedId,
    this.fingerprint,
    this.projectId,
    this.commitId,
    this.policyId,
    this.policyVersion,
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
  });

  final ReleaseGovernanceSourceType sourceType;
  final ReleaseGovernanceSourceResolutionMode resolutionMode;
  final ResolvedReleaseGovernanceSourceState state;
  final String? requestedId;
  final T? resolvedArtifact;
  final String? resolvedId;
  final String? fingerprint;
  final String? projectId;
  final String? commitId;
  final String? policyId;
  final int? policyVersion;
  final List<ReleaseGovernanceWarning> warnings;
  final List<ReleaseGovernanceError> errors;
  final List<ReleaseGovernanceLimitation> limitations;

  bool get isAvailable =>
      state == ResolvedReleaseGovernanceSourceState.available &&
      resolvedArtifact != null;
}

/// Container for all resolved release governance sources.
class ResolvedReleaseGovernanceSources {
  const ResolvedReleaseGovernanceSources({
    required this.releaseContext,
    required this.qualityGateSnapshot,
    required this.policy,
    required this.approvalSet,
    required this.waiverSet,
    required this.sourceReferences,
    required this.resolutionSummary,
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
    this.compatibilityHints = const [],
  });

  final ResolvedReleaseGovernanceSource<ReleaseContext> releaseContext;
  final ResolvedReleaseGovernanceSource<QualityGateSnapshot>
      qualityGateSnapshot;
  final ResolvedReleaseGovernanceSource<ReleaseGovernancePolicy> policy;
  final ResolvedReleaseGovernanceSource<ReleaseApprovalSet> approvalSet;
  final ResolvedReleaseGovernanceSource<ReleaseWaiverSet> waiverSet;
  final List<ReleaseGovernanceSourceReference> sourceReferences;
  final ReleaseGovernanceSourceResolutionSummary resolutionSummary;
  final List<ReleaseGovernanceWarning> warnings;
  final List<ReleaseGovernanceError> errors;
  final List<ReleaseGovernanceLimitation> limitations;
  final List<String> compatibilityHints;

  List<ResolvedReleaseGovernanceSource<dynamic>> get allSources => [
        releaseContext,
        qualityGateSnapshot,
        policy,
        approvalSet,
        waiverSet,
      ];
}

/// Evaluation context passed to target resolvers.
class ReleaseGovernanceEvaluationContext {
  const ReleaseGovernanceEvaluationContext({
    required this.releaseContext,
    required this.referenceTime,
    required this.policy,
    this.strictCompatibility = true,
  });

  final ReleaseContext releaseContext;
  final String referenceTime;
  final ReleaseGovernancePolicy policy;
  final bool strictCompatibility;
}

/// Result of resolving a rule target value.
class ReleaseGovernanceTargetResolution {
  const ReleaseGovernanceTargetResolution({
    required this.status,
    this.actualValue,
    this.sourceReference,
    this.evidenceType = ReleaseGovernanceEvidenceType.operational,
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
    this.notApplicable = false,
  });

  final ReleaseGovernanceTargetResolutionStatus status;
  final ReleaseGovernanceRuleValue? actualValue;
  final ReleaseGovernanceSourceReference? sourceReference;
  final ReleaseGovernanceEvidenceType evidenceType;
  final List<ReleaseGovernanceWarning> warnings;
  final List<ReleaseGovernanceError> errors;
  final List<ReleaseGovernanceLimitation> limitations;
  final bool notApplicable;
}

enum ReleaseGovernanceTargetResolutionStatus {
  resolved,
  unavailable,
  incompatible,
  notApplicable,
  unsupported,
  error,
}
