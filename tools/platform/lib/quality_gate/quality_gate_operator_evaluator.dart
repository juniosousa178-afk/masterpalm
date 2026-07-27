import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_rule_value.dart';

/// Result of applying a typed operator to actual/expected values.
class QualityGateOperatorEvaluation {
  const QualityGateOperatorEvaluation({
    required this.passed,
    this.typeError = false,
    this.message,
  });

  final bool passed;
  final bool typeError;
  final String? message;
}

/// Applies typed comparison operators to rule values.
class QualityGateOperatorEvaluator {
  const QualityGateOperatorEvaluator();

  QualityGateOperatorEvaluation evaluate({
    required QualityGateRuleOperator operator,
    required QualityGateRuleValue? actualValue,
    QualityGateRuleValue? expectedValue,
  }) {
    switch (operator) {
      case QualityGateRuleOperator.isTrue:
        return _boolState(actualValue, true);
      case QualityGateRuleOperator.isFalse:
        return _boolState(actualValue, false);
      case QualityGateRuleOperator.isAvailable:
        return _availabilityState(actualValue, available: true);
      case QualityGateRuleOperator.isUnavailable:
        return _availabilityState(actualValue, available: false);
      case QualityGateRuleOperator.isCompatible:
        return _compatibilityState(actualValue, compatible: true);
      case QualityGateRuleOperator.isIncompatible:
        return _compatibilityState(actualValue, compatible: false);
      case QualityGateRuleOperator.isEligible:
        return _eligibilityState(actualValue, eligible: true);
      case QualityGateRuleOperator.isNotEligible:
        return _eligibilityState(actualValue, eligible: false);
      case QualityGateRuleOperator.isEmpty:
        return _emptiness(actualValue, empty: true);
      case QualityGateRuleOperator.isNotEmpty:
        return _emptiness(actualValue, empty: false);
      case QualityGateRuleOperator.exists:
        return QualityGateOperatorEvaluation(
          passed: actualValue != null,
        );
      case QualityGateRuleOperator.doesNotExist:
        return QualityGateOperatorEvaluation(
          passed: actualValue == null,
        );
      case QualityGateRuleOperator.equals:
        return _equals(actualValue, expectedValue);
      case QualityGateRuleOperator.notEquals:
        final eq = _equals(actualValue, expectedValue);
        return QualityGateOperatorEvaluation(
            passed: !eq.passed, message: eq.message);
      case QualityGateRuleOperator.greaterThan:
        return _compareNumeric(actualValue, expectedValue, (a, b) => a > b);
      case QualityGateRuleOperator.greaterThanOrEqual:
        return _compareNumeric(actualValue, expectedValue, (a, b) => a >= b);
      case QualityGateRuleOperator.lessThan:
        return _compareNumeric(actualValue, expectedValue, (a, b) => a < b);
      case QualityGateRuleOperator.lessThanOrEqual:
        return _compareNumeric(actualValue, expectedValue, (a, b) => a <= b);
      case QualityGateRuleOperator.contains:
        return _contains(actualValue, expectedValue, negate: false);
      case QualityGateRuleOperator.notContains:
        return _contains(actualValue, expectedValue, negate: true);
      case QualityGateRuleOperator.containsAny:
        return _containsAny(actualValue, expectedValue, all: false);
      case QualityGateRuleOperator.containsAll:
        return _containsAny(actualValue, expectedValue, all: true);
      case QualityGateRuleOperator.betweenInclusive:
        return _between(actualValue, expectedValue, inclusive: true);
      case QualityGateRuleOperator.betweenExclusive:
        return _between(actualValue, expectedValue, inclusive: false);
      case QualityGateRuleOperator.outsideRange:
        final inside = _between(actualValue, expectedValue, inclusive: true);
        return QualityGateOperatorEvaluation(passed: !inside.passed);
      case QualityGateRuleOperator.inSet:
        return _inSet(actualValue, expectedValue, negate: false);
      case QualityGateRuleOperator.notInSet:
        return _inSet(actualValue, expectedValue, negate: true);
    }
  }

