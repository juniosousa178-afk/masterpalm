import '../../models/release_supply_chain/release_supply_chain_enums.dart';
import '../../models/release_supply_chain/release_supply_chain_operational_enums.dart';
import '../../models/release_supply_chain/release_supply_chain_policy_models.dart';
import '../../models/release_supply_chain/supply_chain_models.dart';

/// Candidate supply chain policy v1.
class SupplyChainPolicyV1 {
  const SupplyChainPolicyV1._();

  static const policyId = 'supply-chain-v1';

  static RegisteredSupplyChainPolicy create() {
    return RegisteredSupplyChainPolicy(
      metadata: const RegisteredSupplyChainPolicyMetadata(
        policyId: policyId,
        policyVersion: 1,
        displayName: 'Default Supply Chain Policy',
        status: ReleaseSupplyChainPolicyStatus.candidate,
        limitations: [
          'no-cryptographic-verification',
          'no-remote-artifact-fetch',
          'structural-compliance-only',
        ],
      ),
      policy: SupplyChainPolicy(
        policyId: policyId,
        policyVersion: 1,
        name: 'Default Supply Chain Policy',
        requiredStageTypes: [
          SupplyChainStageType.build,
          SupplyChainStageType.source,
          SupplyChainStageType.test,
        ],
        minimumEvidenceCount: 1,
        limitations: const [
          'no-cryptographic-verification',
          'no-remote-artifact-fetch',
        ],
      ),
    );
  }
}
