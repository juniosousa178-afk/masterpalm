import 'package:masterpalm_platform/models/release_evidence/release_evidence_collection_rule.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_policy.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_rule_value.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_evidence_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_policy_validator.dart';
import 'package:test/test.dart';

void main() {
  const validator = ReleaseEvidencePolicyValidator();

  ReleaseEvidencePolicy validPolicy() => ReleaseEvidencePolicyV1.create();

  group('ReleaseEvidencePolicyValidator', () {
    test('valid candidate policy passes', () {
      final result = validator.validate(validPolicy());
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });

    test('empty policyId fails', () {
      final base = validPolicy();
      final policy = ReleaseEvidencePolicy(
        metadata: ReleaseEvidencePolicyMetadata(
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
        requiredEvidenceTypes: base.requiredEvidenceTypes,
        requiredArtifactTypes: base.requiredArtifactTypes,
        compatibilityPolicy: base.compatibilityPolicy,
        eligibilityPolicy: base.eligibilityPolicy,
        coveragePolicy: base.coveragePolicy,
        retentionPolicy: base.retentionPolicy,
      );
      expect(validator.validate(policy).isValid, isFalse);
    });

    test('duplicate rule ID fails', () {
      final base = validPolicy();
      final rules = List<ReleaseEvidenceCollectionRule>.from(base.rules)
        ..add(base.rules.first);
      final result = validator.validate(_withRules(base, rules));
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('duplicate ruleId')), isTrue);
    });

    test('duplicate rule set ID fails', () {
      final base = validPolicy();
      final ruleSets =
          List<ReleaseEvidenceCollectionRuleSet>.from(base.ruleSets)
            ..add(base.ruleSets.first);
      final result = validator.validate(_withRuleSets(base, ruleSets));
      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('duplicate ruleSetId')),
        isTrue,
      );
    });

    test('rule without rule set fails', () {
      final base = validPolicy();
      final rules = base.rules
          .map(
            (r) => r.ruleId == 'RE001'
                ? ReleaseEvidenceCollectionRule(
                    ruleId: r.ruleId,
                    ruleSetId: 'missing-set',
                    name: r.name,
                    description: r.description,
                    target: r.target,
                    operator: r.operator,
                    expectedValue: r.expectedValue,
                    severity: r.severity,
                    requirement: r.requirement,
                    missingDataPolicy: r.missingDataPolicy,
                    incompatibleDataPolicy: r.incompatibleDataPolicy,
                    evidenceRole: r.evidenceRole,
                    rationale: r.rationale,
                    order: r.order,
                  )
                : r,
          )
          .toList();
      final result = validator.validate(_withRules(base, rules));
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('missing ruleSet')), isTrue);
    });

    test('operator without expected value fails', () {
      final base = validPolicy();
      final rules = base.rules
          .map(
            (r) => r.ruleId == 'RE009'
                ? ReleaseEvidenceCollectionRule(
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
                    evidenceRole: r.evidenceRole,
                    rationale: r.rationale,
                    order: r.order,
                  )
                : r,
          )
          .toList();
      final result = validator.validate(_withRules(base, rules));
      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('requires expectedValue')),
        isTrue,
      );
    });

    test('optional critical fails', () {
      final base = validPolicy();
      final rules = base.rules
          .map(
            (r) => r.ruleId == 'RE001'
                ? ReleaseEvidenceCollectionRule(
                    ruleId: r.ruleId,
                    ruleSetId: r.ruleSetId,
                    name: r.name,
                    description: r.description,
                    target: r.target,
                    operator: r.operator,
                    expectedValue: r.expectedValue,
                    severity: ReleaseEvidenceCollectionRuleSeverity.critical,
                    requirement:
                        ReleaseEvidenceCollectionRuleRequirement.optional,
                    missingDataPolicy: r.missingDataPolicy,
                    incompatibleDataPolicy: r.incompatibleDataPolicy,
                    evidenceRole: r.evidenceRole,
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

    test('invalid coverage percentage fails', () {
      final base = validPolicy();
      final policy = ReleaseEvidencePolicy(
        metadata: base.metadata,
        governance: base.governance,
        rules: base.rules,
        ruleSets: base.ruleSets,
        requiredEvidenceTypes: base.requiredEvidenceTypes,
        requiredArtifactTypes: base.requiredArtifactTypes,
        compatibilityPolicy: base.compatibilityPolicy,
        eligibilityPolicy: base.eligibilityPolicy,
        coveragePolicy: const ReleaseEvidenceCoveragePolicy(
          minimumEvidenceCoverage: 150,
        ),
        retentionPolicy: base.retentionPolicy,
      );
      final result = validator.validate(policy);
      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('coverage percentage')),
        isTrue,
      );
    });
  });
}

ReleaseEvidencePolicy _withRules(
  ReleaseEvidencePolicy base,
  List<ReleaseEvidenceCollectionRule> rules,
) {
  return ReleaseEvidencePolicy(
    metadata: base.metadata,
    governance: base.governance,
    rules: rules,
    ruleSets: base.ruleSets,
    requiredEvidenceTypes: base.requiredEvidenceTypes,
    requiredArtifactTypes: base.requiredArtifactTypes,
    compatibilityPolicy: base.compatibilityPolicy,
    eligibilityPolicy: base.eligibilityPolicy,
    coveragePolicy: base.coveragePolicy,
    retentionPolicy: base.retentionPolicy,
  );
}

ReleaseEvidencePolicy _withRuleSets(
  ReleaseEvidencePolicy base,
  List<ReleaseEvidenceCollectionRuleSet> ruleSets,
) {
  return ReleaseEvidencePolicy(
    metadata: base.metadata,
    governance: base.governance,
    rules: base.rules,
    ruleSets: ruleSets,
    requiredEvidenceTypes: base.requiredEvidenceTypes,
    requiredArtifactTypes: base.requiredArtifactTypes,
    compatibilityPolicy: base.compatibilityPolicy,
    eligibilityPolicy: base.eligibilityPolicy,
    coveragePolicy: base.coveragePolicy,
    retentionPolicy: base.retentionPolicy,
  );
}
