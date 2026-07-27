import '../../models/score/score_snapshot.dart';
import '../score_canonical_serializer.dart';
import '../score_exceptions.dart';
import 'score_store.dart';

/// In-memory implementation of [ScoreStore] with idempotent publish.
class InMemoryScoreStore implements ScoreStore {
  InMemoryScoreStore({ScoreCanonicalSerializer? serializer})
      : _serializer = serializer ?? const ScoreCanonicalSerializer();

  final ScoreCanonicalSerializer _serializer;
  final Map<String, EngineeringScoreSnapshot> _snapshots = {};

  @override
  Future<void> save(EngineeringScoreSnapshot snapshot) async {
    final id = snapshot.metadata.scoreSnapshotId;
    final existing = _snapshots[id];
    if (existing != null) {
      final existingCanonical = _serializer.canonicalizeSnapshot(existing);
      final incomingCanonical = _serializer.canonicalizeSnapshot(snapshot);
      if (existingCanonical != incomingCanonical) {
        throw ScoreConflictException(id);
      }
      return;
    }
    _snapshots[id] = snapshot;
  }

  @override
  Future<EngineeringScoreSnapshot?> load(String snapshotId) async {
    return _snapshots[snapshotId];
  }

  @override
  Future<List<EngineeringScoreSnapshot>> listAll() async {
    return _snapshots.values.toList();
  }

  @override
  Future<EngineeringScoreSnapshot?> latest({
    required String projectId,
    String? policyId,
  }) async {
    final projectSnapshots = _snapshots.values
        .where((s) => s.metadata.projectId == projectId)
        .where(
          (s) => policyId == null || s.metadata.policyId == policyId,
        )
        .toList()
      ..sort((a, b) {
        final createdCmp = a.metadata.createdAt.compareTo(b.metadata.createdAt);
        if (createdCmp != 0) return createdCmp;
        return a.metadata.scoreSnapshotId.compareTo(b.metadata.scoreSnapshotId);
      });
    if (projectSnapshots.isEmpty) return null;
    return projectSnapshots.last;
  }

  @override
  Future<bool> exists(String snapshotId) async {
    return _snapshots.containsKey(snapshotId);
  }

  @override
  Future<void> delete(String snapshotId) async {
    _snapshots.remove(snapshotId);
  }
}
