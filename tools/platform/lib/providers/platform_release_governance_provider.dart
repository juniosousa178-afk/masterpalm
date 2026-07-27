import '../interfaces/release_governance_provider.dart';
import '../models/release_governance/release_decision_snapshot.dart';
import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_policy.dart';
import '../models/release_governance/release_governance_query.dart';
import '../models/release_governance/release_governance_request.dart';
import '../models/release_governance/release_governance_messages.dart';
import '../release_governance/release_decision_snapshot_validator.dart';
import '../release_governance/release_governance_engine.dart';
import '../release_governance/release_governance_exceptions.dart';
import '../release_governance/release_governance_policy_registry.dart';
import '../release_governance/release_governance_source_resolver.dart';
import '../release_governance/stores/release_governance_store.dart';

/// Platform implementation of [ReleaseGovernanceProvider].
class PlatformReleaseGovernanceProvider implements ReleaseGovernanceProvider {
  PlatformReleaseGovernanceProvider({
    required ReleaseGovernanceEngine engine,
    required ReleaseGovernancePolicyRegistry policyRegistry,
    required ReleaseGovernanceSourceResolver sourceResolver,
    required ReleaseGovernanceStore store,
    ReleaseDecisionSnapshotValidator? snapshotValidator,
  })  : _engine = engine,
        _policyRegistry = policyRegistry,
        _sourceResolver = sourceResolver,
        _store = store,
        _snapshotValidator = snapshotValidator ??
            const DefaultReleaseDecisionSnapshotValidator();

  final ReleaseGovernanceEngine _engine;
  final ReleaseGovernancePolicyRegistry _policyRegistry;
  final ReleaseGovernanceSourceResolver _sourceResolver;
  final ReleaseGovernanceStore _store;
  final ReleaseDecisionSnapshotValidator _snapshotValidator;

  @override
  Future<ReleaseGovernanceResult> evaluate(
    ReleaseGovernanceRequest request,
  ) async {
    final policy = _resolvePolicy(request);
    if (policy == null) {
      throw ReleaseGovernancePolicyNotFoundException(
        request.policyId ?? request.policy?.metadata.policyId ?? '',
        policyVersion: request.policyVersion,
      );
    }

    final sources = await _sourceResolver.resolveAll(request, policy);
    return _engine.evaluate(
      request: request,
      policy: policy,
      sources: sources,
    );
  }

  @override
  Future<ReleaseGovernanceResult> evaluateAndPublish(
    ReleaseGovernanceRequest request,
  ) async {
    final result = await evaluate(request);
    final snapshot = result.snapshot;
    if (snapshot == null) return result;

    final validation = _snapshotValidator.validate(snapshot);
    if (!validation.isValid) {
      return ReleaseGovernanceResult(
        status: ReleaseGovernanceResultStatus.failure,
        snapshot: snapshot,
        policyReference: result.policyReference,
        warnings: result.warnings,
        errors: result.errors,
        limitations: result.limitations,
        sourceResolutionSummary: result.sourceResolutionSummary,
      );
    }

    final existing = await _store.load(snapshot.metadata.snapshotId);
    if (existing != null) {
      return ReleaseGovernanceResult(
        status: result.status,
        snapshot: existing,
        policyReference: result.policyReference,
        warnings: result.warnings,
        errors: result.errors,
        limitations: result.limitations,
        sourceResolutionSummary: result.sourceResolutionSummary,
        publicationStatus: ReleaseGovernancePublicationStatus.skipped.wireName,
      );
    }

    await _store.save(snapshot);
    final saved = await _store.load(snapshot.metadata.snapshotId);
    return ReleaseGovernanceResult(
      status: result.status,
      snapshot: saved ?? snapshot,
      policyReference: result.policyReference,
      warnings: result.warnings,
      errors: result.errors,
      limitations: result.limitations,
      sourceResolutionSummary: result.sourceResolutionSummary,
      publicationStatus: ReleaseGovernancePublicationStatus.published.wireName,
    );
  }

  @override
  Future<void> publish(ReleaseDecisionSnapshot snapshot) async {
    await _store.save(snapshot);
  }

  @override
  Future<ReleaseDecisionSnapshot?> load(String snapshotId) {
    return _store.load(snapshotId);
  }

  @override
  Future<ReleaseDecisionSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) {
    return _store.latest(
      projectId: projectId,
      releaseId: releaseId,
      policyId: policyId,
    );
  }

  @override
  Future<List<ReleaseDecisionSnapshot>> query(ReleaseGovernanceQuery query) {
    return _store.query(query);
  }

  @override
  Future<void> invalidate(String snapshotId) async {
    if (!await _store.exists(snapshotId)) {
      throw ReleaseGovernanceNotFoundException(snapshotId);
    }
    await _store.invalidate(snapshotId);
  }

  ReleaseGovernancePolicy? _resolvePolicy(ReleaseGovernanceRequest request) {
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
