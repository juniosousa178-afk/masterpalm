import '../cicd_integration/cicd_integration_collector.dart';
import '../cicd_integration/cicd_integration_exceptions.dart';
import '../cicd_integration/cicd_integration_policy_registry.dart';
import '../cicd_integration/cicd_integration_snapshot_builder.dart';
import '../cicd_integration/cicd_integration_snapshot_validator.dart';
import '../cicd_integration/cicd_integration_source_resolver.dart';
import '../cicd_integration/policies/deployment_integration_policy_v1.dart';
import '../cicd_integration/policies/pipeline_execution_policy_v1.dart';
import '../cicd_integration/policies/pipeline_integration_policy_v1.dart';
import '../cicd_integration/resolved_cicd_integration_sources.dart';
import '../cicd_integration/stores/cicd_integration_store.dart';
import '../interfaces/cicd_integration_provider.dart';
import '../models/cicd_integration/cicd_integration_messages.dart';
import '../models/cicd_integration/cicd_integration_operational_enums.dart';
import '../models/cicd_integration/cicd_integration_policy_models.dart';
import '../models/cicd_integration/cicd_integration_query.dart';
import '../models/cicd_integration/cicd_integration_request.dart';
import '../models/cicd_integration/cicd_integration_result.dart';
import '../models/cicd_integration/cicd_integration_snapshot.dart';

/// Platform implementation of [CicdIntegrationProvider].
class PlatformCicdIntegrationProvider implements CicdIntegrationProvider {
  PlatformCicdIntegrationProvider({
    required CicdIntegrationSourceResolver sourceResolver,
    required PipelineIntegrationPolicyRegistry
        pipelineIntegrationPolicyRegistry,
    required PipelineExecutionPolicyRegistry pipelineExecutionPolicyRegistry,
    required DeploymentIntegrationPolicyRegistry
        deploymentIntegrationPolicyRegistry,
    required CicdIntegrationStore store,
    CicdIntegrationCollector? collector,
    CicdIntegrationSnapshotBuilder? snapshotBuilder,
    CicdIntegrationSnapshotValidator? snapshotValidator,
  })  : _sourceResolver = sourceResolver,
        _pipelineIntegrationPolicyRegistry = pipelineIntegrationPolicyRegistry,
        _pipelineExecutionPolicyRegistry = pipelineExecutionPolicyRegistry,
        _deploymentIntegrationPolicyRegistry =
            deploymentIntegrationPolicyRegistry,
        _store = store,
        _collector = collector ?? const CicdIntegrationCollector(),
        _snapshotBuilder = snapshotBuilder ?? CicdIntegrationSnapshotBuilder(),
        _snapshotValidator =
            snapshotValidator ?? const CicdIntegrationSnapshotValidator();

  final CicdIntegrationSourceResolver _sourceResolver;
  final PipelineIntegrationPolicyRegistry _pipelineIntegrationPolicyRegistry;
  final PipelineExecutionPolicyRegistry _pipelineExecutionPolicyRegistry;
  final DeploymentIntegrationPolicyRegistry
      _deploymentIntegrationPolicyRegistry;
  final CicdIntegrationStore _store;
  final CicdIntegrationCollector _collector;
  final CicdIntegrationSnapshotBuilder _snapshotBuilder;
  final CicdIntegrationSnapshotValidator _snapshotValidator;

  @override
  Future<CicdIntegrationResult> evaluate(CicdIntegrationRequest request) async {
    final pipelineIntegrationPolicy =
        _resolvePipelineIntegrationPolicy(request);
    if (pipelineIntegrationPolicy == null) {
      throw CicdIntegrationPolicyNotFoundException(
        request.pipelineIntegrationPolicyId ??
            PipelineIntegrationPolicyV1.policyId,
        policyVersion: request.pipelineIntegrationPolicyVersion,
      );
    }

    final pipelineExecutionPolicy = _resolvePipelineExecutionPolicy(request);
    if (pipelineExecutionPolicy == null) {
      throw CicdIntegrationPolicyNotFoundException(
        request.pipelineExecutionPolicyId ?? PipelineExecutionPolicyV1.policyId,
        policyVersion: request.pipelineExecutionPolicyVersion,
      );
    }

    final deploymentIntegrationPolicy =
        _resolveDeploymentIntegrationPolicy(request);
    if (deploymentIntegrationPolicy == null) {
      throw CicdIntegrationPolicyNotFoundException(
        request.deploymentIntegrationPolicyId ??
            DeploymentIntegrationPolicyV1.policyId,
        policyVersion: request.deploymentIntegrationPolicyVersion,
      );
    }

    final sources = await _sourceResolver.resolveAll(
      request,
      injectedPipelineIntegrationPolicy: pipelineIntegrationPolicy,
      injectedPipelineExecutionPolicy: pipelineExecutionPolicy,
      injectedDeploymentIntegrationPolicy: deploymentIntegrationPolicy,
    );

    return _evaluatePipeline(
      request: request,
      sources: sources,
      pipelineIntegrationPolicy: pipelineIntegrationPolicy,
      pipelineExecutionPolicy: pipelineExecutionPolicy,
      deploymentIntegrationPolicy: deploymentIntegrationPolicy,
    );
  }

