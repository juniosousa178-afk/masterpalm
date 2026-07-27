import '../../models/release_evidence/release_evidence_bundle.dart';
import '../../models/release_evidence/release_evidence_query.dart';
import '../release_evidence_canonical_serializer.dart';
import '../release_evidence_exceptions.dart';
import 'release_evidence_store.dart';

/// In-memory release evidence store with idempotent publish.
class InMemoryReleaseEvidenceStore implements ReleaseEvidenceStore {
  InMemoryReleaseEvidenceStore({
    ReleaseEvidenceCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const ReleaseEvidenceCanonicalSerializer();

  final ReleaseEvidenceCanonicalSerializer _serializer;
  final Map<String, ReleaseEvidenceBundle> _bundles = {};

  @override
  Future<void> save(ReleaseEvidenceBundle bundle) async {
    final id = bundle.metadata.bundleId;
    final existing = _bundles[id];
    if (existing != null) {
      final existingCanonical = _serializer.bundleFingerprint(existing);
      final incomingCanonical = _serializer.bundleFingerprint(bundle);
      if (existingCanonical != incomingCanonical) {
        throw ReleaseEvidenceBundleConflictException(id);
      }
      return;
    }
    _bundles[id] = bundle;
  }

  @override
  Future<ReleaseEvidenceBundle?> load(String bundleId) async {
    return _bundles[bundleId];
  }

  @override
  Future<bool> exists(String bundleId) async {
    return _bundles.containsKey(bundleId);
  }

  @override
  Future<ReleaseEvidenceBundle?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async {
    final matches = _bundles.values
        .where((b) => b.metadata.projectId == projectId)
        .where((b) => releaseId == null || b.metadata.releaseId == releaseId)
        .where((b) => policyId == null || b.metadata.policyId == policyId)
        .toList()
      ..sort((a, b) {
        final evaluatedCmp =
            b.metadata.evaluatedAt.compareTo(a.metadata.evaluatedAt);
        if (evaluatedCmp != 0) return evaluatedCmp;
        final createdCmp = b.metadata.createdAt.compareTo(a.metadata.createdAt);
        if (createdCmp != 0) return createdCmp;
        return a.metadata.bundleId.compareTo(b.metadata.bundleId);
      });
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<List<ReleaseEvidenceBundle>> query(ReleaseEvidenceQuery query) async {
    var results = _bundles.values.where((b) {
      if (query.projectId != null && b.metadata.projectId != query.projectId) {
        return false;
      }
      if (query.releaseId != null && b.metadata.releaseId != query.releaseId) {
        return false;
      }
      if (query.commitId != null && b.metadata.commitId != query.commitId) {
        return false;
      }
      if (query.policyId != null && b.metadata.policyId != query.policyId) {
        return false;
      }
      if (query.policyVersion != null &&
          b.metadata.policyVersion != query.policyVersion) {
        return false;
      }
      if (query.environment != null &&
          b.metadata.environment != query.environment) {
        return false;
      }
      if (query.evaluatedFrom != null &&
          b.metadata.evaluatedAt.compareTo(query.evaluatedFrom!) < 0) {
        return false;
      }
      if (query.evaluatedTo != null &&
          b.metadata.evaluatedAt.compareTo(query.evaluatedTo!) > 0) {
        return false;
      }
      return true;
    }).toList();

    results.sort((a, b) {
      final primary =
          query.sortDirection == ReleaseEvidenceQuerySortDirection.descending
              ? b.metadata.evaluatedAt.compareTo(a.metadata.evaluatedAt)
              : a.metadata.evaluatedAt.compareTo(b.metadata.evaluatedAt);
      if (primary != 0) return primary;
      return a.metadata.bundleId.compareTo(b.metadata.bundleId);
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
  Future<void> invalidate(String bundleId) async {
    _bundles.remove(bundleId);
  }

  @override
  Future<void> clear() async {
    _bundles.clear();
  }

  @override
  Future<int> count() async => _bundles.length;
}
