import '../../models/release_governance/release_governance_enums.dart';
import '../../models/release_governance/release_governance_policy.dart';
import 'release_governance_policy_v1.dart';

/// Candidate release governance policy v1.1 — RG006 uses [isEligible].
///
/// v1 remains frozen with [ReleaseGovernanceRuleOperator.isValid] for RG006.
/// Migrate explicitly to this policy when eligibility semantics are required.
class ReleaseGovernancePolicyV11 {
  const ReleaseGovernancePolicyV11._();

  static const policyId = 'release-governance-v1.1';

  static ReleaseGovernancePolicy create() {
    final v1 = ReleaseGovernancePolicyV1.create();
    final rules = [
      for (final rule in v1.rules)
        if (rule.ruleId == 'RG006')
          ReleaseGovernanceRule(
            ruleId: rule.ruleId,
            ruleSetId: rule.ruleSetId,
            name: rule.name,
            description: rule.description,
            target: rule.target,
            operator: ReleaseGovernanceRuleOperator.isEligible,
            severity: rule.severity,
            requirement: rule.requirement,
            missingDataPolicy: rule.missingDataPolicy,
            incompatibleDataPolicy: rule.incompatibleDataPolicy,
            evidenceRequirement: rule.evidenceRequirement,
            waiverCapability: rule.waiverCapability,
            rationale:
                'RG006 v1.1: eligibility requires isEligible operator; isValid remains structural-only.',
            order: rule.order,
            selector: rule.selector,
            expectedValue: rule.expectedValue,
            enabled: rule.enabled,
            tags: [...rule.tags, 'rg006-eligibility-fix'],
          )
        else
          rule,
    ];

    final metadata = v1.metadata;
    return ReleaseGovernancePolicy(
      metadata: ReleaseGovernancePolicyMetadata(
        policyId: policyId,
        policyVersion: 2,
        displayName: '${metadata.displayName} (v1.1)',
        description:
            '${metadata.description} RG006 uses isEligible for normative eligibility.',
        owner: metadata.owner,
        status: ReleaseGovernancePolicyStatus.candidate,
        schemaVersion: metadata.schemaVersion,
        calculationVersion: metadata.calculationVersion,
        canonicalizationVersion: metadata.canonicalizationVersion,
        createdAt: '2026-07-01T00:00:00.000Z',
        rationale:
            'Migration from v1: RG006 operator changed from isValid to isEligible.',
        changelog: [
          ...metadata.changelog,
          const ReleaseGovernancePolicyChangelogEntry(
            version: 2,
            summary: 'RG006 uses isEligible instead of isValid',
            author: 'MasterPalm Engineering Governance',
            createdAt: '2026-07-01T00:00:00.000Z',
          ),
        ],
        tags: [...metadata.tags, 'v1.1', 'rg006-migration'],
      ),
      governance: v1.governance,
      rules: rules,
      ruleSets: v1.ruleSets,
      approvalRequirements: v1.approvalRequirements,
      waiverRules: v1.waiverRules,
      decisionPolicy: v1.decisionPolicy,
      evidencePolicy: v1.evidencePolicy,
      compatibilityPolicy: v1.compatibilityPolicy,
      eligibilityPolicy: v1.eligibilityPolicy,
      supportedReleaseTypes: v1.supportedReleaseTypes,
      supportedEnvironments: v1.supportedEnvironments,
      limitations: v1.limitations,
      extensions: v1.extensions,
    );
  }
}
