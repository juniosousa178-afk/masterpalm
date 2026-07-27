import '../interfaces/quality_gate_provider.dart';
import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_policy.dart';
import '../models/quality_gate/quality_gate_query.dart';
import '../models/quality_gate/quality_gate_request.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';
import '../quality_gate/quality_gate_engine.dart';
import '../quality_gate/quality_gate_exceptions.dart';
import '../quality_gate/quality_gate_policy_registry.dart';
import '../quality_gate/quality_gate_snapshot_validator.dart';
import '../quality_gate/quality_gate_source_resolver.dart';
import '../quality_gate/stores/quality_gate_store.dart';

/// Platform implementation of [QualityGateProvider].
class PlatformQualityGateProvider implements QualityGateProvider {
  PlatformQualityGateProvider({
    required QualityGateEngine engine,
    required QualityGatePolicyRegistry policyRegistry,
    required QualityGateSourceResolver sourceResolver,
    required QualityGateStore store,
    QualityGateSnapshotValidator? snapshotValidator,
  })  : _engine = engine,
        _policyRegistry = policyRegistry,
        _sourceResolver = sourceResolver,
        _store = store,
        _snapshotValidator =
            snapshotValidator ?? const QualityGateSnapshotValidator();

  final QualityGateEngine _engine;
  final QualityGatePolicyRegistry _policyRegistry;
  final QualityGateSourceResolver _sourceResolver;
  final QualityGateStore _store;
  final QualityGateSnapshotValidator _snapshotValidator;

  @override
  Future<QualityGateResult> evaluate(QualityGateRequest request) async {
    final policy = _resolvePolicy(request);
    if (policy == null) {
      throw QualityGatePolicyNotFoundException(
        request.policyId ?? request.policy?.metadata.policyId ?? '',
        policyVersion: request.policyVersion,
      );
    }

    final sources = await _sourceResolver.resolveAll(request);
    return _engine.evaluate(
      request: request,
      policy: policy,
      sources: sources,
    );
  }

  @override
  Future<QualityGateResult> evaluateAndPublish(
    QualityGateRequest request,
  ) async {
    final result = await evaluate(request);
    final snapshot = result.snapshot;
    if (snapshot == null) return result;

    final validation = _snapshotValidator.validate(snapshot);
    if (!validation.isValid) {
      return QualityGateResult(
        status: QualityGateResultStatus.failure,
        snapshot: snapshot,
        warnings: result.warnings,
        errors: result.errors,
        limitations: result.limitations,
        validationResult: validation,
        sourceResolutionSummary: result.sourceResolutionSummary,
      );
    }

    final existing = await _store.load(snapshot.metadata.qualityGateSnapshotId);
    if (existing != null) {
      return QualityGateResult(
        status: result.status,
        snapshot: existing,
        warnings: result.warnings,
        errors: result.errors,
        limitations: result.limitations,
        validationResult: validation,
        sourceResolutionSummary: result.sourceResolutionSummary,
      );
    }

    await _store.save(snapshot);
    final saved = await _store.load(snapshot.metadata.qualityGateSnapshotId);
    return QualityGateResult(
      status: result.status,
      snapshot: saved ?? snapshot,
      warnings: result.warnings,
      errors: result.errors,
      limitations: result.limitations,
      validationResult: validation,
      sourceResolutionSummary: result.sourceResolutionSummary,
    );
  }

  @override
  Future<void> publish(QualityGateSnapshot snapshot) async {
    await _store.save(snapshot);
  }

  @override
  Future<QualityGateSnapshot?> load(String snapshotId) {
    return _store.load(snapshotId);
  }

  @override
  Future<QualityGateSnapshot?> latest({
    required String projectId,
    String? policyId,
  }) {
    return _store.latest(projectId: projectId, policyId: policyId);
  }

  @override
  Future<List<QualityGateSnapshot>> query(QualityGateQuery query) {
    return _store.query(query);
  }

  @override
  Future<void> invalidate(String snapshotId) async {
    if (!await _store.exists(snapshotId)) {
      throw QualityGateNotFoundException(snapshotId);
    }
    await _store.invalidate(snapshotId);
  }

  QualityGatePolicy? _resolvePolicy(QualityGateRequest request) {
    if (request.policy != null) return request.policy;
    final policyId = request.policyId;
    if (policyId == null) return null;
    return _policyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.policyVersion,
      allowCandidate: true,
      historicalEvaluation: request.historicalEvaluation,
    );
  }
}
