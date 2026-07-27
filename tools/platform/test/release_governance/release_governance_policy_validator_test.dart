import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_policy.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_rule_value.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1.dart';
import 'package:masterpalm_platform/release_governance/release_governance_policy_validator.dart';
import 'package:test/test.dart';

void main() {
  const validator = ReleaseGovernancePolicyValidator();

  ReleaseGovernancePolicy validPolicy() => ReleaseGovernancePolicyV1.create();

  group('ReleaseGovernancePolicyValidator', () {
    test('valid candidate policy passes', () {
      final result = validator.validate(validPolicy());
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });

    test('empty policyId fails', () {
      final base = validPolicy();
      final policy = ReleaseGovernancePolicy(
        metadata: ReleaseGovernancePolicyMetadata(
          policyId: '',
          policyVersion: base.metadata.policyVersion,
          displayName: base.metadata.displayName,
          description: base.metadata.description,
          owner: base.metadata.owner,
          status: base.metadata.status,
          schemaVersion: base.metadata.schemaVersion,
          calculationVersion: base.metadata.calculationVersion,
          canonicalizationVersion: base.metadata.canonicalizationVersion,
          createdAt: base.metadata.createdAt,
          changelog: base.metadata.changelog,
          rationale: base.metadata.rationale,
        ),
        governance: base.governance,
        rules: base.rules,
        ruleSets: base.ruleSets,
        approvalRequirements: base.approvalRequirements,
        waiverRules: base.waiverRules,
        decisionPolicy: base.decisionPolicy,
        evidencePolicy: base.evidencePolicy,
        compatibilityPolicy: base.compatibilityPolicy,
        eligibilityPolicy: base.eligibilityPolicy,
        supportedReleaseTypes: base.supportedReleaseTypes,
        supportedEnvironments: base.supportedEnvironments,
      );
      final result = validator.validate(policy);
      expect(result.isValid, isFalse);
      expect(result.errors, contains('policyId is required'));
    });

    test('duplicate rule ID fails', () {
      final base = validPolicy();
      final rules = List<ReleaseGovernanceRule>.from(base.rules);
      rules.add(rules.first);
      final policy = _withRules(base, rules);
      final result = validator.validate(policy);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('duplicate ruleId')), isTrue);
    });

    test('optional critical fails', () {
      final base = validPolicy();
      final rules = base.rules
          .map(
            (r) => r.ruleId == 'RG019'
                ? ReleaseGovernanceRule(
                    ruleId: r.ruleId,
                    ruleSetId: r.ruleSetId,
                    name: r.name,
                    description: r.description,
                    target: r.target,
                    operator: r.operator,
                    expectedValue: r.expectedValue,
                    severity: ReleaseGovernanceRuleSeverity.critical,
                    requirement: ReleaseGovernanceRuleRequirement.optional,
                    missingDataPolicy: r.missingDataPolicy,
                    incompatibleDataPolicy: r.incompatibleDataPolicy,
                    evidenceRequirement: r.evidenceRequirement,
                    waiverCapability: r.waiverCapability,
                    rationale: r.rationale,
                    order: r.order,
                  )
                : r,
          )
          .toList();
      final result = validator.validate(_withRules(base, rules));
      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('optional + critical')),
        isTrue,
      );
    });

    test('critical waiver allowed fails', () {
      final base = validPolicy();
      final rules = base.rules
          .map(
            (r) => r.ruleId == 'RG001'
                ? ReleaseGovernanceRule(
                    ruleId: r.ruleId,
                    ruleSetId: r.ruleSetId,
                    name: r.name,
                    description: r.description,
                    target: r.target,
                    operator: r.operator,
                    severity: r.severity,
                    requirement: r.requirement,
                    missingDataPolicy: r.missingDataPolicy,
                    incompatibleDataPolicy: r.incompatibleDataPolicy,
                    evidenceRequirement: r.evidenceRequirement,
                    waiverCapability: ReleaseGovernanceWaiverCapability.allowed,
                    rationale: r.rationale,
                    order: r.order,
                  )
                : r,
          )
          .toList();
      final result = validator.validate(_withRules(base, rules));
      expect(result.isValid, isFalse);
    });

    test('operator without expected value fails', () {
      final base = validPolicy();
      final rules = base.rules
          .map(
            (r) => r.ruleId == 'RG011'
                ? ReleaseGovernanceRule(
                    ruleId: r.ruleId,
                    ruleSetId: r.ruleSetId,
                    name: r.name,
                    description: r.description,
                    target: r.target,
                    operator: ReleaseGovernanceRuleOperator.equals,
                    severity: r.severity,
                    requirement: r.requirement,
                    missingDataPolicy: r.missingDataPolicy,
                    incompatibleDataPolicy: r.incompatibleDataPolicy,
                    evidenceRequirement: r.evidenceRequirement,
                    waiverCapability: r.waiverCapability,
                    rationale: r.rationale,
                    order: r.order,
                  )
                : r,
          )
          .toList();
      final result = validator.validate(_withRules(base, rules));
      expect(result.isValid, isFalse);
    });

    test('accepted quality gate decisions must not include failed', () {
      final base = validPolicy();
      final policy = ReleaseGovernancePolicy(
        metadata: base.metadata,
        governance: base.governance,
        rules: base.rules,
        ruleSets: base.ruleSets,
        approvalRequirements: base.approvalRequirements,
        waiverRules: base.waiverRules,
        decisionPolicy: ReleaseGovernanceDecisionPolicy(
          qualityGateAcceptedDecisions: const ['passed', 'failed'],
        ),
        evidencePolicy: base.evidencePolicy,
        compatibilityPolicy: base.compatibilityPolicy,
        eligibilityPolicy: base.eligibilityPolicy,
        supportedReleaseTypes: base.supportedReleaseTypes,
        supportedEnvironments: base.supportedEnvironments,
      );
      final result = validator.validate(policy);
      expect(result.isValid, isFalse);
    });
  });
}

ReleaseGovernancePolicy _withRules(
  ReleaseGovernancePolicy base,
  List<ReleaseGovernanceRule> rules,
) {
  return ReleaseGovernancePolicy(
    metadata: base.metadata,
    governance: base.governance,
    rules: rules,
    ruleSets: base.ruleSets,
    approvalRequirements: base.approvalRequirements,
    waiverRules: base.waiverRules,
    decisionPolicy: base.decisionPolicy,
    evidencePolicy: base.evidencePolicy,
    compatibilityPolicy: base.compatibilityPolicy,
    eligibilityPolicy: base.eligibilityPolicy,
    supportedReleaseTypes: base.supportedReleaseTypes,
    supportedEnvironments: base.supportedEnvironments,
  );
}
