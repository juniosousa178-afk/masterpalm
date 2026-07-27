import '../interfaces/release_evidence_provider.dart';
import '../interfaces/release_supply_chain_provider.dart';
import '../models/cicd_integration/cicd_integration_messages.dart';
import '../models/cicd_integration/cicd_integration_operational_enums.dart';
import '../models/cicd_integration/cicd_integration_policy_models.dart';
import '../models/cicd_integration/cicd_integration_request.dart';
import '../models/cicd_integration/cicd_integration_result.dart';
import '../models/cicd_integration/deployment_models.dart';
import '../models/cicd_integration/pipeline_models.dart';
import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_supply_chain/release_supply_chain_snapshot.dart';
import 'cicd_integration_artifact_registry.dart';
import 'cicd_integration_canonical_serializer.dart';
import 'cicd_integration_policy_registry.dart';
import 'policies/deployment_integration_policy_v1.dart';
import 'policies/pipeline_execution_policy_v1.dart';
import 'policies/pipeline_integration_policy_v1.dart';
import 'resolved_cicd_integration_sources.dart';

/// Resolves CI/CD integration source artifacts without executing origin engines.
class CicdIntegrationSourceResolver {
  CicdIntegrationSourceResolver({
    required ReleaseEvidenceProvider releaseEvidenceProvider,
    required ReleaseSupplyChainProvider releaseSupplyChainProvider,
    CicdIntegrationArtifactRegistry? artifactRegistry,
    PipelineIntegrationPolicyRegistry? pipelineIntegrationPolicyRegistry,
    PipelineExecutionPolicyRegistry? pipelineExecutionPolicyRegistry,
    DeploymentIntegrationPolicyRegistry? deploymentIntegrationPolicyRegistry,
    CicdIntegrationCanonicalSerializer? serializer,
  })  : _releaseEvidenceProvider = releaseEvidenceProvider,
        _releaseSupplyChainProvider = releaseSupplyChainProvider,
        _artifactRegistry =
            artifactRegistry ?? CicdIntegrationArtifactRegistry(),
        _pipelineIntegrationPolicyRegistry =
            pipelineIntegrationPolicyRegistry ??
                PipelineIntegrationPolicyRegistry(),
        _pipelineExecutionPolicyRegistry = pipelineExecutionPolicyRegistry ??
            PipelineExecutionPolicyRegistry(),
        _deploymentIntegrationPolicyRegistry =
            deploymentIntegrationPolicyRegistry ??
                DeploymentIntegrationPolicyRegistry(),
        _serializer = serializer ?? const CicdIntegrationCanonicalSerializer();

  final ReleaseEvidenceProvider _releaseEvidenceProvider;
  final ReleaseSupplyChainProvider _releaseSupplyChainProvider;
  final CicdIntegrationArtifactRegistry _artifactRegistry;
  final PipelineIntegrationPolicyRegistry _pipelineIntegrationPolicyRegistry;
  final PipelineExecutionPolicyRegistry _pipelineExecutionPolicyRegistry;
  final DeploymentIntegrationPolicyRegistry
      _deploymentIntegrationPolicyRegistry;
  final CicdIntegrationCanonicalSerializer _serializer;

  Future<ResolvedCicdIntegrationSources> resolveAll(
    CicdIntegrationRequest request, {
    RegisteredPipelineIntegrationPolicy? injectedPipelineIntegrationPolicy,
    RegisteredPipelineExecutionPolicy? injectedPipelineExecutionPolicy,
    RegisteredDeploymentIntegrationPolicy? injectedDeploymentIntegrationPolicy,
  }) async {
    final refs = <CicdIntegrationSourceReference>[];
    final warnings = <CicdIntegrationWarning>[];
    final errors = <CicdIntegrationError>[];
    final limitations = <CicdIntegrationLimitation>[];
    final hints = <String>[];

    final resolved = <String>[];
    final unresolved = <String>[];
    final injected = <String>[];

    final pipelineDefinition =
        resolvePipelineDefinition(request, refs, limitations);
    _trackResolution(pipelineDefinition, resolved, unresolved, injected);

    final pipelineExecution =
        resolvePipelineExecution(request, refs, limitations);
    _trackResolution(pipelineExecution, resolved, unresolved, injected);

    final pipelineExecutionResult =
        resolvePipelineExecutionResult(request, refs, limitations);
    _trackResolution(pipelineExecutionResult, resolved, unresolved, injected);

    final deploymentPlan = resolveDeploymentPlan(request, refs, limitations);
    _trackResolution(deploymentPlan, resolved, unresolved, injected);

    final deploymentResult =
        resolveDeploymentResult(request, refs, limitations);
    _trackResolution(deploymentResult, resolved, unresolved, injected);

    final releaseEvidenceBundle = await resolveReleaseEvidenceBundle(
      request,
      refs,
      limitations,
    );
    _trackResolution(releaseEvidenceBundle, resolved, unresolved, injected);

    final releaseSupplyChainSnapshot = await resolveReleaseSupplyChainSnapshot(
      request,
      refs,
      limitations,
    );
    _trackResolution(
        releaseSupplyChainSnapshot, resolved, unresolved, injected);

    final pipelineIntegrationPolicy = resolvePipelineIntegrationPolicy(
      request,
      refs,
      injectedPipelineIntegrationPolicy,
      limitations,
    );
    _trackResolution(pipelineIntegrationPolicy, resolved, unresolved, injected);

    final pipelineExecutionPolicy = resolvePipelineExecutionPolicy(
      request,
      refs,
      injectedPipelineExecutionPolicy,
      limitations,
    );
    _trackResolution(pipelineExecutionPolicy, resolved, unresolved, injected);

    final deploymentIntegrationPolicy = resolveDeploymentIntegrationPolicy(
      request,
      refs,
      injectedDeploymentIntegrationPolicy,
      limitations,
    );
    _trackResolution(
        deploymentIntegrationPolicy, resolved, unresolved, injected);

    _checkProjectMismatch(request, releaseEvidenceBundle, hints, limitations);
    _checkExecutionDefinitionLink(
      pipelineDefinition,
      pipelineExecution,
      hints,
      limitations,
    );
    _checkDeploymentExecutionLink(
      pipelineExecution,
      deploymentPlan,
      hints,
      limitations,
    );

    refs.sort((a, b) => a.sourceType.compareTo(b.sourceType));

    final summary = CicdIntegrationSourceResolutionSummary(
      resolvedSources: resolved,
      unresolvedSources: unresolved,
      injectedSources: injected,
      fingerprint: _serializer.sourceReferencesFingerprint(refs),
    );

    return ResolvedCicdIntegrationSources(
      pipelineDefinition: pipelineDefinition,
      pipelineExecution: pipelineExecution,
      pipelineExecutionResult: pipelineExecutionResult,
      deploymentPlan: deploymentPlan,
      deploymentResult: deploymentResult,
      releaseEvidenceBundle: releaseEvidenceBundle,
      releaseSupplyChainSnapshot: releaseSupplyChainSnapshot,
      pipelineIntegrationPolicy: pipelineIntegrationPolicy,
      pipelineExecutionPolicy: pipelineExecutionPolicy,
      deploymentIntegrationPolicy: deploymentIntegrationPolicy,
      sourceReferences: refs,
      resolutionSummary: summary,
      warnings: warnings,
      errors: errors,
      limitations: limitations,
      compatibilityHints: hints,
    );
  }

