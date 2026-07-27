import '../../models/release_supply_chain/release_supply_chain_query.dart';
import '../../models/release_supply_chain/release_supply_chain_snapshot.dart';
import '../release_supply_chain_canonical_serializer.dart';
import '../release_supply_chain_exceptions.dart';
import 'release_supply_chain_store.dart';

/// In-memory release supply chain store with idempotent publish.
class InMemoryReleaseSupplyChainStore implements ReleaseSupplyChainStore {
  InMemoryReleaseSupplyChainStore({
    ReleaseSupplyChainCanonicalSerializer? serializer,
  }) : _serializer =
            serializer ?? const ReleaseSupplyChainCanonicalSerializer();

  final ReleaseSupplyChainCanonicalSerializer _serializer;
  final Map<String, ReleaseSupplyChainSnapshot> _snapshots = {};

  @override
  Future<void> save(ReleaseSupplyChainSnapshot snapshot) async {
    final id = snapshot.metadata.supplyChainSnapshotId;
    final existing = _snapshots[id];
    if (existing != null) {
      final existingCanonical = _serializer.snapshotFingerprint(existing);
      final incomingCanonical = _serializer.snapshotFingerprint(snapshot);
      if (existingCanonical != incomingCanonical) {
        throw ReleaseSupplyChainSnapshotConflictException(id);
      }
      return;
    }
    _snapshots[id] = snapshot;
  }

  @override
  Future<ReleaseSupplyChainSnapshot?> load(String snapshotId) async {
    return _snapshots[snapshotId];
  }

  @override
  Future<bool> exists(String snapshotId) async {
    return _snapshots.containsKey(snapshotId);
  }

  @override
  Future<ReleaseSupplyChainSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? supplyChainPolicyId,
  }) async {
    final matches = _snapshots.values
        .where((s) => s.metadata.projectId == projectId)
        .where((s) => releaseId == null || s.metadata.releaseId == releaseId)
        .where(
          (s) =>
              supplyChainPolicyId == null ||
              s.metadata.supplyChainPolicyId == supplyChainPolicyId,
        )
        .toList()
      ..sort((a, b) {
        final evaluatedCmp =
            b.metadata.evaluatedAt.compareTo(a.metadata.evaluatedAt);
        if (evaluatedCmp != 0) return evaluatedCmp;
        final createdCmp = b.metadata.createdAt.compareTo(a.metadata.createdAt);
        if (createdCmp != 0) return createdCmp;
        return a.metadata.supplyChainSnapshotId
            .compareTo(b.metadata.supplyChainSnapshotId);
      });
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<List<ReleaseSupplyChainSnapshot>> query(
    ReleaseSupplyChainQuery query,
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
      if (query.supplyChainPolicyId != null &&
          s.metadata.supplyChainPolicyId != query.supplyChainPolicyId) {
        return false;
      }
      if (query.supplyChainPolicyVersion != null &&
          s.metadata.supplyChainPolicyVersion !=
              query.supplyChainPolicyVersion) {
        return false;
      }
      if (query.distributionPolicyId != null &&
          s.metadata.distributionPolicyId != query.distributionPolicyId) {
        return false;
      }
      if (query.compliancePolicyId != null &&
          s.metadata.compliancePolicyId != query.compliancePolicyId) {
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
          query.sortDirection == ReleaseSupplyChainQuerySortDirection.descending
              ? b.metadata.evaluatedAt.compareTo(a.metadata.evaluatedAt)
              : a.metadata.evaluatedAt.compareTo(b.metadata.evaluatedAt);
      if (primary != 0) return primary;
      return a.metadata.supplyChainSnapshotId
          .compareTo(b.metadata.supplyChainSnapshotId);
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
