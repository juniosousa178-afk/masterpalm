import '../../models/cicd_integration/cicd_integration_query.dart';
import '../../models/cicd_integration/cicd_integration_snapshot.dart';
import '../cicd_integration_canonical_serializer.dart';
import '../cicd_integration_exceptions.dart';
import 'cicd_integration_store.dart';

/// In-memory CI/CD integration store with idempotent publish.
class InMemoryCicdIntegrationStore implements CicdIntegrationStore {
  InMemoryCicdIntegrationStore({
    CicdIntegrationCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const CicdIntegrationCanonicalSerializer();

  final CicdIntegrationCanonicalSerializer _serializer;
  final Map<String, CicdIntegrationSnapshot> _snapshots = {};

  @override
  Future<void> save(CicdIntegrationSnapshot snapshot) async {
    final id = snapshot.metadata.cicdIntegrationSnapshotId;
    final existing = _snapshots[id];
    if (existing != null) {
      final existingCanonical = _serializer.snapshotFingerprint(existing);
      final incomingCanonical = _serializer.snapshotFingerprint(snapshot);
      if (existingCanonical != incomingCanonical) {
        throw CicdIntegrationSnapshotConflictException(id);
      }
      return;
    }
    _snapshots[id] = snapshot;
  }

  @override
  Future<CicdIntegrationSnapshot?> load(String snapshotId) async {
    return _snapshots[snapshotId];
  }

  @override
  Future<bool> exists(String snapshotId) async {
    return _snapshots.containsKey(snapshotId);
  }

  @override
  Future<CicdIntegrationSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? pipelineIntegrationPolicyId,
  }) async {
    final matches = _snapshots.values
        .where((s) => s.metadata.projectId == projectId)
        .where((s) => releaseId == null || s.metadata.releaseId == releaseId)
        .where(
          (s) =>
              pipelineIntegrationPolicyId == null ||
              s.metadata.pipelineIntegrationPolicyId ==
                  pipelineIntegrationPolicyId,
        )
        .toList()
      ..sort((a, b) {
        final evaluatedCmp =
            b.metadata.evaluatedAt.compareTo(a.metadata.evaluatedAt);
        if (evaluatedCmp != 0) return evaluatedCmp;
        final createdCmp = b.metadata.createdAt.compareTo(a.metadata.createdAt);
        if (createdCmp != 0) return createdCmp;
        return a.metadata.cicdIntegrationSnapshotId
            .compareTo(b.metadata.cicdIntegrationSnapshotId);
      });
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<List<CicdIntegrationSnapshot>> query(
    CicdIntegrationQuery query,
  ) async {
    var results = _snapshots.values.where((s) {
      if (query.projectId != null && s.metadata.projectId != query.projectId) {
        return false;
      }
      if (query.releaseId != null && s.metadata.releaseId != query.releaseId) {
        return false;
      }
      if (query.pipelineDefinitionId != null &&
          s.metadata.pipelineDefinitionId != query.pipelineDefinitionId) {
        return false;
      }
      if (query.status != null && s.status != query.status) {
        return false;
      }
      if (query.policyId != null &&
          s.metadata.pipelineIntegrationPolicyId != query.policyId &&
          s.metadata.pipelineExecutionPolicyId != query.policyId &&
          s.metadata.deploymentIntegrationPolicyId != query.policyId) {
        return false;
      }
      return true;
    }).toList();

    results.sort((a, b) {
      final primary =
          query.sortDirection == CicdIntegrationQuerySortDirection.descending
              ? b.metadata.evaluatedAt.compareTo(a.metadata.evaluatedAt)
              : a.metadata.evaluatedAt.compareTo(b.metadata.evaluatedAt);
      if (primary != 0) return primary;
      return a.metadata.cicdIntegrationSnapshotId
          .compareTo(b.metadata.cicdIntegrationSnapshotId);
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
