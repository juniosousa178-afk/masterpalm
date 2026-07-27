import 'cicd_integration_identity.dart';
import 'cicd_integration_messages.dart';
import 'cicd_integration_operational_enums.dart';
import 'cicd_integration_policy_models.dart';
import 'deployment_models.dart';
import 'pipeline_equality.dart';
import 'pipeline_models.dart';

/// Metadata for a published CI/CD integration snapshot.
class CicdIntegrationSnapshotMetadata {
  const CicdIntegrationSnapshotMetadata({
    required this.cicdIntegrationSnapshotId,
    required this.projectId,
    required this.schemaVersion,
    required this.canonicalizationVersion,
    required this.createdAt,
    required this.evaluatedAt,
    required this.fingerprint,
    required this.status,
    required this.pipelineIntegrationPolicyId,
    required this.pipelineIntegrationPolicyVersion,
    required this.pipelineExecutionPolicyId,
    required this.pipelineExecutionPolicyVersion,
    required this.deploymentIntegrationPolicyId,
    required this.deploymentIntegrationPolicyVersion,
    this.releaseId,
    this.pipelineDefinitionId,
    this.pipelineDefinitionVersion,
    this.pipelineExecutionId,
    this.deploymentPlanId,
    this.releaseEvidenceBundleId,
    this.releaseSupplyChainSnapshotId,
    this.pipelineFingerprint,
    this.executionFingerprint,
    this.executionResultFingerprint,
    this.deploymentPlanFingerprint,
    this.deploymentResultFingerprint,
    this.limitations = const [],
  });

  static const int currentSchemaVersion = 1;
  static const int currentCanonicalizationVersion = 1;

