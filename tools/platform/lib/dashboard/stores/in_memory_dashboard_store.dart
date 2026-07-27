import '../../models/dashboard/dashboard_request.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../dashboard_canonical_serializer.dart';
import '../dashboard_exceptions.dart';
import 'dashboard_store.dart';

/// In-memory dashboard store with idempotent publish.
class InMemoryDashboardStore implements DashboardStore {
  InMemoryDashboardStore({DashboardCanonicalSerializer? serializer})
      : _serializer = serializer ?? const DashboardCanonicalSerializer();

  final DashboardCanonicalSerializer _serializer;
  final Map<String, DashboardSnapshot> _snapshots = {};

  @override
  Future<void> save(DashboardSnapshot snapshot) async {
    final id = snapshot.metadata.dashboardSnapshotId;
    final existing = _snapshots[id];
    if (existing != null) {
      final same = _serializer.canonicalizeSnapshot(existing) ==
          _serializer.canonicalizeSnapshot(snapshot);
      if (!same) {
        throw DashboardConflictException(id);
      }
      return;
    }
    _snapshots[id] = snapshot;
  }

  @override
  Future<DashboardSnapshot?> load(String snapshotId) async {
    return _snapshots[snapshotId];
  }

  @override
  Future<bool> exists(String snapshotId) async {
    return _snapshots.containsKey(snapshotId);
  }

  @override
  Future<DashboardSnapshot?> latest({
    required String projectId,
    String? branch,
  }) async {
    final matches = _snapshots.values
        .where((s) => s.metadata.projectId == projectId)
        .where((s) => branch == null || s.metadata.branch == branch)
        .toList()
      ..sort((a, b) {
        final createdCmp = a.metadata.createdAt.compareTo(b.metadata.createdAt);
        if (createdCmp != 0) return createdCmp;
        return a.metadata.dashboardSnapshotId
            .compareTo(b.metadata.dashboardSnapshotId);
      });
    if (matches.isEmpty) return null;
    return matches.last;
  }

  @override
  Future<List<DashboardSnapshot>> query(DashboardQuery query) async {
    var results = _snapshots.values
        .where((s) => s.metadata.projectId == query.projectId)
        .where((s) => query.branch == null || s.metadata.branch == query.branch)
        .where(
          (s) =>
              query.from == null ||
              s.metadata.createdAt.compareTo(query.from!) >= 0,
        )
        .where(
          (s) =>
              query.to == null ||
              s.metadata.createdAt.compareTo(query.to!) <= 0,
        )
        .toList()
      ..sort((a, b) => a.metadata.createdAt.compareTo(b.metadata.createdAt));

    if (query.limit != null && results.length > query.limit!) {
      results = results.sublist(results.length - query.limit!);
    }
    return results;
  }

  @override
  Future<void> delete(String snapshotId) async {
    _snapshots.remove(snapshotId);
  }
}