  ResolvedCicdIntegrationSource<PipelineDefinition> resolvePipelineDefinition(
    CicdIntegrationRequest request,
    List<CicdIntegrationSourceReference> refs,
    List<CicdIntegrationLimitation> limitations,
  ) {
    if (request.pipelineDefinition != null) {
      final definition = request.pipelineDefinition!;
      refs.add(
        _definitionRef(
          definition,
          CicdIntegrationSourceResolutionMode.injected,
        ),
      );
      return _availableDefinition(definition, refs.last);
    }
    if (request.pipelineDefinitionId != null) {
      final loaded =
          _artifactRegistry.loadDefinition(request.pipelineDefinitionId!);
      if (loaded != null) {
        refs.add(
          _definitionRef(loaded, CicdIntegrationSourceResolutionMode.byId),
        );
        return _availableDefinition(loaded, refs.last);
      }
      refs.add(
        _unavailableRef(
          CicdIntegrationSourceType.pipelineDefinition,
          request.pipelineDefinitionId!,
          CicdIntegrationSourceResolutionMode.byId,
        ),
      );
      limitations.add(
        CicdIntegrationLimitation(
          limitationId: 'missing-pipeline-definition',
          code: 'no-physical-persistence',
          description:
              'Pipeline definition ${request.pipelineDefinitionId} unavailable',
          impact: 'Pipeline integration assembly may be incomplete',
        ),
      );
      return _unavailableDefinition(request.pipelineDefinitionId);
    }
    if (request.useLatest) {
      final loaded = _artifactRegistry.latestDefinition(
        projectId: request.projectId,
      );
      if (loaded != null) {
        refs.add(
          _definitionRef(loaded, CicdIntegrationSourceResolutionMode.latest),
        );
        return _availableDefinition(loaded, refs.last);
      }
      limitations.add(
        const CicdIntegrationLimitation(
          limitationId: 'latest-pipeline-definition-missing',
          code: 'no-physical-persistence',
          description: 'Latest pipeline definition unavailable',
          impact: 'Pipeline integration assembly may be incomplete',
        ),
      );
    }
    return _notRequestedDefinition();
  }

  ResolvedCicdIntegrationSource<PipelineExecution> resolvePipelineExecution(
    CicdIntegrationRequest request,
    List<CicdIntegrationSourceReference> refs,
    List<CicdIntegrationLimitation> limitations,
  ) {
    if (request.pipelineExecution != null) {
      final execution = request.pipelineExecution!;
      refs.add(
        _executionRef(execution, CicdIntegrationSourceResolutionMode.injected),
      );
      return _availableExecution(execution, refs.last);
    }
    if (request.pipelineExecutionId != null) {
      final loaded =
          _artifactRegistry.loadExecution(request.pipelineExecutionId!);
      if (loaded != null) {
        refs.add(
          _executionRef(loaded, CicdIntegrationSourceResolutionMode.byId),
        );
        return _availableExecution(loaded, refs.last);
      }
      refs.add(
        _unavailableRef(
          CicdIntegrationSourceType.pipelineExecution,
          request.pipelineExecutionId!,
          CicdIntegrationSourceResolutionMode.byId,
        ),
      );
      limitations.add(
        CicdIntegrationLimitation(
          limitationId: 'missing-pipeline-execution',
          code: 'no-physical-persistence',
          description:
              'Pipeline execution ${request.pipelineExecutionId} unavailable',
          impact: 'Execution evidence may be unavailable',
        ),
      );
      return _unavailableExecution(request.pipelineExecutionId);
    }
    if (request.useLatest) {
      final loaded = _artifactRegistry.latestExecution(
        projectId: request.projectId,
      );
      if (loaded != null) {
        refs.add(
          _executionRef(loaded, CicdIntegrationSourceResolutionMode.latest),
        );
        return _availableExecution(loaded, refs.last);
      }
      limitations.add(
        const CicdIntegrationLimitation(
          limitationId: 'latest-pipeline-execution-missing',
          code: 'no-physical-persistence',
          description: 'Latest pipeline execution unavailable',
          impact: 'Execution evidence may be unavailable',
        ),
      );
    }
    return _notRequestedExecution();
  }

