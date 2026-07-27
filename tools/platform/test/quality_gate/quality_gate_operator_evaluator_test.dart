import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_rule_value.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_operator_evaluator.dart';
import 'package:test/test.dart';

void main() {
  const evaluator = QualityGateOperatorEvaluator();

  group('QualityGateOperatorEvaluator', () {
    test('equals compares decimals with negative zero normalization', () {
      final result = evaluator.evaluate(
        operator: QualityGateRuleOperator.equals,
        actualValue: const QualityGateDecimalValue(-0.0),
        expectedValue: const QualityGateDecimalValue(0),
      );
      expect(result.passed, isTrue);
    });

    test('greaterThanOrEqual for percentage', () {
      final result = evaluator.evaluate(
        operator: QualityGateRuleOperator.greaterThanOrEqual,
        actualValue: const QualityGatePercentageValue(82),
        expectedValue: const QualityGatePercentageValue(80),
      );
      expect(result.passed, isTrue);
    });

    test('inSet accepts enum in set', () {
      final result = evaluator.evaluate(
        operator: QualityGateRuleOperator.inSet,
        actualValue: const QualityGateStringValue('GO'),
        expectedValue: const QualityGateSetValue(['GO', 'NO-GO']),
      );
      expect(result.passed, isTrue);
    });

    test('type mismatch returns typeError', () {
      final result = evaluator.evaluate(
        operator: QualityGateRuleOperator.greaterThan,
        actualValue: const QualityGateStringValue('80'),
        expectedValue: const QualityGateDecimalValue(75),
      );
      expect(result.passed, isFalse);
      expect(result.typeError, isTrue);
    });

    test('exists passes when value present', () {
      final result = evaluator.evaluate(
        operator: QualityGateRuleOperator.exists,
        actualValue: const QualityGateBooleanValue(true),
      );
      expect(result.passed, isTrue);
    });

    test('betweenInclusive validates range', () {
      final result = evaluator.evaluate(
        operator: QualityGateRuleOperator.betweenInclusive,
        actualValue: const QualityGateDecimalValue(50),
        expectedValue: const QualityGateRangeValue(lower: 40, upper: 60),
      );
      expect(result.passed, isTrue);
    });
  });
}
