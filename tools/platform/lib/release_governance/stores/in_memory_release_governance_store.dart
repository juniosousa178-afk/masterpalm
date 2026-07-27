import '../../models/release_governance/release_decision_snapshot.dart';
import '../../models/release_governance/release_governance_query.dart';
import '../release_governance_canonical_serializer.dart';
import '../release_governance_exceptions.dart';
import 'release_governance_store.dart';

/// In-memory release governance store with idempotent publish.
class InMemoryReleaseGovernanceStore implements ReleaseGovernanceStore {
  InMemoryReleaseGovernanceStore({
    ReleaseGovernanceCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const ReleaseGovernanceCanonicalSerializer();

  final ReleaseGovernanceCanonicalSerializer _serializer;
  final Map<String, ReleaseDecisionSnapshot> _snapshots = {};

  @override
  Future<void> save(ReleaseDecisionSnapshot snapshot) async {
    final id = snapshot.metadata.snapshotId;
    final existing = _snapshots[id];
    if (existing != null) {
      final existingCanonical = _serializer.snapshotFingerprint(existing);
      final incomingCanonical = _serializer.snapshotFingerprint(snapshot);
      if (existingCanonical != incomingCanonical) {
        throw ReleaseGovernanceSnapshotConflictException(id);
      }
      return;
    }
    _snapshots[id] = snapshot;
  }

  @override
  Future<ReleaseDecisionSnapshot?> load(String snapshotId) async {
    return _snapshots[snapshotId];
  }

  @override
  Future<bool> exists(String snapshotId) async {
    return _snapshots.containsKey(snapshotId);
  }

  @override
  Future<ReleaseDecisionSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async {
    final matches = _snapshots.values
        .where((s) => s.metadata.projectId == projectId)
        .where((s) => releaseId == null || s.metadata.releaseId == releaseId)
        .where((s) => policyId == null || s.metadata.policyId == policyId)
        .toList()
      ..sort((a, b) {
        final evaluatedCmp =
            b.metadata.evaluatedAt.compareTo(a.metadata.evaluatedAt);
        if (evaluatedCmp != 0) return evaluatedCmp;
        final createdCmp = b.metadata.createdAt.compareTo(a.metadata.createdAt);
        if (createdCmp != 0) return createdCmp;
        return a.metadata.snapshotId.compareTo(b.metadata.snapshotId);
      });
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<List<ReleaseDecisionSnapshot>> query(
    ReleaseGovernanceQuery query,
  ) async {
    var results = _snapshots.values.where((s) {
      if (query.projectId != null && s.metadata.projectId != query.projectId) {
        return false;
      }
      if (query.releaseId != null && s.metadata.releaseId != query.releaseId) {
        return false;
      }
      if (query.commitId != null && s.metadata.commitId != query.commitId) {
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
      if (query.environment != null &&
          s.metadata.environment != query.environment) {
        return false;
      }
      if (query.releaseType != null &&
          s.metadata.releaseType != query.releaseType) {
        return false;
      }
      if (query.evaluatedFrom != null &&
          s.metadata.evaluatedAt.compareTo(query.evaluatedFrom!) < 0) {
        return false;
      }
      if (query.evaluatedTo != null &&
          s.metadata.evaluatedAt.compareTo(query.evaluatedTo!) > 0) {
        return false;
      }
      return true;
    }).toList();

    results.sort((a, b) {
      final primary =
          query.sortDirection == ReleaseGovernanceQuerySortDirection.descending
              ? b.metadata.evaluatedAt.compareTo(a.metadata.evaluatedAt)
              : a.metadata.evaluatedAt.compareTo(b.metadata.evaluatedAt);
      if (primary != 0) return primary;
      return a.metadata.snapshotId.compareTo(b.metadata.snapshotId);
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