  QualityGateOperatorEvaluation _boolState(
    QualityGateRuleValue? actual,
    bool expected,
  ) {
    if (actual is! QualityGateBooleanValue) {
      return const QualityGateOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Boolean operator requires boolean value',
      );
    }
    return QualityGateOperatorEvaluation(passed: actual.value == expected);
  }

  QualityGateOperatorEvaluation _availabilityState(
    QualityGateRuleValue? actual, {
    required bool available,
  }) {
    if (actual is QualityGateBooleanValue) {
      return QualityGateOperatorEvaluation(passed: actual.value == available);
    }
    if (actual is QualityGateStringValue) {
      final normalized = actual.value.toLowerCase();
      final isAvailable = normalized == 'available' || normalized == 'true';
      return QualityGateOperatorEvaluation(
        passed: available ? isAvailable : !isAvailable,
      );
    }
    return QualityGateOperatorEvaluation(
      passed: available ? actual != null : actual == null,
    );
  }

  QualityGateOperatorEvaluation _compatibilityState(
    QualityGateRuleValue? actual, {
    required bool compatible,
  }) {
    if (actual is QualityGateBooleanValue) {
      return QualityGateOperatorEvaluation(passed: actual.value == compatible);
    }
    if (actual is QualityGateEnumValue) {
      final normalized = actual.value.toLowerCase();
      final isCompatible =
          normalized == 'compatible' || normalized == 'partiallycompatible';
      return QualityGateOperatorEvaluation(
        passed: compatible ? isCompatible : !isCompatible,
      );
    }
    return const QualityGateOperatorEvaluation(
      passed: false,
      typeError: true,
      message: 'Compatibility operator requires boolean or enum value',
    );
  }

  QualityGateOperatorEvaluation _eligibilityState(
    QualityGateRuleValue? actual, {
    required bool eligible,
  }) {
    if (actual is QualityGateBooleanValue) {
      return QualityGateOperatorEvaluation(passed: actual.value == eligible);
    }
    if (actual is QualityGateEnumValue) {
      final normalized = actual.value.toLowerCase();
      final isEligible =
          normalized == 'eligible' || normalized == 'partiallyeligible';
      return QualityGateOperatorEvaluation(
        passed: eligible ? isEligible : !isEligible,
      );
    }
    return const QualityGateOperatorEvaluation(
      passed: false,
      typeError: true,
      message: 'Eligibility operator requires boolean or enum value',
    );
  }

  QualityGateOperatorEvaluation _emptiness(
    QualityGateRuleValue? actual, {
    required bool empty,
  }) {
    if (actual == null) {
      return QualityGateOperatorEvaluation(passed: empty);
    }
    if (actual is QualityGateSetValue) {
      return QualityGateOperatorEvaluation(
        passed: empty ? actual.values.isEmpty : actual.values.isNotEmpty,
      );
    }
    if (actual is QualityGateStringValue) {
      return QualityGateOperatorEvaluation(
        passed: empty ? actual.value.isEmpty : actual.value.isNotEmpty,
      );
    }
    return QualityGateOperatorEvaluation(passed: !empty);
  }

  QualityGateOperatorEvaluation _equals(
    QualityGateRuleValue? actual,
    QualityGateRuleValue? expected,
  ) {
    if (actual == null || expected == null) {
      return const QualityGateOperatorEvaluation(
        passed: false,
        message: 'Missing actual or expected value',
      );
    }
    if (actual.valueKind != expected.valueKind) {
      final actualNum = _asNum(actual);
      final expectedNum = _asNum(expected);
      if (actualNum != null && expectedNum != null) {
        return QualityGateOperatorEvaluation(
          passed: actualNum == expectedNum,
        );
      }
      return const QualityGateOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Incompatible value kinds for equality',
      );
    }
    switch (actual) {
      case QualityGateBooleanValue():
        return QualityGateOperatorEvaluation(
          passed: actual.value == (expected as QualityGateBooleanValue).value,
        );
      case QualityGateIntegerValue():
        return QualityGateOperatorEvaluation(
          passed: actual.value == (expected as QualityGateIntegerValue).value,
        );
      case QualityGateDecimalValue():
        return QualityGateOperatorEvaluation(
          passed: actual.value == (expected as QualityGateDecimalValue).value,
        );
      case QualityGatePercentageValue():
        return QualityGateOperatorEvaluation(
          passed:
              actual.value == (expected as QualityGatePercentageValue).value,
        );
      case QualityGateStringValue():
        return QualityGateOperatorEvaluation(
          passed: actual.value == (expected as QualityGateStringValue).value,
        );
      case QualityGateEnumValue():
        final exp = expected as QualityGateEnumValue;
        return QualityGateOperatorEvaluation(
          passed: actual.domain == exp.domain && actual.value == exp.value,
        );
      case QualityGateRangeValue():
        final exp = expected as QualityGateRangeValue;
        return QualityGateOperatorEvaluation(
          passed: actual.lower == exp.lower && actual.upper == exp.upper,
        );
      case QualityGateSetValue():
        final exp = expected as QualityGateSetValue;
        return QualityGateOperatorEvaluation(
          passed: _listEquals(actual.values, exp.values),
        );
      case QualityGateVersionValue():
        final exp = expected as QualityGateVersionValue;
        return QualityGateOperatorEvaluation(
          passed: actual.major == exp.major &&
              actual.minor == exp.minor &&
              actual.patch == exp.patch,
        );
      case QualityGateArtifactReferenceValue():
        final exp = expected as QualityGateArtifactReferenceValue;
        return QualityGateOperatorEvaluation(
          passed: actual.artifactType == exp.artifactType &&
              actual.artifactId == exp.artifactId,
        );
      default:
        return const QualityGateOperatorEvaluation(
          passed: false,
          typeError: true,
          message: 'Unsupported value kind for equality',
        );
    }
  }

  QualityGateOperatorEvaluation _compareNumeric(
    QualityGateRuleValue? actual,
    QualityGateRuleValue? expected,
    bool Function(double actual, double expected) compare,
  ) {
    final actualNum = _asNum(actual);
    final expectedNum = _asNum(expected);
    if (actualNum == null || expectedNum == null) {
      return const QualityGateOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Numeric operator requires numeric values',
      );
    }
    return QualityGateOperatorEvaluation(
      passed: compare(actualNum, expectedNum),
    );
  }

  QualityGateOperatorEvaluation _between(
    QualityGateRuleValue? actual,
    QualityGateRuleValue? expected, {
    required bool inclusive,
  }) {
    final actualNum = _asNum(actual);
    if (actualNum == null) {
      return const QualityGateOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Range operator requires numeric actual value',
      );
    }
    if (expected is! QualityGateRangeValue) {
      return const QualityGateOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Range operator requires range expected value',
      );
    }
    final inside = inclusive
        ? actualNum >= expected.lower && actualNum <= expected.upper
        : actualNum > expected.lower && actualNum < expected.upper;
    return QualityGateOperatorEvaluation(passed: inside);
  }

  QualityGateOperatorEvaluation _contains(
    QualityGateRuleValue? actual,
    QualityGateRuleValue? expected, {
    required bool negate,
  }) {
    if (actual == null || expected == null) {
      return QualityGateOperatorEvaluation(passed: negate);
    }
    var matched = false;
    if (actual is QualityGateStringValue &&
        expected is QualityGateStringValue) {
      matched = actual.value.contains(expected.value);
    } else if (actual is QualityGateSetValue &&
        expected is QualityGateStringValue) {
      matched = actual.values.contains(expected.value);
    } else {
      return const QualityGateOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Contains operator requires string or set actual value',
      );
    }
    return QualityGateOperatorEvaluation(passed: negate ? !matched : matched);
  }

  QualityGateOperatorEvaluation _containsAny(
    QualityGateRuleValue? actual,
    QualityGateRuleValue? expected, {
    required bool all,
  }) {
    if (expected is! QualityGateSetValue) {
      return const QualityGateOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Set operator requires set expected value',
      );
    }
    final actualItems = _asStringCollection(actual);
    if (actualItems == null) {
      return const QualityGateOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Set operator requires set or string actual value',
      );
    }
    if (all) {
      return QualityGateOperatorEvaluation(
        passed: expected.values.every(actualItems.contains),
      );
    }
    return QualityGateOperatorEvaluation(
      passed: expected.values.any(actualItems.contains),
    );
  }

  QualityGateOperatorEvaluation _inSet(
    QualityGateRuleValue? actual,
    QualityGateRuleValue? expected, {
    required bool negate,
  }) {
    if (expected is! QualityGateSetValue) {
      return const QualityGateOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'inSet operator requires set expected value',
      );
    }
    final actualText = _asComparableString(actual);
    if (actualText == null) {
      return QualityGateOperatorEvaluation(passed: negate);
    }
    final matched = expected.values.contains(actualText);
    return QualityGateOperatorEvaluation(passed: negate ? !matched : matched);
  }

  double? _asNum(QualityGateRuleValue? value) {
    return switch (value) {
      QualityGateIntegerValue(:final value) => value.toDouble(),
      QualityGateDecimalValue(:final value) => value,
      QualityGatePercentageValue(:final value) => value,
      _ => null,
    };
  }

  List<String>? _asStringCollection(QualityGateRuleValue? value) {
    if (value is QualityGateSetValue) return value.values;
    if (value is QualityGateStringValue) return [value.value];
    return null;
  }

  String? _asComparableString(QualityGateRuleValue? value) {
    return switch (value) {
      QualityGateStringValue(:final value) => value,
      QualityGateEnumValue(:final value) => value,
      QualityGateIntegerValue(:final value) => value.toString(),
      QualityGateDecimalValue(:final value) => value.toString(),
      QualityGatePercentageValue(:final value) => value.toString(),
      QualityGateBooleanValue(:final value) => value.toString(),
      _ => null,
    };
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final sortedA = List<String>.from(a)..sort();
    final sortedB = List<String>.from(b)..sort();
    for (var i = 0; i < sortedA.length; i++) {
      if (sortedA[i] != sortedB[i]) return false;
    }
    return true;
  }
}
