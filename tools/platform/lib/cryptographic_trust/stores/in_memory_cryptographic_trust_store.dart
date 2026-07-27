import '../../models/cryptographic_trust/cryptographic_trust_query.dart';
import '../../models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import '../cryptographic_trust_canonical_serializer.dart';
import '../cryptographic_trust_exceptions.dart';
import 'cryptographic_trust_store.dart';

/// In-memory cryptographic trust store with idempotent publish.
class InMemoryCryptographicTrustStore implements CryptographicTrustStore {
  InMemoryCryptographicTrustStore({
    CryptographicTrustCanonicalSerializer? serializer,
  }) : _serializer =
            serializer ?? const CryptographicTrustCanonicalSerializer();

  final CryptographicTrustCanonicalSerializer _serializer;
  final Map<String, CryptographicTrustSnapshot> _snapshots = {};

  @override
  Future<void> save(CryptographicTrustSnapshot snapshot) async {
    final id = snapshot.metadata.cryptographicTrustSnapshotId;
    final existing = _snapshots[id];
    if (existing != null) {
      final existingCanonical = _serializer.snapshotFingerprint(existing);
      final incomingCanonical = _serializer.snapshotFingerprint(snapshot);
      if (existingCanonical != incomingCanonical) {
        throw CryptographicTrustSnapshotConflictException(id);
      }
      return;
    }
    _snapshots[id] = snapshot;
  }

  @override
  Future<CryptographicTrustSnapshot?> load(String snapshotId) async {
    return _snapshots[snapshotId];
  }

  @override
  Future<bool> exists(String snapshotId) async {
    return _snapshots.containsKey(snapshotId);
  }

  @override
  Future<CryptographicTrustSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async {
    final matches = _snapshots.values
        .where((s) => s.metadata.projectId == projectId)
        .where((s) => releaseId == null || s.metadata.releaseId == releaseId)
        .where(
          (s) =>
              policyId == null ||
              s.trustPolicies.any((p) => p.policyId == policyId),
        )
        .toList()
      ..sort((a, b) {
        final evaluatedCmp = (b.metadata.evaluatedAt ?? '')
            .compareTo(a.metadata.evaluatedAt ?? '');
        if (evaluatedCmp != 0) return evaluatedCmp;
        final createdCmp = b.metadata.createdAt.compareTo(a.metadata.createdAt);
        if (createdCmp != 0) return createdCmp;
        return a.metadata.cryptographicTrustSnapshotId
            .compareTo(b.metadata.cryptographicTrustSnapshotId);
      });
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<List<CryptographicTrustSnapshot>> query(
    CryptographicTrustQuery query,
  ) async {
    var results = _snapshots.values.where((snapshot) {
      if (query.projectId != null &&
          snapshot.metadata.projectId != query.projectId) {
        return false;
      }
      if (query.releaseId != null &&
          snapshot.metadata.releaseId != query.releaseId) {
        return false;
      }
      if (query.subjectId != null &&
          !snapshot.subjects.any((s) => s.subjectId == query.subjectId)) {
        return false;
      }
      if (query.signatureId != null &&
          !snapshot.signatures.any((s) => s.signatureId == query.signatureId)) {
        return false;
      }
      if (query.policyId != null &&
          !snapshot.trustPolicies.any((p) => p.policyId == query.policyId)) {
        return false;
      }
      if (query.trustStatus != null && snapshot.status != query.trustStatus) {
        return false;
      }
      if (query.verificationStatus != null &&
          !snapshot.verificationResults
              .any((r) => r.status == query.verificationStatus)) {
        return false;
      }
      if (query.createdFrom != null &&
          snapshot.metadata.createdAt.compareTo(query.createdFrom!) < 0) {
        return false;
      }
      if (query.createdUntil != null &&
          snapshot.metadata.createdAt.compareTo(query.createdUntil!) > 0) {
        return false;
      }
      return true;
    }).toList();

    results.sort((a, b) {
      final primary =
          query.sortDirection == CryptographicTrustQuerySortDirection.descending
              ? b.metadata.createdAt.compareTo(a.metadata.createdAt)
              : a.metadata.createdAt.compareTo(b.metadata.createdAt);
      if (primary != 0) return primary;
      return a.metadata.cryptographicTrustSnapshotId
          .compareTo(b.metadata.cryptographicTrustSnapshotId);
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
