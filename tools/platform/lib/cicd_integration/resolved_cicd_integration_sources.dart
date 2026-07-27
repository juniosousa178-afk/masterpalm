import '../models/cicd_integration/cicd_integration_messages.dart';
import '../models/cicd_integration/cicd_integration_operational_enums.dart';
import '../models/cicd_integration/cicd_integration_policy_models.dart';
import '../models/cicd_integration/cicd_integration_request.dart';
import '../models/cicd_integration/cicd_integration_result.dart';
import '../models/cicd_integration/deployment_models.dart';
import '../models/cicd_integration/pipeline_models.dart';
import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_supply_chain/release_supply_chain_snapshot.dart';

/// Wrapper for a resolved CI/CD integration source artifact.
class ResolvedCicdIntegrationSource<T> {
  const ResolvedCicdIntegrationSource({
    required this.sourceType,
    required this.resolutionMode,
    required this.state,
    this.requestedId,
    this.resolvedArtifact,
    this.resolvedId,
    this.fingerprint,
    this.projectId,
    this.releaseId,
    this.policyId,
    this.policyVersion,
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
  });

  final CicdIntegrationSourceType sourceType;
  final CicdIntegrationSourceResolutionMode resolutionMode;
  final CicdIntegrationSourceState state;
  final String? requestedId;
  final T? resolvedArtifact;
  final String? resolvedId;
  final String? fingerprint;
  final String? projectId;
  final String? releaseId;
  final String? policyId;
  final int? policyVersion;
  final List<CicdIntegrationWarning> warnings;
  final List<CicdIntegrationError> errors;
  final List<CicdIntegrationLimitation> limitations;

  bool get isAvailable =>
      state == CicdIntegrationSourceState.available && resolvedArtifact != null;
}

/// Container for all resolved CI/CD integration sources.
class ResolvedCicdIntegrationSources {
  const ResolvedCicdIntegrationSources({
    required this.pipelineDefinition,
    required this.pipelineExecution,
    required this.pipelineExecutionResult,
    required this.deploymentPlan,
    required this.deploymentResult,
    required this.releaseEvidenceBundle,
    required this.releaseSupplyChainSnapshot,
    required this.pipelineIntegrationPolicy,
    required this.pipelineExecutionPolicy,
    required this.deploymentIntegrationPolicy,
    required this.sourceReferences,
    required this.resolutionSummary,
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
    this.compatibilityHints = const [],
  });

  final ResolvedCicdIntegrationSource<PipelineDefinition> pipelineDefinition;
  final ResolvedCicdIntegrationSource<PipelineExecution> pipelineExecution;
  final ResolvedCicdIntegrationSource<PipelineExecutionResult>
      pipelineExecutionResult;
  final ResolvedCicdIntegrationSource<DeploymentPlan> deploymentPlan;
  final ResolvedCicdIntegrationSource<DeploymentResult> deploymentResult;
  final ResolvedCicdIntegrationSource<ReleaseEvidenceBundle>
      releaseEvidenceBundle;
  final ResolvedCicdIntegrationSource<ReleaseSupplyChainSnapshot>
      releaseSupplyChainSnapshot;
  final ResolvedCicdIntegrationSource<RegisteredPipelineIntegrationPolicy>
      pipelineIntegrationPolicy;
  final ResolvedCicdIntegrationSource<RegisteredPipelineExecutionPolicy>
      pipelineExecutionPolicy;
  final ResolvedCicdIntegrationSource<RegisteredDeploymentIntegrationPolicy>
      deploymentIntegrationPolicy;
  final List<CicdIntegrationSourceReference> sourceReferences;
  final CicdIntegrationSourceResolutionSummary resolutionSummary;
  final List<CicdIntegrationWarning> warnings;
  final List<CicdIntegrationError> errors;
  final List<CicdIntegrationLimitation> limitations;
  final List<String> compatibilityHints;

  List<ResolvedCicdIntegrationSource<dynamic>> get allSources => [
        pipelineDefinition,
        pipelineExecution,
        pipelineExecutionResult,
        deploymentPlan,
        deploymentResult,
        releaseEvidenceBundle,
        releaseSupplyChainSnapshot,
        pipelineIntegrationPolicy,
        pipelineExecutionPolicy,
        deploymentIntegrationPolicy,
      ];
}

/// Evaluation context passed through the CI/CD integration pipeline.
class CicdIntegrationEvaluationContext {
  const CicdIntegrationEvaluationContext({
    required this.request,
    required this.sources,
    required this.pipelineIntegrationPolicy,
    required this.pipelineExecutionPolicy,
    required this.deploymentIntegrationPolicy,
  });

  final CicdIntegrationRequest request;
  final ResolvedCicdIntegrationSources sources;
  final RegisteredPipelineIntegrationPolicy pipelineIntegrationPolicy;
  final RegisteredPipelineExecutionPolicy pipelineExecutionPolicy;
  final RegisteredDeploymentIntegrationPolicy deploymentIntegrationPolicy;
}
