import '../../models/cryptographic_trust/cryptographic_trust_query.dart';
import '../../models/cryptographic_trust/cryptographic_trust_snapshot.dart';

/// Persistence contract for cryptographic trust snapshots.
abstract class CryptographicTrustStore {
  Future<void> save(CryptographicTrustSnapshot snapshot);

  Future<CryptographicTrustSnapshot?> load(String snapshotId);

  Future<bool> exists(String snapshotId);

  Future<CryptographicTrustSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  });

  Future<List<CryptographicTrustSnapshot>> query(CryptographicTrustQuery query);

  Future<void> invalidate(String snapshotId);

  Future<void> clear();

  Future<int> count();
}
