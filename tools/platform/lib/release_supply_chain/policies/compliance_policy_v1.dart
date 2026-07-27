import '../../models/release_supply_chain/compliance_models.dart';
import '../../models/release_supply_chain/release_supply_chain_enums.dart';
import '../../models/release_supply_chain/release_supply_chain_operational_enums.dart';
import '../../models/release_supply_chain/release_supply_chain_policy_models.dart';

/// Candidate compliance policy v1.
class CompliancePolicyV1 {
  const CompliancePolicyV1._();

  static const policyId = 'compliance-v1';

  static RegisteredCompliancePolicy create() {
    return RegisteredCompliancePolicy(
      metadata: const RegisteredCompliancePolicyMetadata(
        policyId: policyId,
        policyVersion: 1,
        displayName: 'Release Compliance',
        status: ReleaseSupplyChainPolicyStatus.candidate,
        limitations: [
          'structural-rules-only',
          'never-approves-release',
        ],
      ),
      policy: CompliancePolicy(
        policyId: policyId,
        policyVersion: 1,
        name: 'Release Compliance',
        rules: const [
          ComplianceRule(
            ruleId: 'COMP001',
            name: 'Evidence bundle required',
            severity: ComplianceRuleSeverity.high,
            expression: 'releaseEvidenceBundleId != null',
          ),
          ComplianceRule(
            ruleId: 'COMP002',
            name: 'Project consistency',
            severity: ComplianceRuleSeverity.high,
            expression: 'projectId != null',
          ),
          ComplianceRule(
            ruleId: 'COMP003',
            name: 'Provenance fingerprint present',
            severity: ComplianceRuleSeverity.medium,
            expression: 'provenanceFingerprint != null',
          ),
        ],
        limitations: const [
          'structural-rules-only',
          'never-approves-release',
        ],
      ),
    );
  }
}
