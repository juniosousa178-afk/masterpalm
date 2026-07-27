import '../../models/release_supply_chain/release_supply_chain_query.dart';
import '../../models/release_supply_chain/release_supply_chain_snapshot.dart';

/// Persistence contract for release supply chain snapshots.
abstract class ReleaseSupplyChainStore {
  Future<void> save(ReleaseSupplyChainSnapshot snapshot);

  Future<ReleaseSupplyChainSnapshot?> load(String snapshotId);

  Future<bool> exists(String snapshotId);

  Future<ReleaseSupplyChainSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? supplyChainPolicyId,
  });

  Future<List<ReleaseSupplyChainSnapshot>> query(ReleaseSupplyChainQuery query);

  Future<void> invalidate(String snapshotId);

  Future<void> clear();

  Future<int> count();
}
