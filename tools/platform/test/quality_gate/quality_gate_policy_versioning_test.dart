import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_governance.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_policy.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_rule_value.dart';
import 'package:masterpalm_platform/quality_gate/policies/quality_gate_release_policy_v1.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_canonical_serializer.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_policy_registry.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_policy_validator.dart';
import 'package:test/test.dart';

void main() {
  group('Quality Gate policy versioning', () {
    test('threshold change alters policy fingerprint', () {
      const serializer = QualityGateCanonicalSerializer();
      final base = QualityGateReleasePolicyV1.create();
      final modified = _withRuleThreshold(base, 'QG005', 79);
      expect(
        serializer.policyFingerprint(modified),
        isNot(serializer.policyFingerprint(base)),
      );
    });

    test('operator change alters fingerprint', () {
      const serializer = QualityGateCanonicalSerializer();
      final base = QualityGateReleasePolicyV1.create();
      final modified = _withRuleOperator(
        base,
        'QG003',
        QualityGateRuleOperator.isFalse,
      );
      expect(
        serializer.policyFingerprint(modified),
        isNot(serializer.policyFingerprint(base)),
      );
    });

    test('registry rejects duplicate version', () {
      final registry = QualityGatePolicyRegistry();
      registry.register(QualityGateReleasePolicyV1.create());
      expect(
        () => registry.register(QualityGateReleasePolicyV1.create()),
        throwsA(isA<Exception>()),
      );
    });

    test('retired policy unavailable for new evaluation', () {
      final base = QualityGateReleasePolicyV1.create();
      final retired = QualityGatePolicy(
        metadata: QualityGatePolicyMetadata(
          policyId: 'quality-gate-release-v1',
          policyName: base.metadata.policyName,
          policyVersion: 1,
          schemaVersion: base.metadata.schemaVersion,
          calculationVersion: base.metadata.calculationVersion,
          canonicalizationVersion: base.metadata.canonicalizationVersion,
          status: QualityGatePolicyStatus.retired,
          owner: base.metadata.owner,
          createdAt: base.metadata.createdAt,
          rationale: base.metadata.rationale,
          changelog: base.metadata.changelog,
          policyFingerprint: base.metadata.policyFingerprint,
        ),
        governance: base.governance,
        decisionPolicy: base.decisionPolicy,
        requiredSourceTypes: base.requiredSourceTypes,
        ruleSets: base.ruleSets,
      );
      final registry = QualityGatePolicyRegistry();
      registry.register(retired);
      expect(
        registry.resolve(
          policyId: retired.metadata.policyId,
          policyVersion: 1,
        ),
        isNull,
      );
      expect(
        registry.resolve(
          policyId: retired.metadata.policyId,
          policyVersion: 1,
          historicalEvaluation: true,
        ),
        isNotNull,
      );
    });

    test('policy replay preserves decision fingerprint inputs', () {
      final original = QualityGateReleasePolicyV1.create();
      final restored = QualityGatePolicy.fromJson(original.toJson());
      const serializer = QualityGateCanonicalSerializer();
      expect(
        serializer.policyFingerprint(restored),
        serializer.policyFingerprint(original),
      );
      final validation = const QualityGatePolicyValidator().validate(restored);
      expect(validation.isValid, isTrue);
    });

    test('createdAt does not alter comparable policy fingerprint', () {
      const serializer = QualityGateCanonicalSerializer();
      final base = QualityGateReleasePolicyV1.create();
      final meta = base.metadata;
      final updated = QualityGatePolicy(
        metadata: QualityGatePolicyMetadata(
          policyId: meta.policyId,
          policyName: meta.policyName,
          policyVersion: meta.policyVersion,
          schemaVersion: meta.schemaVersion,
          calculationVersion: meta.calculationVersion,
          canonicalizationVersion: meta.canonicalizationVersion,
          status: meta.status,
          owner: meta.owner,
          createdAt: '2099-12-31T00:00:00.000Z',
          rationale: meta.rationale,
          changelog: meta.changelog,
          tags: meta.tags,
        ),
        governance: base.governance,
        decisionPolicy: base.decisionPolicy,
        requiredSourceTypes: base.requiredSourceTypes,
        ruleSets: base.ruleSets,
      );
      expect(
        serializer.policyFingerprint(updated),
        serializer.policyFingerprint(base),
      );
    });
  });
}

QualityGatePolicy _withRuleThreshold(
  QualityGatePolicy policy,
  String ruleId,
  num threshold,
) {
  final rule = policy.allRules.firstWhere((r) => r.ruleId == ruleId);
  return _replaceRule(
    policy,
    QualityGateRule(
      ruleId: rule.ruleId,
      name: rule.name,
      description: rule.description,
      target: rule.target,
      operator: rule.operator,
      expectedValue: QualityGateDecimalValue(threshold.toDouble()),
      requirement: rule.requirement,
      severity: rule.severity,
      missingDataPolicy: rule.missingDataPolicy,
      incompatibleDataPolicy: rule.incompatibleDataPolicy,
      evidencePolicy: rule.evidencePolicy,
      explanationTemplateId: rule.explanationTemplateId,
      order: rule.order,
    ),
  );
}

QualityGatePolicy _withRuleOperator(
  QualityGatePolicy policy,
  String ruleId,
  QualityGateRuleOperator operator,
) {
  final rule = policy.allRules.firstWhere((r) => r.ruleId == ruleId);
  return _replaceRule(
    policy,
    QualityGateRule(
      ruleId: rule.ruleId,
      name: rule.name,
      description: rule.description,
      target: rule.target,
      operator: operator,
      expectedValue: rule.expectedValue,
      requirement: rule.requirement,
      severity: rule.severity,
      missingDataPolicy: rule.missingDataPolicy,
      incompatibleDataPolicy: rule.incompatibleDataPolicy,
      evidencePolicy: rule.evidencePolicy,
      explanationTemplateId: rule.explanationTemplateId,
      order: rule.order,
    ),
  );
}

QualityGatePolicy _replaceRule(QualityGatePolicy policy, QualityGateRule rule) {
  return QualityGatePolicy(
    metadata: policy.metadata,
    governance: policy.governance,
    decisionPolicy: policy.decisionPolicy,
    requiredSourceTypes: policy.requiredSourceTypes,
    ruleSets: [
      for (final set in policy.ruleSets)
        QualityGateRuleSet(
          ruleSetId: set.ruleSetId,
          name: set.name,
          description: set.description,
          aggregationMode: set.aggregationMode,
          required: set.required,
          severity: set.severity,
          order: set.order,
          rules: [
            for (final r in set.rules) r.ruleId == rule.ruleId ? rule : r,
          ],
        ),
    ],
  );
}
