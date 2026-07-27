import '../config/platform_config.dart';
import '../interfaces/ast_provider.dart';
import '../interfaces/graph_provider.dart';
import '../interfaces/guardian_provider.dart';
import '../interfaces/history_provider.dart';
import '../interfaces/metrics_provider.dart';
import '../interfaces/report_provider.dart';
import '../interfaces/score_provider.dart';
import '../interfaces/mes_provider.dart';
import '../interfaces/dashboard_provider.dart';
import '../interfaces/observability_provider.dart';
import '../interfaces/quality_gate_provider.dart';
import '../interfaces/release_governance_provider.dart';
import '../interfaces/release_evidence_provider.dart';
import '../interfaces/release_supply_chain_provider.dart';
import '../interfaces/cicd_integration_provider.dart';
import '../interfaces/cryptographic_trust_provider.dart';
import '../interfaces/persistent_artifact_provider.dart';
import '../cryptographic_trust/interfaces/cryptographic_signer.dart';
import '../models/cicd_integration/cicd_integration_query.dart';
import '../models/cicd_integration/cicd_integration_request.dart';
import '../models/cicd_integration/cicd_integration_result.dart';
import '../models/cicd_integration/cicd_integration_snapshot.dart';
import '../models/cryptographic_trust/cryptographic_key_reference.dart';
import '../models/cryptographic_trust/cryptographic_signature_envelope.dart';
import '../models/cryptographic_trust/cryptographic_trust_evaluation_request.dart';
import '../models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import '../models/cryptographic_trust/cryptographic_trust_query.dart';
import '../models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import '../models/persistent_artifacts/persistent_artifact_evaluation_request.dart';
import '../models/persistent_artifacts/persistent_artifact_evaluation_result.dart';
import '../models/persistent_artifacts/persistent_artifact_infrastructure_snapshot.dart';
import '../models/persistent_artifacts/persistent_artifact_query.dart';
import '../models/quality_gate/quality_gate_request.dart';
import '../models/release_governance/release_governance_request.dart';
import '../models/release_evidence/release_evidence_request.dart';
import '../models/release_evidence/release_evidence_result.dart';
import '../models/release_supply_chain/release_supply_chain_request.dart';
import '../models/release_supply_chain/release_supply_chain_result.dart';
import 'provider_registry.dart';

/// Single entry point for cross-module access to platform providers.
class PlatformCore {
  PlatformCore({
    required this.config,
    required ProviderRegistry registry,
  }) : _registry = registry;

  final PlatformConfig config;
  final ProviderRegistry _registry;

  AstProvider ast() => _registry.resolve<AstProvider>();

  GuardianProvider guardian() => _registry.resolve<GuardianProvider>();

  GraphProvider graph() => _registry.resolve<GraphProvider>();

  MetricsProvider metrics() => _registry.resolve<MetricsProvider>();

  HistoryProvider history() => _registry.resolve<HistoryProvider>();

  ReportProvider report() => _registry.resolve<ReportProvider>();

  ScoreProvider score() => _registry.resolve<ScoreProvider>();

  MESProvider mes() => _registry.resolve<MESProvider>();

  DashboardProvider dashboard() => _registry.resolve<DashboardProvider>();

  ObservabilityProvider observability() =>
      _registry.resolve<ObservabilityProvider>();

  QualityGateProvider qualityGate() => _registry.resolve<QualityGateProvider>();

  ReleaseGovernanceProvider releaseGovernance() =>
      _registry.resolve<ReleaseGovernanceProvider>();

  ReleaseEvidenceProvider releaseEvidence() =>
      _registry.resolve<ReleaseEvidenceProvider>();

  ReleaseSupplyChainProvider releaseSupplyChain() =>
      _registry.resolve<ReleaseSupplyChainProvider>();

  CicdIntegrationProvider cicdIntegration() =>
      _registry.resolve<CicdIntegrationProvider>();

  CryptographicTrustProvider cryptographicTrust() =>
      _registry.resolve<CryptographicTrustProvider>();

  PersistentArtifactProvider persistentArtifacts() =>
      _registry.resolve<PersistentArtifactProvider>();

  Future<QualityGateResult> qualityGateEvaluate(
    QualityGateRequest request,
  ) =>
      qualityGate().evaluate(request);

  Future<QualityGateResult> qualityGateAndPublish(
    QualityGateRequest request,
  ) =>
      qualityGate().evaluateAndPublish(request);

  Future<ReleaseGovernanceResult> releaseGovernanceEvaluate(
    ReleaseGovernanceRequest request,
  ) =>
      releaseGovernance().evaluate(request);

