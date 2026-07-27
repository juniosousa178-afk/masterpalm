import '../../models/quality_gate/quality_gate_query.dart';
import '../../models/quality_gate/quality_gate_snapshot.dart';
import '../quality_gate_canonical_serializer.dart';
import '../quality_gate_exceptions.dart';
import 'quality_gate_store.dart';

/// In-memory quality gate store with idempotent publish.
class InMemoryQualityGateStore implements QualityGateStore {
  InMemoryQualityGateStore({QualityGateCanonicalSerializer? serializer})
      : _serializer = serializer ?? const QualityGateCanonicalSerializer();

  final QualityGateCanonicalSerializer _serializer;
  final Map<String, QualityGateSnapshot> _snapshots = {};

  @override
  Future<void> save(QualityGateSnapshot snapshot) async {
    final id = snapshot.metadata.qualityGateSnapshotId;
    final existing = _snapshots[id];
    if (existing != null) {
      final existingCanonical = _serializer.snapshotFingerprint(existing);
      final incomingCanonical = _serializer.snapshotFingerprint(snapshot);
      if (existingCanonical != incomingCanonical) {
        throw QualityGateSnapshotConflictException(id);
      }
      return;
    }
    _snapshots[id] = snapshot;
  }

  @override
  Future<QualityGateSnapshot?> load(String snapshotId) async {
    return _snapshots[snapshotId];
  }

  @override
  Future<bool> exists(String snapshotId) async {
    return _snapshots.containsKey(snapshotId);
  }

  @override
  Future<QualityGateSnapshot?> latest({
    required String projectId,
    String? policyId,
  }) async {
    final matches = _snapshots.values
        .where((s) => s.metadata.projectId == projectId)
        .where(
          (s) => policyId == null || s.metadata.policyId == policyId,
        )
        .toList()
      ..sort((a, b) {
        final evaluatedCmp =
            b.metadata.evaluatedAt.compareTo(a.metadata.evaluatedAt);
        if (evaluatedCmp != 0) return evaluatedCmp;
        final createdCmp = b.metadata.createdAt.compareTo(a.metadata.createdAt);
        if (createdCmp != 0) return createdCmp;
        return a.metadata.qualityGateSnapshotId
            .compareTo(b.metadata.qualityGateSnapshotId);
      });
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<List<QualityGateSnapshot>> query(QualityGateQuery query) async {
    var results = _snapshots.values.where((s) {
      if (query.projectId != null && s.metadata.projectId != query.projectId) {
        return false;
      }
      if (query.commitId != null && s.metadata.commitId != query.commitId) {
        return false;
      }
      if (query.branch != null && s.metadata.branch != query.branch) {
        return false;
      }
      if (query.policyId != null && s.metadata.policyId != query.policyId) {
        return false;
      }
      if (query.policyVersion != null &&
          s.metadata.policyVersion != query.policyVersion) {
        return false;
      }
      if (query.decision != null && s.decision != query.decision) {
        return false;
      }
      if (query.eligibility != null &&
          s.eligibility.status != query.eligibility) {
        return false;
      }
      if (query.compatibility != null &&
          s.compatibility.status != query.compatibility) {
        return false;
      }
      if (query.createdFrom != null &&
          s.metadata.createdAt.compareTo(query.createdFrom!) < 0) {
        return false;
      }
      if (query.createdTo != null &&
          s.metadata.createdAt.compareTo(query.createdTo!) > 0) {
        return false;
      }
      return true;
    }).toList();

    results.sort((a, b) {
      final primary =
          query.sortDirection == QualityGateQuerySortDirection.descending
              ? b.metadata.evaluatedAt.compareTo(a.metadata.evaluatedAt)
              : a.metadata.evaluatedAt.compareTo(b.metadata.evaluatedAt);
      if (primary != 0) return primary;
      final secondary =
          query.sortDirection == QualityGateQuerySortDirection.descending
              ? b.metadata.createdAt.compareTo(a.metadata.createdAt)
              : a.metadata.createdAt.compareTo(b.metadata.createdAt);
      if (secondary != 0) return secondary;
      return a.metadata.qualityGateSnapshotId
          .compareTo(b.metadata.qualityGateSnapshotId);
    });

    final offset = query.offset ?? 0;
    if (offset > 0 && offset < results.length) {
      results = results.sublist(offset);
    } else if (offset >= results.length) {
      return const [];
    }
    if (query.limit != null && query.limit! < results.length) {
      results = results.sublist(0, query.limit);
    }
    return List.unmodifiable(results);
  }

  @override
  Future<void> invalidate(String snapshotId) async {
    _snapshots.remove(snapshotId);
  }

  @override
  Future<void> clear() async {
    _snapshots.clear();
  }

  @override
  Future<int> count() async => _snapshots.length;
}
