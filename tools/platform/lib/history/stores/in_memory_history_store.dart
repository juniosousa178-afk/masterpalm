import '../../models/history/history_snapshot.dart';
import '../history_canonical_serializer.dart';
import '../history_exceptions.dart';
import 'history_store.dart';

/// In-memory implementation of [HistoryStore] with idempotent publish.
class InMemoryHistoryStore implements HistoryStore {
  InMemoryHistoryStore({HistoryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const HistoryCanonicalSerializer();

  final HistoryCanonicalSerializer _serializer;
  final Map<String, HistorySnapshot> _snapshots = {};
  final Map<String, int> _sequenceByProject = {};

  @override
  Future<void> save(HistorySnapshot snapshot) async {
    final id = snapshot.metadata.historySnapshotId;
    final existing = _snapshots[id];
    if (existing != null) {
      final existingCanonical = _serializer.canonicalizeSnapshot(existing);
      final incomingCanonical = _serializer.canonicalizeSnapshot(snapshot);
      if (existingCanonical != incomingCanonical) {
        throw HistoryConflictException(id);
      }
      return;
    }
    final sequence = (_sequenceByProject[snapshot.metadata.projectId] ?? 0) + 1;
    _sequenceByProject[snapshot.metadata.projectId] = sequence;
    final withSequence = HistorySnapshot(
      metadata: snapshot.metadata.copyWith(sequence: sequence),
      artifacts: snapshot.artifacts,
    );
    _snapshots[id] = withSequence;
  }

  @override
  Future<HistorySnapshot?> load(String snapshotId) async {
    return _snapshots[snapshotId];
  }

  @override
  Future<List<HistorySnapshot>> listAll() async {
    return _snapshots.values.toList();
  }

  @override
  Future<HistorySnapshot?> latest(String projectId) async {
    final projectSnapshots = _snapshots.values
        .where((s) => s.metadata.projectId == projectId)
        .toList()
      ..sort((a, b) {
        final createdCmp = a.metadata.createdAt.compareTo(b.metadata.createdAt);
        if (createdCmp != 0) return createdCmp;
        return a.metadata.historySnapshotId
            .compareTo(b.metadata.historySnapshotId);
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