  Future<ReleaseGovernanceResult> releaseGovernanceAndPublish(
    ReleaseGovernanceRequest request,
  ) =>
      releaseGovernance().evaluateAndPublish(request);

  Future<ReleaseEvidenceResult> releaseEvidenceEvaluate(
    ReleaseEvidenceRequest request,
  ) =>
      releaseEvidence().evaluate(request);

  Future<ReleaseEvidenceResult> releaseEvidenceAndPublish(
    ReleaseEvidenceRequest request,
  ) =>
      releaseEvidence().evaluateAndPublish(request);

  Future<ReleaseSupplyChainResult> releaseSupplyChainEvaluate(
    ReleaseSupplyChainRequest request,
  ) =>
      releaseSupplyChain().evaluate(request);

  Future<ReleaseSupplyChainResult> releaseSupplyChainPublish(
    ReleaseSupplyChainRequest request,
  ) =>
      releaseSupplyChain().evaluateAndPublish(request);

  Future<CicdIntegrationResult> cicdIntegrationEvaluate(
    CicdIntegrationRequest request,
  ) =>
      cicdIntegration().evaluate(request);

  Future<CicdIntegrationResult> cicdIntegrationPublish(
    CicdIntegrationRequest request,
  ) =>
      cicdIntegration().evaluateAndPublish(request);

  Future<CicdIntegrationSnapshot?> cicdIntegrationLoad(String snapshotId) =>
      cicdIntegration().load(snapshotId);

  Future<List<CicdIntegrationSnapshot>> cicdIntegrationQuery(
    CicdIntegrationQuery query,
  ) =>
      cicdIntegration().query(query);

  Future<CryptographicTrustEvaluationResult> cryptographicTrustEvaluate(
    CryptographicTrustEvaluationRequest request,
  ) =>
      cryptographicTrust().evaluate(request);

  Future<CryptographicTrustEvaluationResult>
      cryptographicTrustEvaluateAndPublish(
    CryptographicTrustEvaluationRequest request,
  ) =>
          cryptographicTrust().evaluateAndPublish(request);

  Future<void> cryptographicTrustPublish(
    CryptographicTrustSnapshot snapshot,
  ) =>
      cryptographicTrust().publish(snapshot);

  Future<CryptographicTrustSnapshot?> cryptographicTrustLoad(
    String snapshotId,
  ) =>
      cryptographicTrust().load(snapshotId);

  Future<CryptographicTrustSnapshot?> cryptographicTrustLatest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) =>
      cryptographicTrust().latest(
        projectId: projectId,
        releaseId: releaseId,
        policyId: policyId,
      );

  Future<List<CryptographicTrustSnapshot>> cryptographicTrustQuery(
    CryptographicTrustQuery query,
  ) =>
      cryptographicTrust().query(query);

  Future<CryptographicVerificationResult?> cryptographicTrustVerifySignature({
    required CryptographicSignatureEnvelope envelope,
    required List<int> subjectBytes,
    required String projectId,
    String? releaseId,
  }) =>
      cryptographicTrust().verifySignature(
        envelope: envelope,
        subjectBytes: subjectBytes,
        projectId: projectId,
        releaseId: releaseId,
      );

  Future<CryptographicSigningPrimitiveResult> cryptographicTrustSign({
    required CryptographicKeyReference keyReference,
    required List<int> digestBytes,
    required CryptographicSignatureEnvelope template,
  }) =>
      cryptographicTrust().sign(
        keyReference: keyReference,
        digestBytes: digestBytes,
        template: template,
      );

  Future<PersistentArtifactEvaluationResult> persistentArtifactEvaluate(
    PersistentArtifactEvaluationRequest request,
  ) =>
      persistentArtifacts().evaluate(request);

  Future<PersistentArtifactEvaluationResult>
      persistentArtifactEvaluateAndPublish(
    PersistentArtifactEvaluationRequest request,
  ) =>
          persistentArtifacts().evaluateAndPublish(request);

  Future<PersistentArtifactInfrastructureSnapshot?> persistentArtifactLoad(
    String snapshotId,
  ) =>
      persistentArtifacts().load(snapshotId);

  Future<PersistentArtifactInfrastructureSnapshot?> persistentArtifactLatest({
    required String projectId,
    String? releaseId,
  }) =>
      persistentArtifacts().latest(projectId: projectId, releaseId: releaseId);

  Future<List<PersistentArtifactInfrastructureSnapshot>>
      persistentArtifactQuery(
    PersistentArtifactQuery query,
  ) =>
          persistentArtifacts().query(query);

  T resolve<T extends Object>() => _registry.resolve<T>();
}
