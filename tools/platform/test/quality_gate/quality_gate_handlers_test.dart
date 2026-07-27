import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_evidence.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_policy.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_rule_value.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_handlers.dart';
import 'package:test/test.dart';

QualityGateRule _rule({
  QualityGateRuleRequirement requirement = QualityGateRuleRequirement.required,
  QualityGateRuleSeverity severity = QualityGateRuleSeverity.blocking,
  QualityGateMissingDataPolicy missing = QualityGateMissingDataPolicy.fail,
  QualityGateIncompatibleDataPolicy incompatible =
      QualityGateIncompatibleDataPolicy.fail,
}) {
  return QualityGateRule(
    ruleId: 'TEST',
    name: 'Test',
    description: 'Test rule',
    target: QualityGateRuleTarget.guardianDecision,
    operator: QualityGateRuleOperator.exists,
    requirement: requirement,
    severity: severity,
    missingDataPolicy: missing,
    incompatibleDataPolicy: incompatible,
    evidencePolicy: const QualityGateEvidencePolicy(),
    explanationTemplateId: 'test',
    order: 1,
  );
}

void main() {
  const missingHandler = QualityGateMissingDataHandler();
  const incompatibleHandler = QualityGateIncompatibleDataHandler();
  const impactResolver = QualityGateDecisionImpactResolver();

  group('QualityGateMissingDataHandler', () {
    test('fail on required produces failed and blocksApproval', () {
      final outcome = missingHandler
          .handle(_rule(missing: QualityGateMissingDataPolicy.fail));
      expect(outcome.status, QualityGateRuleStatus.failed);
      expect(outcome.decisionImpact, QualityGateDecisionImpact.blocksApproval);
    });

    test('partial produces unavailable and contributesToPartial', () {
      final outcome = missingHandler
          .handle(_rule(missing: QualityGateMissingDataPolicy.partial));
      expect(outcome.status, QualityGateRuleStatus.unavailable);
      expect(outcome.decisionImpact,
          QualityGateDecisionImpact.contributesToPartial);
    });

    test('informational is notApplicable', () {
      final outcome = missingHandler.handle(
        _rule(requirement: QualityGateRuleRequirement.informational),
      );
      expect(outcome.status, QualityGateRuleStatus.notApplicable);
      expect(outcome.decisionImpact, QualityGateDecisionImpact.none);
    });
  });

  group('QualityGateIncompatibleDataHandler', () {
    test('incompatible policy produces incompatible status', () {
      final outcome = incompatibleHandler.handle(
        _rule(incompatible: QualityGateIncompatibleDataPolicy.incompatible),
      );
      expect(outcome.status, QualityGateRuleStatus.incompatible);
      expect(
          outcome.decisionImpact, QualityGateDecisionImpact.causesIncompatible);
    });
  });

  group('QualityGateDecisionImpactResolver', () {
    test('passed has no impact', () {
      final impact = impactResolver.resolve(
        rule: _rule(),
        status: QualityGateRuleStatus.passed,
        decisionPolicy: const QualityGateDecisionPolicy(),
      );
      expect(impact, QualityGateDecisionImpact.none);
    });

    test('critical failure blocks approval', () {
      final impact = impactResolver.resolve(
        rule: _rule(severity: QualityGateRuleSeverity.critical),
        status: QualityGateRuleStatus.failed,
        decisionPolicy: const QualityGateDecisionPolicy(),
      );
      expect(impact, QualityGateDecisionImpact.blocksApproval);
    });

    test('optional failure does not block by default', () {
      final impact = impactResolver.resolve(
        rule: _rule(requirement: QualityGateRuleRequirement.optional),
        status: QualityGateRuleStatus.failed,
        decisionPolicy: const QualityGateDecisionPolicy(
          optionalFailuresAffectDecision: false,
        ),
      );
      expect(impact, isNot(QualityGateDecisionImpact.blocksApproval));
    });

    test('error maps to internalError', () {
      final impact = impactResolver.resolve(
        rule: _rule(),
        status: QualityGateRuleStatus.error,
        decisionPolicy: const QualityGateDecisionPolicy(),
        operatorTypeError: true,
      );
      expect(impact, QualityGateDecisionImpact.internalError);
    });
  });
}