  @override
  Future<CicdIntegrationResult> evaluateAndPublish(
    CicdIntegrationRequest request,
  ) async {
    final result = await evaluate(request);
    final snapshot = result.snapshot;
    if (snapshot == null) return result;

    final validation = _snapshotValidator.validate(snapshot);
    if (!validation.isValid) {
      return CicdIntegrationResult(
        status: CicdIntegrationResultStatus.failure,
        snapshot: snapshot,
        policyReference: result.policyReference,
        warnings: result.warnings,
        errors: [
          ...result.errors,
          ...validation.errors.map(
            (e) => CicdIntegrationError(
              errorId: 'validation-${e.hashCode}',
              code: 'snapshot-validation',
              message: e,
            ),
          ),
        ],
        limitations: result.limitations,
        sourceResolutionSummary: result.sourceResolutionSummary,
      );
    }

    final existing =
        await _store.load(snapshot.metadata.cicdIntegrationSnapshotId);
    if (existing != null) {
      return CicdIntegrationResult(
        status: result.status,
        snapshot: existing,
        policyReference: result.policyReference,
        warnings: result.warnings,
        errors: result.errors,
        limitations: result.limitations,
        sourceResolutionSummary: result.sourceResolutionSummary,
        publicationStatus: CicdIntegrationPublicationStatus.skipped,
      );
    }

    await _store.save(snapshot);
    final saved =
        await _store.load(snapshot.metadata.cicdIntegrationSnapshotId);
    return CicdIntegrationResult(
      status: result.status,
      snapshot: saved ?? snapshot,
      policyReference: result.policyReference,
      warnings: result.warnings,
      errors: result.errors,
      limitations: result.limitations,
      sourceResolutionSummary: result.sourceResolutionSummary,
      publicationStatus: CicdIntegrationPublicationStatus.published,
    );
  }

  @override
  Future<void> publish(CicdIntegrationSnapshot snapshot) async {
    await _store.save(snapshot);
  }

  @override
  Future<CicdIntegrationSnapshot?> load(String snapshotId) {
    return _store.load(snapshotId);
  }

  @override
  Future<CicdIntegrationSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? pipelineIntegrationPolicyId,
  }) {
    return _store.latest(
      projectId: projectId,
      releaseId: releaseId,
      pipelineIntegrationPolicyId: pipelineIntegrationPolicyId,
    );
  }

  @override
  Future<List<CicdIntegrationSnapshot>> query(CicdIntegrationQuery query) {
    return _store.query(query);
  }

  @override
  Future<void> invalidate(String snapshotId) async {
    if (!await _store.exists(snapshotId)) {
      throw CicdIntegrationNotFoundException(snapshotId);
    }
    await _store.invalidate(snapshotId);
  }

  Future<CicdIntegrationResult> _evaluatePipeline({
    required CicdIntegrationRequest request,
    required ResolvedCicdIntegrationSources sources,
    required RegisteredPipelineIntegrationPolicy pipelineIntegrationPolicy,
    required RegisteredPipelineExecutionPolicy pipelineExecutionPolicy,
    required RegisteredDeploymentIntegrationPolicy deploymentIntegrationPolicy,
  }) async {
    final context = CicdIntegrationEvaluationContext(
      request: request,
      sources: sources,
      pipelineIntegrationPolicy: pipelineIntegrationPolicy,
      pipelineExecutionPolicy: pipelineExecutionPolicy,
      deploymentIntegrationPolicy: deploymentIntegrationPolicy,
    );

    final collected = _collector.collect(context);
    final buildResult = _snapshotBuilder.build(
      context: context,
      collected: collected,
      evaluatedAt: request.requestedAt,
    );
    final snapshot = buildResult.snapshot;

    final validation = _snapshotValidator.validate(snapshot);

    final warnings = <CicdIntegrationWarning>[
      ...sources.warnings,
      ...validation.warnings.map(
        (w) => CicdIntegrationWarning(
          warningId: 'validation-${w.hashCode}',
          code: 'snapshot-validation',
          message: w,
        ),
      ),
    ];
    final errors = <CicdIntegrationError>[
      ...sources.errors,
      ...validation.errors.map(
        (e) => CicdIntegrationError(
          errorId: 'validation-${e.hashCode}',
          code: 'snapshot-validation',
          message: e,
        ),
      ),
    ];
    final limitations = <CicdIntegrationLimitation>[
      ...sources.limitations,
    ];

    var status = CicdIntegrationResultStatus.success;
    if (errors.isNotEmpty) {
      status = CicdIntegrationResultStatus.failure;
    } else if (limitations.isNotEmpty || warnings.isNotEmpty) {
      status = CicdIntegrationResultStatus.partial;
    }
    if (collected.artifacts.isEmpty) {
      status = CicdIntegrationResultStatus.unavailable;
    }

    return CicdIntegrationResult(
      status: status,
      snapshot: snapshot,
      policyReference: buildResult.policyReference,
      sourceResolutionSummary: sources.resolutionSummary,
      warnings: warnings,
      errors: errors,
      limitations: limitations,
    );
  }

  RegisteredPipelineIntegrationPolicy? _resolvePipelineIntegrationPolicy(
    CicdIntegrationRequest request,
  ) {
    final policyId = request.pipelineIntegrationPolicyId ??
        PipelineIntegrationPolicyV1.policyId;
    return _pipelineIntegrationPolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.pipelineIntegrationPolicyVersion,
      allowCandidate: true,
    );
  }

  RegisteredPipelineExecutionPolicy? _resolvePipelineExecutionPolicy(
    CicdIntegrationRequest request,
  ) {
    final policyId =
        request.pipelineExecutionPolicyId ?? PipelineExecutionPolicyV1.policyId;
    return _pipelineExecutionPolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.pipelineExecutionPolicyVersion,
      allowCandidate: true,
    );
  }

  RegisteredDeploymentIntegrationPolicy? _resolveDeploymentIntegrationPolicy(
    CicdIntegrationRequest request,
  ) {
    final policyId = request.deploymentIntegrationPolicyId ??
        DeploymentIntegrationPolicyV1.policyId;
    return _deploymentIntegrationPolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.deploymentIntegrationPolicyVersion,
      allowCandidate: true,
    );
  }
}
