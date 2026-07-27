import '../release_evidence/release_evidence_bundle.dart';
import '../release_supply_chain/release_supply_chain_snapshot.dart';
import 'deployment_models.dart';
import 'pipeline_equality.dart';
import 'pipeline_models.dart';

/// Request to collect and compose a CI/CD integration snapshot.
class CicdIntegrationRequest {
  const CicdIntegrationRequest({
    required this.requestId,
    required this.projectId,
    required this.requestedAt,
    this.releaseId,
    this.pipelineDefinitionId,
    this.pipelineExecutionId,
    this.deploymentPlanId,
    this.pipelineIntegrationPolicyId,
    this.pipelineIntegrationPolicyVersion,
    this.pipelineExecutionPolicyId,
    this.pipelineExecutionPolicyVersion,
    this.deploymentIntegrationPolicyId,
    this.deploymentIntegrationPolicyVersion,
    this.useLatest = false,
    this.pipelineDefinition,
    this.pipelineExecution,
    this.pipelineExecutionResult,
    this.deploymentPlan,
    this.deploymentResult,
    this.releaseEvidenceBundle,
    this.releaseSupplyChainSnapshot,
    this.metadata = const {},
  });

  final String requestId;
  final String projectId;
  final String? releaseId;
  final String? pipelineDefinitionId;
  final String? pipelineExecutionId;
  final String? deploymentPlanId;
  final String? pipelineIntegrationPolicyId;
  final int? pipelineIntegrationPolicyVersion;
  final String? pipelineExecutionPolicyId;
  final int? pipelineExecutionPolicyVersion;
  final String? deploymentIntegrationPolicyId;
  final int? deploymentIntegrationPolicyVersion;
  final bool useLatest;
  final String requestedAt;
  final PipelineDefinition? pipelineDefinition;
  final PipelineExecution? pipelineExecution;
  final PipelineExecutionResult? pipelineExecutionResult;
  final DeploymentPlan? deploymentPlan;
  final DeploymentResult? deploymentResult;
  final ReleaseEvidenceBundle? releaseEvidenceBundle;
  final ReleaseSupplyChainSnapshot? releaseSupplyChainSnapshot;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (pipelineDefinitionId != null)
          'pipelineDefinitionId': pipelineDefinitionId,
        if (pipelineExecutionId != null)
          'pipelineExecutionId': pipelineExecutionId,
        if (deploymentPlanId != null) 'deploymentPlanId': deploymentPlanId,
        if (pipelineIntegrationPolicyId != null)
          'pipelineIntegrationPolicyId': pipelineIntegrationPolicyId,
        if (pipelineIntegrationPolicyVersion != null)
          'pipelineIntegrationPolicyVersion': pipelineIntegrationPolicyVersion,
        if (pipelineExecutionPolicyId != null)
          'pipelineExecutionPolicyId': pipelineExecutionPolicyId,
        if (pipelineExecutionPolicyVersion != null)
          'pipelineExecutionPolicyVersion': pipelineExecutionPolicyVersion,
        if (deploymentIntegrationPolicyId != null)
          'deploymentIntegrationPolicyId': deploymentIntegrationPolicyId,
        if (deploymentIntegrationPolicyVersion != null)
          'deploymentIntegrationPolicyVersion':
              deploymentIntegrationPolicyVersion,
        'useLatest': useLatest,
        'requestedAt': requestedAt,
        if (pipelineDefinition != null)
          'pipelineDefinition': pipelineDefinition!.toJson(),
        if (pipelineExecution != null)
          'pipelineExecution': pipelineExecution!.toJson(),
        if (pipelineExecutionResult != null)
          'pipelineExecutionResult': pipelineExecutionResult!.toJson(),
        if (deploymentPlan != null) 'deploymentPlan': deploymentPlan!.toJson(),
        if (deploymentResult != null)
          'deploymentResult': deploymentResult!.toJson(),
        if (releaseEvidenceBundle != null)
          'releaseEvidenceBundle': releaseEvidenceBundle!.toJson(),
        if (releaseSupplyChainSnapshot != null)
          'releaseSupplyChainSnapshot': releaseSupplyChainSnapshot!.toJson(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CicdIntegrationRequest.fromJson(Map<String, dynamic> json) {
    return CicdIntegrationRequest(
      requestId: json['requestId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      pipelineDefinitionId: json['pipelineDefinitionId'] as String?,
      pipelineExecutionId: json['pipelineExecutionId'] as String?,
      deploymentPlanId: json['deploymentPlanId'] as String?,
      pipelineIntegrationPolicyId:
          json['pipelineIntegrationPolicyId'] as String?,
      pipelineIntegrationPolicyVersion:
          json['pipelineIntegrationPolicyVersion'] as int?,
      pipelineExecutionPolicyId: json['pipelineExecutionPolicyId'] as String?,
      pipelineExecutionPolicyVersion:
          json['pipelineExecutionPolicyVersion'] as int?,
      deploymentIntegrationPolicyId:
          json['deploymentIntegrationPolicyId'] as String?,
      deploymentIntegrationPolicyVersion:
          json['deploymentIntegrationPolicyVersion'] as int?,
      useLatest: json['useLatest'] as bool? ?? false,
      requestedAt: json['requestedAt'] as String,
      pipelineDefinition: json['pipelineDefinition'] == null
          ? null
          : PipelineDefinition.fromJson(
              json['pipelineDefinition'] as Map<String, dynamic>,
            ),
      pipelineExecution: json['pipelineExecution'] == null
          ? null
          : PipelineExecution.fromJson(
              json['pipelineExecution'] as Map<String, dynamic>,
            ),
      pipelineExecutionResult: json['pipelineExecutionResult'] == null
          ? null
          : PipelineExecutionResult.fromJson(
              json['pipelineExecutionResult'] as Map<String, dynamic>,
            ),
      deploymentPlan: json['deploymentPlan'] == null
          ? null
          : DeploymentPlan.fromJson(
              json['deploymentPlan'] as Map<String, dynamic>,
            ),
      deploymentResult: json['deploymentResult'] == null
          ? null
          : DeploymentResult.fromJson(
              json['deploymentResult'] as Map<String, dynamic>,
            ),
      releaseEvidenceBundle: json['releaseEvidenceBundle'] == null
          ? null
          : ReleaseEvidenceBundle.fromJson(
              json['releaseEvidenceBundle'] as Map<String, dynamic>,
            ),
      releaseSupplyChainSnapshot: json['releaseSupplyChainSnapshot'] == null
          ? null
          : ReleaseSupplyChainSnapshot.fromJson(
              json['releaseSupplyChainSnapshot'] as Map<String, dynamic>,
            ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  CicdIntegrationRequest copyWith({
    String? requestId,
    String? projectId,
    String? releaseId,
    String? pipelineDefinitionId,
    String? pipelineExecutionId,
    String? deploymentPlanId,
    String? pipelineIntegrationPolicyId,
    int? pipelineIntegrationPolicyVersion,
    String? pipelineExecutionPolicyId,
    int? pipelineExecutionPolicyVersion,
    String? deploymentIntegrationPolicyId,
    int? deploymentIntegrationPolicyVersion,
    bool? useLatest,
    String? requestedAt,
    PipelineDefinition? pipelineDefinition,
    PipelineExecution? pipelineExecution,
    PipelineExecutionResult? pipelineExecutionResult,
    DeploymentPlan? deploymentPlan,
    DeploymentResult? deploymentResult,
    ReleaseEvidenceBundle? releaseEvidenceBundle,
    ReleaseSupplyChainSnapshot? releaseSupplyChainSnapshot,
    Map<String, String>? metadata,
  }) {
    return CicdIntegrationRequest(
      requestId: requestId ?? this.requestId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      pipelineDefinitionId: pipelineDefinitionId ?? this.pipelineDefinitionId,
      pipelineExecutionId: pipelineExecutionId ?? this.pipelineExecutionId,
      deploymentPlanId: deploymentPlanId ?? this.deploymentPlanId,
      pipelineIntegrationPolicyId:
          pipelineIntegrationPolicyId ?? this.pipelineIntegrationPolicyId,
      pipelineIntegrationPolicyVersion: pipelineIntegrationPolicyVersion ??
          this.pipelineIntegrationPolicyVersion,
      pipelineExecutionPolicyId:
          pipelineExecutionPolicyId ?? this.pipelineExecutionPolicyId,
      pipelineExecutionPolicyVersion:
          pipelineExecutionPolicyVersion ?? this.pipelineExecutionPolicyVersion,
      deploymentIntegrationPolicyId:
          deploymentIntegrationPolicyId ?? this.deploymentIntegrationPolicyId,
      deploymentIntegrationPolicyVersion: deploymentIntegrationPolicyVersion ??
          this.deploymentIntegrationPolicyVersion,
      useLatest: useLatest ?? this.useLatest,
      requestedAt: requestedAt ?? this.requestedAt,
      pipelineDefinition: pipelineDefinition ?? this.pipelineDefinition,
      pipelineExecution: pipelineExecution ?? this.pipelineExecution,
      pipelineExecutionResult:
          pipelineExecutionResult ?? this.pipelineExecutionResult,
      deploymentPlan: deploymentPlan ?? this.deploymentPlan,
      deploymentResult: deploymentResult ?? this.deploymentResult,
      releaseEvidenceBundle:
          releaseEvidenceBundle ?? this.releaseEvidenceBundle,
      releaseSupplyChainSnapshot:
          releaseSupplyChainSnapshot ?? this.releaseSupplyChainSnapshot,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CicdIntegrationRequest &&
          requestId == other.requestId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          pipelineDefinitionId == other.pipelineDefinitionId &&
          pipelineExecutionId == other.pipelineExecutionId &&
          deploymentPlanId == other.deploymentPlanId &&
          pipelineIntegrationPolicyId == other.pipelineIntegrationPolicyId &&
          pipelineIntegrationPolicyVersion ==
              other.pipelineIntegrationPolicyVersion &&
          pipelineExecutionPolicyId == other.pipelineExecutionPolicyId &&
          pipelineExecutionPolicyVersion ==
              other.pipelineExecutionPolicyVersion &&
          deploymentIntegrationPolicyId ==
              other.deploymentIntegrationPolicyId &&
          deploymentIntegrationPolicyVersion ==
              other.deploymentIntegrationPolicyVersion &&
          useLatest == other.useLatest &&
          requestedAt == other.requestedAt &&
          pipelineDefinition == other.pipelineDefinition &&
          pipelineExecution == other.pipelineExecution &&
          pipelineExecutionResult == other.pipelineExecutionResult &&
          deploymentPlan == other.deploymentPlan &&
          deploymentResult == other.deploymentResult &&
          releaseEvidenceBundle == other.releaseEvidenceBundle &&
          releaseSupplyChainSnapshot == other.releaseSupplyChainSnapshot &&
          cicdMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        Object.hash(
          requestId,
          projectId,
          releaseId,
          pipelineDefinitionId,
          pipelineExecutionId,
          deploymentPlanId,
          pipelineIntegrationPolicyId,
          pipelineIntegrationPolicyVersion,
          pipelineExecutionPolicyId,
          pipelineExecutionPolicyVersion,
          deploymentIntegrationPolicyId,
          deploymentIntegrationPolicyVersion,
          useLatest,
          requestedAt,
          pipelineDefinition,
          pipelineExecution,
          pipelineExecutionResult,
          deploymentPlan,
          deploymentResult,
        ),
        releaseEvidenceBundle,
        releaseSupplyChainSnapshot,
        Object.hashAll(metadata.entries),
      );
}