  ResolvedCicdIntegrationSource<PipelineExecutionResult>
      resolvePipelineExecutionResult(
    CicdIntegrationRequest request,
    List<CicdIntegrationSourceReference> refs,
    List<CicdIntegrationLimitation> limitations,
  ) {
    if (request.pipelineExecutionResult != null) {
      final result = request.pipelineExecutionResult!;
      refs.add(
        _executionResultRef(
            result, CicdIntegrationSourceResolutionMode.injected),
      );
      return _availableExecutionResult(result, refs.last);
    }
    if (request.useLatest) {
      final loaded = _artifactRegistry.latestExecutionResult(
        projectId: request.projectId,
      );
      if (loaded != null) {
        refs.add(
          _executionResultRef(
            loaded,
            CicdIntegrationSourceResolutionMode.latest,
          ),
        );
        return _availableExecutionResult(loaded, refs.last);
      }
      limitations.add(
        const CicdIntegrationLimitation(
          limitationId: 'latest-pipeline-execution-result-missing',
          code: 'no-physical-persistence',
          description: 'Latest pipeline execution result unavailable',
          impact: 'Execution result evidence may be unavailable',
        ),
      );
    }
    return _notRequestedExecutionResult();
  }

  ResolvedCicdIntegrationSource<DeploymentPlan> resolveDeploymentPlan(
    CicdIntegrationRequest request,
    List<CicdIntegrationSourceReference> refs,
    List<CicdIntegrationLimitation> limitations,
  ) {
    if (request.deploymentPlan != null) {
      final plan = request.deploymentPlan!;
      refs.add(_planRef(plan, CicdIntegrationSourceResolutionMode.injected));
      return _availablePlan(plan, refs.last);
    }
    if (request.deploymentPlanId != null) {
      final loaded = _artifactRegistry.loadDeploymentPlan(
        request.deploymentPlanId!,
      );
      if (loaded != null) {
        refs.add(_planRef(loaded, CicdIntegrationSourceResolutionMode.byId));
        return _availablePlan(loaded, refs.last);
      }
      refs.add(
        _unavailableRef(
          CicdIntegrationSourceType.deploymentPlan,
          request.deploymentPlanId!,
          CicdIntegrationSourceResolutionMode.byId,
        ),
      );
      limitations.add(
        CicdIntegrationLimitation(
          limitationId: 'missing-deployment-plan',
          code: 'no-physical-persistence',
          description:
              'Deployment plan ${request.deploymentPlanId} unavailable',
          impact: 'Deployment integration may be limited',
        ),
      );
      return _unavailablePlan(request.deploymentPlanId);
    }
    if (request.useLatest) {
      final loaded = _artifactRegistry.latestDeploymentPlan(
        projectId: request.projectId,
      );
      if (loaded != null) {
        refs.add(_planRef(loaded, CicdIntegrationSourceResolutionMode.latest));
        return _availablePlan(loaded, refs.last);
      }
      limitations.add(
        const CicdIntegrationLimitation(
          limitationId: 'latest-deployment-plan-missing',
          code: 'no-physical-persistence',
          description: 'Latest deployment plan unavailable',
          impact: 'Deployment integration may be limited',
        ),
      );
    }
    return _notRequestedPlan();
  }

  ResolvedCicdIntegrationSource<DeploymentResult> resolveDeploymentResult(
    CicdIntegrationRequest request,
    List<CicdIntegrationSourceReference> refs,
    List<CicdIntegrationLimitation> limitations,
  ) {
    if (request.deploymentResult != null) {
      final result = request.deploymentResult!;
      refs.add(
        _deploymentResultRef(
            result, CicdIntegrationSourceResolutionMode.injected),
      );
      return _availableDeploymentResult(result, refs.last);
    }
    if (request.useLatest) {
      final loaded = _artifactRegistry.latestDeploymentResult(
        projectId: request.projectId,
      );
      if (loaded != null) {
        refs.add(
          _deploymentResultRef(
            loaded,
            CicdIntegrationSourceResolutionMode.latest,
          ),
        );
        return _availableDeploymentResult(loaded, refs.last);
      }
      limitations.add(
        const CicdIntegrationLimitation(
          limitationId: 'latest-deployment-result-missing',
          code: 'no-physical-persistence',
          description: 'Latest deployment result unavailable',
          impact: 'Deployment result evidence may be unavailable',
        ),
      );
    }
    return _notRequestedDeploymentResult();
  }

