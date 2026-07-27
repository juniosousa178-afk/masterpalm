import '../interfaces/mes_provider.dart';
import '../models/mes/mes_policy.dart';
import '../models/mes/mes_request.dart';
import '../models/mes/mes_snapshot.dart';
import '../mes/mes_canonical_serializer.dart';
import '../mes/mes_engine.dart';
import '../mes/mes_exceptions.dart';
import '../mes/mes_registry.dart';
import '../mes/stores/mes_store.dart';

/// Platform implementation of [MESProvider].
class PlatformMESProvider implements MESProvider {
  PlatformMESProvider({
    required MESEngine engine,
    required MESPolicyRegistry registry,
    required MESStore store,
    MESCanonicalSerializer? serializer,
  })  : _engine = engine,
        _registry = registry,
        _store = store,
        _serializer = serializer ?? const MESCanonicalSerializer();

  final MESEngine _engine;
  final MESPolicyRegistry _registry;
  final MESStore _store;
  final MESCanonicalSerializer _serializer;

  @override
  Set<String> get supportedPolicyIds => _registry.supportedPolicyIds;

  @override
  MESPolicy? getPolicy(String policyId, {int? policyVersion}) {
    return _registry.getPolicy(policyId, policyVersion: policyVersion);
  }

  @override
  MESPolicy? getCandidatePolicy() => _registry.getCandidatePolicy();

  @override
  MESPolicy? getActivePolicy() => _registry.getActivePolicy();

  @override
  Future<MESResult> calculate(MESRequest request) async {
    final result = await _engine.calculate(request);
    if (result.snapshot == null) return result;

    final existing = await _store.load(result.snapshot!.metadata.mesSnapshotId);
    if (existing != null) {
      final same = _serializer.canonicalizeSnapshot(existing) ==
          _serializer.canonicalizeSnapshot(result.snapshot!);
      return MESResult(
        status: result.status,
        eligibility: result.eligibility,
        snapshot: existing,
        warnings: result.warnings,
        errors: result.errors,
        idempotent: same,
      );
    }
    await _store.save(result.snapshot!);
    final saved = await _store.load(result.snapshot!.metadata.mesSnapshotId);
    return MESResult(
      status: result.status,
      eligibility: result.eligibility,
      snapshot: saved ?? result.snapshot,
      warnings: result.warnings,
      errors: result.errors,
    );
  }

  @override
  Future<MESEligibility> checkEligibility(MESRequest request) {
    return _engine.checkEligibility(request);
  }

  @override
  Future<void> publish(MESSnapshot snapshot) async {
    await _store.save(snapshot);
  }

  @override
  Future<MESSnapshot?> load(String snapshotId) async {
    return _store.load(snapshotId);
  }

  @override
  Future<MESSnapshot?> latest({
    required String projectId,
    int? policyVersion,
  }) async {
    return _store.latest(
      projectId: projectId,
      policyVersion: policyVersion,
    );
  }

  @override
  Future<void> invalidate(String snapshotId) async {
    if (!await _store.exists(snapshotId)) {
      throw MESNotFoundException(snapshotId);
    }
    await _store.delete(snapshotId);
  }
}
