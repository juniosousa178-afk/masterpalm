import '../models/quality_gate/quality_gate_snapshot.dart';
import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_governance/release_context.dart';
import '../models/release_governance/release_decision_snapshot.dart';
import '../models/release_supply_chain/release_supply_chain_messages.dart';
import '../models/release_supply_chain/release_supply_chain_operational_enums.dart';
import '../models/release_supply_chain/release_supply_chain_policy_models.dart';
import '../models/release_supply_chain/release_supply_chain_request.dart';
import '../models/release_supply_chain/release_supply_chain_result.dart';

/// Wrapper for a resolved release supply chain source artifact.
class ResolvedReleaseSupplyChainSource<T> {
  const ResolvedReleaseSupplyChainSource({
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

  final ReleaseSupplyChainSourceType sourceType;
  final ReleaseSupplyChainSourceResolutionMode resolutionMode;
  final ReleaseSupplyChainSourceState state;
  final String? requestedId;
  final T? resolvedArtifact;
  final String? resolvedId;
  final String? fingerprint;
  final String? projectId;
  final String? commitId;
  final String? policyId;
  final int? policyVersion;
  final List<ReleaseSupplyChainWarning> warnings;
  final List<ReleaseSupplyChainError> errors;
  final List<ReleaseSupplyChainLimitation> limitations;

  bool get isAvailable =>
      state == ReleaseSupplyChainSourceState.available &&
      resolvedArtifact != null;
}

/// Container for all resolved release supply chain sources.
class ResolvedReleaseSupplyChainSources {
  const ResolvedReleaseSupplyChainSources({
    required this.releaseContext,
    required this.qualityGateSnapshot,
    required this.releaseDecisionSnapshot,
    required this.releaseEvidenceBundle,
    required this.supplyChainPolicy,
    required this.distributionPolicy,
    required this.compliancePolicy,
    required this.sourceReferences,
    required this.resolutionSummary,
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
    this.compatibilityHints = const [],
  });

  final ResolvedReleaseSupplyChainSource<ReleaseContext> releaseContext;
  final ResolvedReleaseSupplyChainSource<QualityGateSnapshot>
      qualityGateSnapshot;
  final ResolvedReleaseSupplyChainSource<ReleaseDecisionSnapshot>
      releaseDecisionSnapshot;
  final ResolvedReleaseSupplyChainSource<ReleaseEvidenceBundle>
      releaseEvidenceBundle;
  final ResolvedReleaseSupplyChainSource<RegisteredSupplyChainPolicy>
      supplyChainPolicy;
  final ResolvedReleaseSupplyChainSource<RegisteredDistributionPolicy>
      distributionPolicy;
  final ResolvedReleaseSupplyChainSource<RegisteredCompliancePolicy>
      compliancePolicy;
  final List<ReleaseSupplyChainSourceReference> sourceReferences;
  final ReleaseSupplyChainSourceResolutionSummary resolutionSummary;
  final List<ReleaseSupplyChainWarning> warnings;
  final List<ReleaseSupplyChainError> errors;
  final List<ReleaseSupplyChainLimitation> limitations;
  final List<String> compatibilityHints;

  List<ResolvedReleaseSupplyChainSource<dynamic>> get allSources => [
        releaseContext,
        qualityGateSnapshot,
        releaseDecisionSnapshot,
        releaseEvidenceBundle,
        supplyChainPolicy,
        distributionPolicy,
        compliancePolicy,
      ];
}

/// Evaluation context passed through the release supply chain pipeline.
class ReleaseSupplyChainEvaluationContext {
  const ReleaseSupplyChainEvaluationContext({
    required this.request,
    required this.sources,
    required this.supplyChainPolicy,
    required this.distributionPolicy,
    required this.compliancePolicy,
  });

  final ReleaseSupplyChainRequest request;
  final ResolvedReleaseSupplyChainSources sources;
  final RegisteredSupplyChainPolicy supplyChainPolicy;
  final RegisteredDistributionPolicy distributionPolicy;
  final RegisteredCompliancePolicy compliancePolicy;
}