  Future<ResolvedCicdIntegrationSource<ReleaseEvidenceBundle>>
      resolveReleaseEvidenceBundle(
    CicdIntegrationRequest request,
    List<CicdIntegrationSourceReference> refs,
    List<CicdIntegrationLimitation> limitations,
  ) async {
    if (request.releaseEvidenceBundle != null) {
      final bundle = request.releaseEvidenceBundle!;
      refs.add(
          _evidenceRef(bundle, CicdIntegrationSourceResolutionMode.injected));
      return _availableEvidence(bundle, refs.last);
    }
    if (request.useLatest) {
      final loaded = await _releaseEvidenceProvider.latest(
        projectId: request.projectId,
        releaseId: request.releaseId,
      );
      if (loaded != null) {
        refs.add(
          _evidenceRef(loaded, CicdIntegrationSourceResolutionMode.latest),
        );
        return _availableEvidence(loaded, refs.last);
      }
      limitations.add(
        const CicdIntegrationLimitation(
          limitationId: 'latest-evidence-bundle-missing',
          code: 'no-physical-persistence',
          description: 'Latest release evidence bundle unavailable',
          impact: 'Release evidence linkage may be incomplete',
        ),
      );
    }
    return _notRequestedEvidence();
  }

  Future<ResolvedCicdIntegrationSource<ReleaseSupplyChainSnapshot>>
      resolveReleaseSupplyChainSnapshot(
    CicdIntegrationRequest request,
    List<CicdIntegrationSourceReference> refs,
    List<CicdIntegrationLimitation> limitations,
  ) async {
    if (request.releaseSupplyChainSnapshot != null) {
      final snapshot = request.releaseSupplyChainSnapshot!;
      refs.add(
        _supplyChainRef(snapshot, CicdIntegrationSourceResolutionMode.injected),
      );
      return _availableSupplyChain(snapshot, refs.last);
    }
    if (request.useLatest) {
      final loaded = await _releaseSupplyChainProvider.latest(
        projectId: request.projectId,
        releaseId: request.releaseId,
      );
      if (loaded != null) {
        refs.add(
          _supplyChainRef(loaded, CicdIntegrationSourceResolutionMode.latest),
        );
        return _availableSupplyChain(loaded, refs.last);
      }
      limitations.add(
        const CicdIntegrationLimitation(
          limitationId: 'latest-supply-chain-missing',
          code: 'no-physical-persistence',
          description: 'Latest release supply chain snapshot unavailable',
          impact: 'Supply chain linkage may be incomplete',
        ),
      );
    }
    return _notRequestedSupplyChain();
  }

