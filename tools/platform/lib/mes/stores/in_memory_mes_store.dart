import '../../models/mes/mes_snapshot.dart';
import '../mes_canonical_serializer.dart';
import '../mes_exceptions.dart';
import 'mes_store.dart';

/// In-memory MES store with idempotent publish.
class InMemoryMESStore implements MESStore {
  InMemoryMESStore({MESCanonicalSerializer? serializer})
      : _serializer = serializer ?? const MESCanonicalSerializer();

  final MESCanonicalSerializer _serializer;
  final Map<String, MESSnapshot> _snapshots = {};

  @override
  Future<void> save(MESSnapshot snapshot) async {
    final id = snapshot.metadata.mesSnapshotId;
    final existing = _snapshots[id];
    if (existing != null) {
      final existingCanonical = _serializer.canonicalizeSnapshot(existing);
      final incomingCanonical = _serializer.canonicalizeSnapshot(snapshot);
      if (existingCanonical != incomingCanonical) {
        throw MESConflictException(id);
      }
      return;
    }
    _snapshots[id] = snapshot;
  }

  @override
  Future<MESSnapshot?> load(String snapshotId) async {
    return _snapshots[snapshotId];
  }

  @override
  Future<List<MESSnapshot>> listAll() async {
    return _snapshots.values.toList();
  }

  @override
  Future<MESSnapshot?> latest({
    required String projectId,
    int? policyVersion,
  }) async {
    final projectSnapshots = _snapshots.values
        .where((s) => s.metadata.projectId == projectId)
        .where(
          (s) =>
              policyVersion == null ||
              s.metadata.policyVersion == policyVersion,
        )
        .toList()
      ..sort((a, b) {
        final createdCmp = a.metadata.createdAt.compareTo(b.metadata.createdAt);
        if (createdCmp != 0) return createdCmp;
        return a.metadata.mesSnapshotId.compareTo(b.metadata.mesSnapshotId);
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
