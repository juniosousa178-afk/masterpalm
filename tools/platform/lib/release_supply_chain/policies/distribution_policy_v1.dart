import '../../models/release_supply_chain/release_distribution_models.dart';
import '../../models/release_supply_chain/release_supply_chain_enums.dart';
import '../../models/release_supply_chain/release_supply_chain_operational_enums.dart';
import '../../models/release_supply_chain/release_supply_chain_policy_models.dart';

/// Candidate distribution policy v1.
class DistributionPolicyV1 {
  const DistributionPolicyV1._();

  static const policyId = 'distribution-v1';

  static RegisteredDistributionPolicy create() {
    return RegisteredDistributionPolicy(
      metadata: const RegisteredDistributionPolicyMetadata(
        policyId: policyId,
        policyVersion: 1,
        displayName: 'Production Distribution',
        status: ReleaseSupplyChainPolicyStatus.candidate,
        limitations: [
          'no-remote-distribution',
          'structural-manifest-only',
        ],
      ),
      policy: DistributionPolicy(
        policyId: policyId,
        policyVersion: 1,
        name: 'Production Distribution',
        allowedChannelTypes: [ReleaseChannelType.production],
        requiredTargetCount: 1,
        limitations: const [
          'no-remote-distribution',
        ],
      ),
    );
  }
}