  final String cicdIntegrationSnapshotId;
  final String projectId;
  final String? releaseId;
  final String? pipelineDefinitionId;
  final int? pipelineDefinitionVersion;
  final String? pipelineExecutionId;
  final String? deploymentPlanId;
  final String? releaseEvidenceBundleId;
  final String? releaseSupplyChainSnapshotId;
  final String pipelineIntegrationPolicyId;
  final int pipelineIntegrationPolicyVersion;
  final String pipelineExecutionPolicyId;
  final int pipelineExecutionPolicyVersion;
  final String deploymentIntegrationPolicyId;
  final int deploymentIntegrationPolicyVersion;
  final int schemaVersion;
  final int canonicalizationVersion;
  final String createdAt;
  final String evaluatedAt;
  final String fingerprint;
  final CicdIntegrationSnapshotStatus status;
  final String? pipelineFingerprint;
  final String? executionFingerprint;
  final String? executionResultFingerprint;
  final String? deploymentPlanFingerprint;
  final String? deploymentResultFingerprint;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'cicdIntegrationSnapshotId': cicdIntegrationSnapshotId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (pipelineDefinitionId != null)
          'pipelineDefinitionId': pipelineDefinitionId,
        if (pipelineDefinitionVersion != null)
          'pipelineDefinitionVersion': pipelineDefinitionVersion,
        if (pipelineExecutionId != null)
          'pipelineExecutionId': pipelineExecutionId,
        if (deploymentPlanId != null) 'deploymentPlanId': deploymentPlanId,
        if (releaseEvidenceBundleId != null)
          'releaseEvidenceBundleId': releaseEvidenceBundleId,
        if (releaseSupplyChainSnapshotId != null)
          'releaseSupplyChainSnapshotId': releaseSupplyChainSnapshotId,
        'pipelineIntegrationPolicyId': pipelineIntegrationPolicyId,
        'pipelineIntegrationPolicyVersion': pipelineIntegrationPolicyVersion,
        'pipelineExecutionPolicyId': pipelineExecutionPolicyId,
        'pipelineExecutionPolicyVersion': pipelineExecutionPolicyVersion,
        'deploymentIntegrationPolicyId': deploymentIntegrationPolicyId,
        'deploymentIntegrationPolicyVersion':
            deploymentIntegrationPolicyVersion,
        'schemaVersion': schemaVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'createdAt': createdAt,
        'evaluatedAt': evaluatedAt,
        'fingerprint': fingerprint,
        'status': status.wireName,
        if (pipelineFingerprint != null)
          'pipelineFingerprint': pipelineFingerprint,
        if (executionFingerprint != null)
          'executionFingerprint': executionFingerprint,
        if (executionResultFingerprint != null)
          'executionResultFingerprint': executionResultFingerprint,
        if (deploymentPlanFingerprint != null)
          'deploymentPlanFingerprint': deploymentPlanFingerprint,
        if (deploymentResultFingerprint != null)
          'deploymentResultFingerprint': deploymentResultFingerprint,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory CicdIntegrationSnapshotMetadata.fromJson(Map<String, dynamic> json) {
    return CicdIntegrationSnapshotMetadata(
      cicdIntegrationSnapshotId: json['cicdIntegrationSnapshotId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      pipelineDefinitionId: json['pipelineDefinitionId'] as String?,
      pipelineDefinitionVersion: json['pipelineDefinitionVersion'] as int?,
      pipelineExecutionId: json['pipelineExecutionId'] as String?,
      deploymentPlanId: json['deploymentPlanId'] as String?,
      releaseEvidenceBundleId: json['releaseEvidenceBundleId'] as String?,
      releaseSupplyChainSnapshotId:
          json['releaseSupplyChainSnapshotId'] as String?,
      pipelineIntegrationPolicyId:
          json['pipelineIntegrationPolicyId'] as String,
      pipelineIntegrationPolicyVersion:
          json['pipelineIntegrationPolicyVersion'] as int,
      pipelineExecutionPolicyId: json['pipelineExecutionPolicyId'] as String,
      pipelineExecutionPolicyVersion:
          json['pipelineExecutionPolicyVersion'] as int,
      deploymentIntegrationPolicyId:
          json['deploymentIntegrationPolicyId'] as String,
      deploymentIntegrationPolicyVersion:
          json['deploymentIntegrationPolicyVersion'] as int,
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      canonicalizationVersion: json['canonicalizationVersion'] as int? ??
          currentCanonicalizationVersion,
      createdAt: json['createdAt'] as String,
      evaluatedAt: json['evaluatedAt'] as String,
      fingerprint: json['fingerprint'] as String,
      status: CicdIntegrationSnapshotStatusX.fromWireName(
        json['status'] as String,
      ),
      pipelineFingerprint: json['pipelineFingerprint'] as String?,
      executionFingerprint: json['executionFingerprint'] as String?,
      executionResultFingerprint: json['executionResultFingerprint'] as String?,
      deploymentPlanFingerprint: json['deploymentPlanFingerprint'] as String?,
      deploymentResultFingerprint:
          json['deploymentResultFingerprint'] as String?,
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (pipelineDefinitionId != null)
          'pipelineDefinitionId': pipelineDefinitionId,
        if (pipelineDefinitionVersion != null)
          'pipelineDefinitionVersion': pipelineDefinitionVersion,
        if (pipelineExecutionId != null)
          'pipelineExecutionId': pipelineExecutionId,
        if (deploymentPlanId != null) 'deploymentPlanId': deploymentPlanId,
        if (releaseEvidenceBundleId != null)
          'releaseEvidenceBundleId': releaseEvidenceBundleId,
        if (releaseSupplyChainSnapshotId != null)
          'releaseSupplyChainSnapshotId': releaseSupplyChainSnapshotId,
        'pipelineIntegrationPolicyId': pipelineIntegrationPolicyId,
        'pipelineIntegrationPolicyVersion': pipelineIntegrationPolicyVersion,
        'pipelineExecutionPolicyId': pipelineExecutionPolicyId,
        'pipelineExecutionPolicyVersion': pipelineExecutionPolicyVersion,
        'deploymentIntegrationPolicyId': deploymentIntegrationPolicyId,
        'deploymentIntegrationPolicyVersion':
            deploymentIntegrationPolicyVersion,
        'schemaVersion': schemaVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'status': status.wireName,
        if (pipelineFingerprint != null)
          'pipelineFingerprint': pipelineFingerprint,
        if (executionFingerprint != null)
          'executionFingerprint': executionFingerprint,
        if (executionResultFingerprint != null)
          'executionResultFingerprint': executionResultFingerprint,
        if (deploymentPlanFingerprint != null)
          'deploymentPlanFingerprint': deploymentPlanFingerprint,
        if (deploymentResultFingerprint != null)
          'deploymentResultFingerprint': deploymentResultFingerprint,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  CicdIntegrationSnapshotMetadata copyWith({
    String? cicdIntegrationSnapshotId,
    String? projectId,
    String? releaseId,
    String? pipelineDefinitionId,
    int? pipelineDefinitionVersion,
    String? pipelineExecutionId,
    String? deploymentPlanId,
    String? releaseEvidenceBundleId,
    String? releaseSupplyChainSnapshotId,
    String? pipelineIntegrationPolicyId,
    int? pipelineIntegrationPolicyVersion,
    String? pipelineExecutionPolicyId,
    int? pipelineExecutionPolicyVersion,
    String? deploymentIntegrationPolicyId,
    int? deploymentIntegrationPolicyVersion,
    int? schemaVersion,
    int? canonicalizationVersion,
    String? createdAt,
    String? evaluatedAt,
    String? fingerprint,
    CicdIntegrationSnapshotStatus? status,
    String? pipelineFingerprint,
    String? executionFingerprint,
    String? executionResultFingerprint,
    String? deploymentPlanFingerprint,
    String? deploymentResultFingerprint,
    List<String>? limitations,
  }) {
    return CicdIntegrationSnapshotMetadata(
      cicdIntegrationSnapshotId:
          cicdIntegrationSnapshotId ?? this.cicdIntegrationSnapshotId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      pipelineDefinitionId: pipelineDefinitionId ?? this.pipelineDefinitionId,
      pipelineDefinitionVersion:
          pipelineDefinitionVersion ?? this.pipelineDefinitionVersion,
      pipelineExecutionId: pipelineExecutionId ?? this.pipelineExecutionId,
      deploymentPlanId: deploymentPlanId ?? this.deploymentPlanId,
      releaseEvidenceBundleId:
          releaseEvidenceBundleId ?? this.releaseEvidenceBundleId,
      releaseSupplyChainSnapshotId:
          releaseSupplyChainSnapshotId ?? this.releaseSupplyChainSnapshotId,
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
      schemaVersion: schemaVersion ?? this.schemaVersion,
      canonicalizationVersion:
          canonicalizationVersion ?? this.canonicalizationVersion,
      createdAt: createdAt ?? this.createdAt,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
      fingerprint: fingerprint ?? this.fingerprint,
      status: status ?? this.status,
      pipelineFingerprint: pipelineFingerprint ?? this.pipelineFingerprint,
      executionFingerprint: executionFingerprint ?? this.executionFingerprint,
      executionResultFingerprint:
          executionResultFingerprint ?? this.executionResultFingerprint,
      deploymentPlanFingerprint:
          deploymentPlanFingerprint ?? this.deploymentPlanFingerprint,
      deploymentResultFingerprint:
          deploymentResultFingerprint ?? this.deploymentResultFingerprint,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CicdIntegrationSnapshotMetadata &&
          cicdIntegrationSnapshotId == other.cicdIntegrationSnapshotId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          pipelineDefinitionId == other.pipelineDefinitionId &&
          pipelineDefinitionVersion == other.pipelineDefinitionVersion &&
          pipelineExecutionId == other.pipelineExecutionId &&
          deploymentPlanId == other.deploymentPlanId &&
          releaseEvidenceBundleId == other.releaseEvidenceBundleId &&
          releaseSupplyChainSnapshotId == other.releaseSupplyChainSnapshotId &&
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
          schemaVersion == other.schemaVersion &&
          canonicalizationVersion == other.canonicalizationVersion &&
          createdAt == other.createdAt &&
          evaluatedAt == other.evaluatedAt &&
          fingerprint == other.fingerprint &&
          status == other.status &&
          pipelineFingerprint == other.pipelineFingerprint &&
          executionFingerprint == other.executionFingerprint &&
          executionResultFingerprint == other.executionResultFingerprint &&
          deploymentPlanFingerprint == other.deploymentPlanFingerprint &&
          deploymentResultFingerprint == other.deploymentResultFingerprint &&
          cicdListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        Object.hash(
          cicdIntegrationSnapshotId,
          projectId,
          releaseId,
          pipelineDefinitionId,
          pipelineDefinitionVersion,
          pipelineExecutionId,
          deploymentPlanId,
          releaseEvidenceBundleId,
          releaseSupplyChainSnapshotId,
          pipelineIntegrationPolicyId,
          pipelineIntegrationPolicyVersion,
          pipelineExecutionPolicyId,
          pipelineExecutionPolicyVersion,
          deploymentIntegrationPolicyId,
          deploymentIntegrationPolicyVersion,
          schemaVersion,
          canonicalizationVersion,
          createdAt,
          evaluatedAt,
        ),
        Object.hash(
          fingerprint,
          status,
          pipelineFingerprint,
          executionFingerprint,
          executionResultFingerprint,
          deploymentPlanFingerprint,
          deploymentResultFingerprint,
        ),
        Object.hashAll(limitations),
      );
}

/// Published aggregate snapshot for CI/CD integration.
class CicdIntegrationSnapshot {
  const CicdIntegrationSnapshot({
    required this.metadata,
    required this.fingerprint,
    required this.status,
    this.pipelineDefinition,
    this.pipelineExecution,
    this.pipelineExecutionResult,
    this.deploymentPlan,
    this.deploymentResult,
    this.sourceReferences = const [],
    this.policyReference,
    this.identity,
    this.warnings = const [],
    this.limitations = const [],
  });

  final CicdIntegrationSnapshotMetadata metadata;
  final String fingerprint;
  final CicdIntegrationSnapshotStatus status;
  final PipelineDefinition? pipelineDefinition;
  final PipelineExecution? pipelineExecution;
  final PipelineExecutionResult? pipelineExecutionResult;
  final DeploymentPlan? deploymentPlan;
  final DeploymentResult? deploymentResult;
  final List<CicdIntegrationSourceReference> sourceReferences;
  final CicdIntegrationPolicyReference? policyReference;
  final CicdIntegrationIdentity? identity;
  final List<String> warnings;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'fingerprint': fingerprint,
        'status': status.wireName,
        if (pipelineDefinition != null)
          'pipelineDefinition': pipelineDefinition!.toJson(),
        if (pipelineExecution != null)
          'pipelineExecution': pipelineExecution!.toJson(),
        if (pipelineExecutionResult != null)
          'pipelineExecutionResult': pipelineExecutionResult!.toJson(),
        if (deploymentPlan != null) 'deploymentPlan': deploymentPlan!.toJson(),
        if (deploymentResult != null)
          'deploymentResult': deploymentResult!.toJson(),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        if (policyReference != null)
          'policyReference': policyReference!.toJson(),
        if (identity != null) 'identity': identity!.toJson(),
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory CicdIntegrationSnapshot.fromJson(Map<String, dynamic> json) {
    return CicdIntegrationSnapshot(
      metadata: CicdIntegrationSnapshotMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      fingerprint: json['fingerprint'] as String,
      status: CicdIntegrationSnapshotStatusX.fromWireName(
        json['status'] as String,
      ),
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
      sourceReferences: List.unmodifiable(
        (json['sourceReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => CicdIntegrationSourceReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      policyReference: json['policyReference'] == null
          ? null
          : CicdIntegrationPolicyReference.fromJson(
              json['policyReference'] as Map<String, dynamic>,
            ),
      identity: json['identity'] == null
          ? null
          : CicdIntegrationIdentity.fromJson(
              json['identity'] as Map<String, dynamic>,
            ),
      warnings: List.unmodifiable(
        (json['warnings'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'metadata': metadata.toComparableJson(),
        'status': status.wireName,
        if (pipelineDefinition != null)
          'pipelineDefinition': pipelineDefinition!.toComparableJson(),
        if (pipelineExecution != null)
          'pipelineExecution': pipelineExecution!.toComparableJson(),
        if (pipelineExecutionResult != null)
          'pipelineExecutionResult':
              pipelineExecutionResult!.toComparableJson(),
        if (deploymentPlan != null)
          'deploymentPlan': deploymentPlan!.toComparableJson(),
        if (deploymentResult != null)
          'deploymentResult': deploymentResult!.toComparableJson(),
        if (sourceReferences.isNotEmpty)
          'sourceReferences':
              (sourceReferences.map((e) => e.toComparableJson()).toList()
                ..sort(
                  (a, b) => a['requestedId']
                      .toString()
                      .compareTo(b['requestedId'].toString()),
                )),
        if (policyReference != null)
          'policyReference': policyReference!.toComparableJson(),
        if (identity != null) 'identity': identity!.toComparableJson(),
        if (warnings.isNotEmpty)
          'warnings': List<String>.from(warnings)..sort(),
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  CicdIntegrationSnapshot copyWith({
    CicdIntegrationSnapshotMetadata? metadata,
    String? fingerprint,
    CicdIntegrationSnapshotStatus? status,
    PipelineDefinition? pipelineDefinition,
    PipelineExecution? pipelineExecution,
    PipelineExecutionResult? pipelineExecutionResult,
    DeploymentPlan? deploymentPlan,
    DeploymentResult? deploymentResult,
    List<CicdIntegrationSourceReference>? sourceReferences,
    CicdIntegrationPolicyReference? policyReference,
    CicdIntegrationIdentity? identity,
    List<String>? warnings,
    List<String>? limitations,
  }) {
    return CicdIntegrationSnapshot(
      metadata: metadata ?? this.metadata,
      fingerprint: fingerprint ?? this.fingerprint,
      status: status ?? this.status,
      pipelineDefinition: pipelineDefinition ?? this.pipelineDefinition,
      pipelineExecution: pipelineExecution ?? this.pipelineExecution,
      pipelineExecutionResult:
          pipelineExecutionResult ?? this.pipelineExecutionResult,
      deploymentPlan: deploymentPlan ?? this.deploymentPlan,
      deploymentResult: deploymentResult ?? this.deploymentResult,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      policyReference: policyReference ?? this.policyReference,
      identity: identity ?? this.identity,
      warnings: warnings ?? this.warnings,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CicdIntegrationSnapshot &&
          metadata == other.metadata &&
          fingerprint == other.fingerprint &&
          status == other.status &&
          pipelineDefinition == other.pipelineDefinition &&
          pipelineExecution == other.pipelineExecution &&
          pipelineExecutionResult == other.pipelineExecutionResult &&
          deploymentPlan == other.deploymentPlan &&
          deploymentResult == other.deploymentResult &&
          cicdListEquals(sourceReferences, other.sourceReferences) &&
          policyReference == other.policyReference &&
          identity == other.identity &&
          cicdListEquals(warnings, other.warnings) &&
          cicdListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        metadata,
        fingerprint,
        status,
        pipelineDefinition,
        pipelineExecution,
        pipelineExecutionResult,
        deploymentPlan,
        deploymentResult,
        Object.hashAll(sourceReferences),
        policyReference,
        identity,
        Object.hashAll(warnings),
        Object.hashAll(limitations),
      );
}
