import '../models/release_supply_chain/release_supply_chain_query.dart';
import '../models/release_supply_chain/release_supply_chain_request.dart';
import '../models/release_supply_chain/release_supply_chain_result.dart';
import '../models/release_supply_chain/release_supply_chain_snapshot.dart';

/// Public contract for release supply chain collection and publication.
abstract interface class ReleaseSupplyChainProvider {
  Future<ReleaseSupplyChainResult> evaluate(ReleaseSupplyChainRequest request);

  Future<ReleaseSupplyChainResult> evaluateAndPublish(
    ReleaseSupplyChainRequest request,
  );

  Future<void> publish(ReleaseSupplyChainSnapshot snapshot);

  Future<ReleaseSupplyChainSnapshot?> load(String snapshotId);

  Future<ReleaseSupplyChainSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? supplyChainPolicyId,
  });

  Future<List<ReleaseSupplyChainSnapshot>> query(ReleaseSupplyChainQuery query);

  Future<void> invalidate(String snapshotId);
}
