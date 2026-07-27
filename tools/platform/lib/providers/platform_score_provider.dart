import '../interfaces/score_provider.dart';
import '../models/score/score_policy.dart';
import '../models/score/score_request.dart';
import '../models/score/score_snapshot.dart';
import '../score/score_canonical_serializer.dart';
import '../score/score_engine.dart';
import '../score/score_exceptions.dart';
import '../score/score_registry.dart';
import '../score/stores/score_store.dart';

/// Platform implementation of [ScoreProvider].
class PlatformScoreProvider implements ScoreProvider {
  PlatformScoreProvider({
    required ScoreEngine engine,
    required ScoreRegistry registry,
    required ScoreStore store,
    ScoreCanonicalSerializer? serializer,
  })  : _engine = engine,
        _registry = registry,
        _store = store,
        _serializer = serializer ?? const ScoreCanonicalSerializer();

  final ScoreEngine _engine;
  final ScoreRegistry _registry;
  final ScoreStore _store;
  final ScoreCanonicalSerializer _serializer;

  @override
  Set<String> get supportedPolicyIds => _registry.supportedPolicyIds;

  @override
  ScorePolicy? getPolicy(String policyId) => _registry.getPolicy(policyId);

  @override
  Future<ScoreResult> calculate(ScoreRequest request) async {
    final result = _engine.calculate(request);
    final existing =
        await _store.load(result.snapshot.metadata.scoreSnapshotId);
    if (existing != null) {
      final same = _serializer.canonicalizeSnapshot(existing) ==
          _serializer.canonicalizeSnapshot(result.snapshot);
      return ScoreResult(
        status: result.status,
        snapshot: existing,
        warnings: result.warnings,
        errors: result.errors,
        idempotent: same,
      );
    }
    await _store.save(result.snapshot);
    final saved = await _store.load(result.snapshot.metadata.scoreSnapshotId);
    return ScoreResult(
      status: result.status,
      snapshot: saved ?? result.snapshot,
      warnings: result.warnings,
      errors: result.errors,
    );
  }

  @override
  Future<void> publish(EngineeringScoreSnapshot snapshot) async {
    await _store.save(snapshot);
  }

  @override
  Future<EngineeringScoreSnapshot?> load({required String snapshotId}) async {
    return _store.load(snapshotId);
  }

  @override
  Future<EngineeringScoreSnapshot?> latest({
    required String projectId,
    String? policyId,
  }) async {
    return _store.latest(projectId: projectId, policyId: policyId);
  }

  @override
  Future<void> invalidate(String snapshotId) async {
    if (!await _store.exists(snapshotId)) {
      throw ScoreNotFoundException(snapshotId);
    }
    await _store.delete(snapshotId);
  }
}