  ResolvedCicdIntegrationSource<RegisteredPipelineIntegrationPolicy>
      resolvePipelineIntegrationPolicy(
    CicdIntegrationRequest request,
    List<CicdIntegrationSourceReference> refs,
    RegisteredPipelineIntegrationPolicy? injectedPolicy,
    List<CicdIntegrationLimitation> limitations,
  ) {
    if (injectedPolicy != null) {
      return _resolvedPipelineIntegrationPolicy(
        policy: injectedPolicy,
        mode: CicdIntegrationSourceResolutionMode.injected,
        refs: refs,
      );
    }
    final policyId = request.pipelineIntegrationPolicyId ??
        PipelineIntegrationPolicyV1.policyId;
    final policy = _pipelineIntegrationPolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.pipelineIntegrationPolicyVersion,
      allowCandidate: true,
    );
    if (policy != null) {
      return _resolvedPipelineIntegrationPolicy(
        policy: policy,
        mode: CicdIntegrationSourceResolutionMode.byId,
        refs: refs,
      );
    }
    limitations.add(
      CicdIntegrationLimitation(
        limitationId: 'missing-pipeline-integration-policy',
        code: 'no-physical-persistence',
        description: 'Pipeline integration policy $policyId unavailable',
        impact: 'CI/CD integration collection cannot proceed',
      ),
    );
    return _unavailablePolicy<RegisteredPipelineIntegrationPolicy>(
      CicdIntegrationSourceType.pipelineIntegrationPolicy,
      policyId,
    );
  }

  ResolvedCicdIntegrationSource<RegisteredPipelineExecutionPolicy>
      resolvePipelineExecutionPolicy(
    CicdIntegrationRequest request,
    List<CicdIntegrationSourceReference> refs,
    RegisteredPipelineExecutionPolicy? injectedPolicy,
    List<CicdIntegrationLimitation> limitations,
  ) {
    if (injectedPolicy != null) {
      return _resolvedPipelineExecutionPolicy(
        policy: injectedPolicy,
        mode: CicdIntegrationSourceResolutionMode.injected,
        refs: refs,
      );
    }
    final policyId =
        request.pipelineExecutionPolicyId ?? PipelineExecutionPolicyV1.policyId;
    final policy = _pipelineExecutionPolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.pipelineExecutionPolicyVersion,
      allowCandidate: true,
    );
    if (policy != null) {
      return _resolvedPipelineExecutionPolicy(
        policy: policy,
        mode: CicdIntegrationSourceResolutionMode.byId,
        refs: refs,
      );
    }
    limitations.add(
      CicdIntegrationLimitation(
        limitationId: 'missing-pipeline-execution-policy',
        code: 'no-physical-persistence',
        description: 'Pipeline execution policy $policyId unavailable',
        impact: 'Execution validation may be limited',
      ),
    );
    return _unavailablePolicy<RegisteredPipelineExecutionPolicy>(
      CicdIntegrationSourceType.pipelineExecutionPolicy,
      policyId,
    );
  }

  ResolvedCicdIntegrationSource<RegisteredDeploymentIntegrationPolicy>
      resolveDeploymentIntegrationPolicy(
    CicdIntegrationRequest request,
    List<CicdIntegrationSourceReference> refs,
    RegisteredDeploymentIntegrationPolicy? injectedPolicy,
    List<CicdIntegrationLimitation> limitations,
  ) {
    if (injectedPolicy != null) {
      return _resolvedDeploymentIntegrationPolicy(
        policy: injectedPolicy,
        mode: CicdIntegrationSourceResolutionMode.injected,
        refs: refs,
      );
    }
    final policyId = request.deploymentIntegrationPolicyId ??
        DeploymentIntegrationPolicyV1.policyId;
    final policy = _deploymentIntegrationPolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.deploymentIntegrationPolicyVersion,
      allowCandidate: true,
    );
    if (policy != null) {
      return _resolvedDeploymentIntegrationPolicy(
        policy: policy,
        mode: CicdIntegrationSourceResolutionMode.byId,
        refs: refs,
      );
    }
    limitations.add(
      CicdIntegrationLimitation(
        limitationId: 'missing-deployment-integration-policy',
        code: 'no-physical-persistence',
        description: 'Deployment integration policy $policyId unavailable',
        impact: 'Deployment validation may be limited',
      ),
    );
    return _unavailablePolicy<RegisteredDeploymentIntegrationPolicy>(
      CicdIntegrationSourceType.deploymentIntegrationPolicy,
      policyId,
    );
  }

  void _checkProjectMismatch(
    CicdIntegrationRequest request,
    ResolvedCicdIntegrationSource<ReleaseEvidenceBundle> evidence,
    List<String> hints,
    List<CicdIntegrationLimitation> limitations,
  ) {
    if (!evidence.isAvailable) return;
    final evidenceProject = evidence.resolvedArtifact!.metadata.projectId;
    if (evidenceProject != request.projectId) {
      hints.add(
        'Project mismatch on releaseEvidence: $evidenceProject != ${request.projectId}',
      );
      limitations.add(
        CicdIntegrationLimitation(
          limitationId: 'project-mismatch-evidence',
          code: 'historical-data-incomplete',
          description:
              'Release evidence projectId $evidenceProject differs from request ${request.projectId}',
          impact: 'Cross-artifact consistency may be reduced',
        ),
      );
    }
  }

  void _checkExecutionDefinitionLink(
    ResolvedCicdIntegrationSource<PipelineDefinition> definition,
    ResolvedCicdIntegrationSource<PipelineExecution> execution,
    List<String> hints,
    List<CicdIntegrationLimitation> limitations,
  ) {
    if (!definition.isAvailable || !execution.isAvailable) return;
    final expected = definition.resolvedArtifact!.definitionId;
    final actual = execution.resolvedArtifact!.definitionId;
    if (actual != expected) {
      hints.add('Execution definition mismatch: $actual != $expected');
      limitations.add(
        const CicdIntegrationLimitation(
          limitationId: 'execution-definition-mismatch',
          code: 'historical-data-incomplete',
          description:
              'Pipeline execution definitionId differs from definition',
          impact: 'Execution linkage may be inconsistent',
        ),
      );
    }
  }

  void _checkDeploymentExecutionLink(
    ResolvedCicdIntegrationSource<PipelineExecution> execution,
    ResolvedCicdIntegrationSource<DeploymentPlan> plan,
    List<String> hints,
    List<CicdIntegrationLimitation> limitations,
  ) {
    if (!execution.isAvailable || !plan.isAvailable) return;
    final executionId = execution.resolvedArtifact!.executionId;
    final planExecutionId = plan.resolvedArtifact!.pipelineExecutionId;
    if (planExecutionId != null && planExecutionId != executionId) {
      hints.add(
        'Deployment plan execution mismatch: $planExecutionId != $executionId',
      );
      limitations.add(
        const CicdIntegrationLimitation(
          limitationId: 'deployment-execution-mismatch',
          code: 'historical-data-incomplete',
          description:
              'Deployment plan pipelineExecutionId differs from execution',
          impact: 'Deployment linkage may be inconsistent',
        ),
      );
    }
  }

  void _trackResolution(
    ResolvedCicdIntegrationSource<dynamic> source,
    List<String> resolved,
    List<String> unresolved,
    List<String> injected,
  ) {
    final name = source.sourceType.wireName;
    switch (source.resolutionMode) {
      case CicdIntegrationSourceResolutionMode.injected:
        if (source.isAvailable) {
          injected.add(name);
          resolved.add(name);
        }
      case CicdIntegrationSourceResolutionMode.byId:
        if (source.isAvailable) {
          resolved.add(name);
        } else if (source.state != CicdIntegrationSourceState.notRequested) {
          unresolved.add(name);
        }
      case CicdIntegrationSourceResolutionMode.latest:
        if (source.isAvailable) {
          resolved.add(name);
        } else {
          unresolved.add(name);
        }
      case CicdIntegrationSourceResolutionMode.notRequested:
        break;
    }
  }

  ResolvedCicdIntegrationSource<RegisteredPipelineIntegrationPolicy>
      _resolvedPipelineIntegrationPolicy({
    required RegisteredPipelineIntegrationPolicy policy,
    required CicdIntegrationSourceResolutionMode mode,
    required List<CicdIntegrationSourceReference> refs,
  }) {
    final fingerprint = policy.metadata.fingerprint ?? policy.metadata.policyId;
    refs.add(
      CicdIntegrationSourceReference(
        sourceType:
            CicdIntegrationSourceType.pipelineIntegrationPolicy.wireName,
        resolutionMode: mode.wireName,
        requestedId: policy.metadata.policyId,
        resolvedId: policy.metadata.policyId,
        fingerprint: fingerprint,
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
      ),
    );
    return ResolvedCicdIntegrationSource<RegisteredPipelineIntegrationPolicy>(
      sourceType: CicdIntegrationSourceType.pipelineIntegrationPolicy,
      resolutionMode: mode,
      state: CicdIntegrationSourceState.available,
      resolvedArtifact: policy,
      resolvedId: policy.metadata.policyId,
      fingerprint: fingerprint,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
    );
  }

  ResolvedCicdIntegrationSource<RegisteredPipelineExecutionPolicy>
      _resolvedPipelineExecutionPolicy({
    required RegisteredPipelineExecutionPolicy policy,
    required CicdIntegrationSourceResolutionMode mode,
    required List<CicdIntegrationSourceReference> refs,
  }) {
    final fingerprint = policy.metadata.fingerprint ?? policy.metadata.policyId;
    refs.add(
      CicdIntegrationSourceReference(
        sourceType: CicdIntegrationSourceType.pipelineExecutionPolicy.wireName,
        resolutionMode: mode.wireName,
        requestedId: policy.metadata.policyId,
        resolvedId: policy.metadata.policyId,
        fingerprint: fingerprint,
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
      ),
    );
    return ResolvedCicdIntegrationSource<RegisteredPipelineExecutionPolicy>(
      sourceType: CicdIntegrationSourceType.pipelineExecutionPolicy,
      resolutionMode: mode,
      state: CicdIntegrationSourceState.available,
      resolvedArtifact: policy,
      resolvedId: policy.metadata.policyId,
      fingerprint: fingerprint,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
    );
  }

  ResolvedCicdIntegrationSource<RegisteredDeploymentIntegrationPolicy>
      _resolvedDeploymentIntegrationPolicy({
    required RegisteredDeploymentIntegrationPolicy policy,
    required CicdIntegrationSourceResolutionMode mode,
    required List<CicdIntegrationSourceReference> refs,
  }) {
    final fingerprint = policy.metadata.fingerprint ?? policy.metadata.policyId;
    refs.add(
      CicdIntegrationSourceReference(
        sourceType:
            CicdIntegrationSourceType.deploymentIntegrationPolicy.wireName,
        resolutionMode: mode.wireName,
        requestedId: policy.metadata.policyId,
        resolvedId: policy.metadata.policyId,
        fingerprint: fingerprint,
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
      ),
    );
    return ResolvedCicdIntegrationSource<RegisteredDeploymentIntegrationPolicy>(
      sourceType: CicdIntegrationSourceType.deploymentIntegrationPolicy,
      resolutionMode: mode,
      state: CicdIntegrationSourceState.available,
      resolvedArtifact: policy,
      resolvedId: policy.metadata.policyId,
      fingerprint: fingerprint,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
    );
  }

  ResolvedCicdIntegrationSource<PipelineDefinition> _availableDefinition(
    PipelineDefinition definition,
    CicdIntegrationSourceReference ref,
  ) {
    return ResolvedCicdIntegrationSource<PipelineDefinition>(
      sourceType: CicdIntegrationSourceType.pipelineDefinition,
      resolutionMode: CicdIntegrationSourceResolutionModeX.fromWireName(
        ref.resolutionMode,
      ),
      state: CicdIntegrationSourceState.available,
      resolvedArtifact: definition,
      resolvedId: ref.resolvedId,
      fingerprint: ref.fingerprint,
      projectId: ref.projectId,
      releaseId: ref.releaseId,
    );
  }

  ResolvedCicdIntegrationSource<PipelineDefinition> _unavailableDefinition(
    String? requestedId,
  ) {
    return ResolvedCicdIntegrationSource<PipelineDefinition>(
      sourceType: CicdIntegrationSourceType.pipelineDefinition,
      resolutionMode: CicdIntegrationSourceResolutionMode.injected,
      state: CicdIntegrationSourceState.unavailable,
      requestedId: requestedId,
    );
  }

  ResolvedCicdIntegrationSource<PipelineDefinition> _notRequestedDefinition() {
    return const ResolvedCicdIntegrationSource<PipelineDefinition>(
      sourceType: CicdIntegrationSourceType.pipelineDefinition,
      resolutionMode: CicdIntegrationSourceResolutionMode.notRequested,
      state: CicdIntegrationSourceState.notRequested,
    );
  }

  ResolvedCicdIntegrationSource<PipelineExecution> _availableExecution(
    PipelineExecution execution,
    CicdIntegrationSourceReference ref,
  ) {
    return ResolvedCicdIntegrationSource<PipelineExecution>(
      sourceType: CicdIntegrationSourceType.pipelineExecution,
      resolutionMode: CicdIntegrationSourceResolutionModeX.fromWireName(
        ref.resolutionMode,
      ),
      state: CicdIntegrationSourceState.available,
      resolvedArtifact: execution,
      resolvedId: ref.resolvedId,
      fingerprint: ref.fingerprint,
      projectId: ref.projectId,
      releaseId: ref.releaseId,
    );
  }

  ResolvedCicdIntegrationSource<PipelineExecution> _unavailableExecution(
    String? requestedId,
  ) {
    return ResolvedCicdIntegrationSource<PipelineExecution>(
      sourceType: CicdIntegrationSourceType.pipelineExecution,
      resolutionMode: CicdIntegrationSourceResolutionMode.injected,
      state: CicdIntegrationSourceState.unavailable,
      requestedId: requestedId,
    );
  }

  ResolvedCicdIntegrationSource<PipelineExecution> _notRequestedExecution() {
    return const ResolvedCicdIntegrationSource<PipelineExecution>(
      sourceType: CicdIntegrationSourceType.pipelineExecution,
      resolutionMode: CicdIntegrationSourceResolutionMode.notRequested,
      state: CicdIntegrationSourceState.notRequested,
    );
  }

  ResolvedCicdIntegrationSource<PipelineExecutionResult>
      _availableExecutionResult(
    PipelineExecutionResult result,
    CicdIntegrationSourceReference ref,
  ) {
    return ResolvedCicdIntegrationSource<PipelineExecutionResult>(
      sourceType: CicdIntegrationSourceType.pipelineExecutionResult,
      resolutionMode: CicdIntegrationSourceResolutionModeX.fromWireName(
        ref.resolutionMode,
      ),
      state: CicdIntegrationSourceState.available,
      resolvedArtifact: result,
      resolvedId: ref.resolvedId,
      fingerprint: ref.fingerprint,
    );
  }

  ResolvedCicdIntegrationSource<PipelineExecutionResult>
      _notRequestedExecutionResult() {
    return const ResolvedCicdIntegrationSource<PipelineExecutionResult>(
      sourceType: CicdIntegrationSourceType.pipelineExecutionResult,
      resolutionMode: CicdIntegrationSourceResolutionMode.notRequested,
      state: CicdIntegrationSourceState.notRequested,
    );
  }

  ResolvedCicdIntegrationSource<DeploymentPlan> _availablePlan(
    DeploymentPlan plan,
    CicdIntegrationSourceReference ref,
  ) {
    return ResolvedCicdIntegrationSource<DeploymentPlan>(
      sourceType: CicdIntegrationSourceType.deploymentPlan,
      resolutionMode: CicdIntegrationSourceResolutionModeX.fromWireName(
        ref.resolutionMode,
      ),
      state: CicdIntegrationSourceState.available,
      resolvedArtifact: plan,
      resolvedId: ref.resolvedId,
      fingerprint: ref.fingerprint,
    );
  }

  ResolvedCicdIntegrationSource<DeploymentPlan> _unavailablePlan(
    String? requestedId,
  ) {
    return ResolvedCicdIntegrationSource<DeploymentPlan>(
      sourceType: CicdIntegrationSourceType.deploymentPlan,
      resolutionMode: CicdIntegrationSourceResolutionMode.injected,
      state: CicdIntegrationSourceState.unavailable,
      requestedId: requestedId,
    );
  }

  ResolvedCicdIntegrationSource<DeploymentPlan> _notRequestedPlan() {
    return const ResolvedCicdIntegrationSource<DeploymentPlan>(
      sourceType: CicdIntegrationSourceType.deploymentPlan,
      resolutionMode: CicdIntegrationSourceResolutionMode.notRequested,
      state: CicdIntegrationSourceState.notRequested,
    );
  }

  ResolvedCicdIntegrationSource<DeploymentResult> _availableDeploymentResult(
    DeploymentResult result,
    CicdIntegrationSourceReference ref,
  ) {
    return ResolvedCicdIntegrationSource<DeploymentResult>(
      sourceType: CicdIntegrationSourceType.deploymentResult,
      resolutionMode: CicdIntegrationSourceResolutionModeX.fromWireName(
        ref.resolutionMode,
      ),
      state: CicdIntegrationSourceState.available,
      resolvedArtifact: result,
      resolvedId: ref.resolvedId,
      fingerprint: ref.fingerprint,
    );
  }

  ResolvedCicdIntegrationSource<DeploymentResult>
      _notRequestedDeploymentResult() {
    return const ResolvedCicdIntegrationSource<DeploymentResult>(
      sourceType: CicdIntegrationSourceType.deploymentResult,
      resolutionMode: CicdIntegrationSourceResolutionMode.notRequested,
      state: CicdIntegrationSourceState.notRequested,
    );
  }

  ResolvedCicdIntegrationSource<ReleaseEvidenceBundle> _availableEvidence(
    ReleaseEvidenceBundle bundle,
    CicdIntegrationSourceReference ref,
  ) {
    return ResolvedCicdIntegrationSource<ReleaseEvidenceBundle>(
      sourceType: CicdIntegrationSourceType.releaseEvidenceBundle,
      resolutionMode: CicdIntegrationSourceResolutionModeX.fromWireName(
        ref.resolutionMode,
      ),
      state: CicdIntegrationSourceState.available,
      resolvedArtifact: bundle,
      resolvedId: ref.resolvedId,
      fingerprint: ref.fingerprint,
      projectId: ref.projectId,
      releaseId: ref.releaseId,
    );
  }

  ResolvedCicdIntegrationSource<ReleaseEvidenceBundle> _notRequestedEvidence() {
    return const ResolvedCicdIntegrationSource<ReleaseEvidenceBundle>(
      sourceType: CicdIntegrationSourceType.releaseEvidenceBundle,
      resolutionMode: CicdIntegrationSourceResolutionMode.notRequested,
      state: CicdIntegrationSourceState.notRequested,
    );
  }

  ResolvedCicdIntegrationSource<ReleaseSupplyChainSnapshot>
      _availableSupplyChain(
    ReleaseSupplyChainSnapshot snapshot,
    CicdIntegrationSourceReference ref,
  ) {
    return ResolvedCicdIntegrationSource<ReleaseSupplyChainSnapshot>(
      sourceType: CicdIntegrationSourceType.releaseSupplyChainSnapshot,
      resolutionMode: CicdIntegrationSourceResolutionModeX.fromWireName(
        ref.resolutionMode,
      ),
      state: CicdIntegrationSourceState.available,
      resolvedArtifact: snapshot,
      resolvedId: ref.resolvedId,
      fingerprint: ref.fingerprint,
      projectId: ref.projectId,
      releaseId: ref.releaseId,
    );
  }

  ResolvedCicdIntegrationSource<ReleaseSupplyChainSnapshot>
      _notRequestedSupplyChain() {
    return const ResolvedCicdIntegrationSource<ReleaseSupplyChainSnapshot>(
      sourceType: CicdIntegrationSourceType.releaseSupplyChainSnapshot,
      resolutionMode: CicdIntegrationSourceResolutionMode.notRequested,
      state: CicdIntegrationSourceState.notRequested,
    );
  }

  ResolvedCicdIntegrationSource<T> _unavailablePolicy<T>(
    CicdIntegrationSourceType sourceType,
    String policyId,
  ) {
    return ResolvedCicdIntegrationSource<T>(
      sourceType: sourceType,
      resolutionMode: CicdIntegrationSourceResolutionMode.injected,
      state: CicdIntegrationSourceState.unavailable,
      requestedId: policyId,
    );
  }

  CicdIntegrationSourceReference _definitionRef(
    PipelineDefinition definition,
    CicdIntegrationSourceResolutionMode mode,
  ) {
    return CicdIntegrationSourceReference(
      sourceType: CicdIntegrationSourceType.pipelineDefinition.wireName,
      resolutionMode: mode.wireName,
      requestedId: definition.definitionId,
      resolvedId: definition.definitionId,
      fingerprint: definition.fingerprint ?? definition.definitionId,
      projectId: definition.metadata['projectId'],
    );
  }

  CicdIntegrationSourceReference _executionRef(
    PipelineExecution execution,
    CicdIntegrationSourceResolutionMode mode,
  ) {
    return CicdIntegrationSourceReference(
      sourceType: CicdIntegrationSourceType.pipelineExecution.wireName,
      resolutionMode: mode.wireName,
      requestedId: execution.executionId,
      resolvedId: execution.executionId,
      fingerprint: execution.fingerprint ?? execution.executionId,
      projectId: execution.metadata['projectId'],
    );
  }

  CicdIntegrationSourceReference _executionResultRef(
    PipelineExecutionResult result,
    CicdIntegrationSourceResolutionMode mode,
  ) {
    return CicdIntegrationSourceReference(
      sourceType: CicdIntegrationSourceType.pipelineExecutionResult.wireName,
      resolutionMode: mode.wireName,
      requestedId: result.resultId,
      resolvedId: result.resultId,
      fingerprint: result.fingerprint ?? result.resultId,
    );
  }

  CicdIntegrationSourceReference _planRef(
    DeploymentPlan plan,
    CicdIntegrationSourceResolutionMode mode,
  ) {
    return CicdIntegrationSourceReference(
      sourceType: CicdIntegrationSourceType.deploymentPlan.wireName,
      resolutionMode: mode.wireName,
      requestedId: plan.planId,
      resolvedId: plan.planId,
      fingerprint: plan.fingerprint ?? plan.planId,
      projectId: plan.metadata['projectId'],
    );
  }

  CicdIntegrationSourceReference _deploymentResultRef(
    DeploymentResult result,
    CicdIntegrationSourceResolutionMode mode,
  ) {
    return CicdIntegrationSourceReference(
      sourceType: CicdIntegrationSourceType.deploymentResult.wireName,
      resolutionMode: mode.wireName,
      requestedId: result.resultId,
      resolvedId: result.resultId,
      fingerprint: result.fingerprint ?? result.resultId,
      projectId: result.metadata['projectId'],
    );
  }

  CicdIntegrationSourceReference _evidenceRef(
    ReleaseEvidenceBundle bundle,
    CicdIntegrationSourceResolutionMode mode,
  ) {
    return CicdIntegrationSourceReference(
      sourceType: CicdIntegrationSourceType.releaseEvidenceBundle.wireName,
      resolutionMode: mode.wireName,
      requestedId: bundle.metadata.bundleId,
      resolvedId: bundle.metadata.bundleId,
      fingerprint: bundle.fingerprint,
      projectId: bundle.metadata.projectId,
      releaseId: bundle.metadata.releaseId,
      policyId: bundle.metadata.policyId,
      policyVersion: bundle.metadata.policyVersion,
    );
  }

  CicdIntegrationSourceReference _supplyChainRef(
    ReleaseSupplyChainSnapshot snapshot,
    CicdIntegrationSourceResolutionMode mode,
  ) {
    return CicdIntegrationSourceReference(
      sourceType: CicdIntegrationSourceType.releaseSupplyChainSnapshot.wireName,
      resolutionMode: mode.wireName,
      requestedId: snapshot.metadata.supplyChainSnapshotId,
      resolvedId: snapshot.metadata.supplyChainSnapshotId,
      fingerprint: snapshot.fingerprint,
      projectId: snapshot.metadata.projectId,
      releaseId: snapshot.metadata.releaseId,
    );
  }

  CicdIntegrationSourceReference _unavailableRef(
    CicdIntegrationSourceType type,
    String artifactId,
    CicdIntegrationSourceResolutionMode mode,
  ) {
    return CicdIntegrationSourceReference(
      sourceType: type.wireName,
      resolutionMode: mode.wireName,
      requestedId: artifactId,
      resolvedId: artifactId,
      limitations: const ['source unavailable'],
    );
  }
}
