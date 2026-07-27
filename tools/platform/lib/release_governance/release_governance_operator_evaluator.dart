import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_rule_value.dart';

/// Result of applying a typed operator to actual/expected values.
class ReleaseGovernanceOperatorEvaluation {
  const ReleaseGovernanceOperatorEvaluation({
    required this.passed,
    this.typeError = false,
    this.message,
  });

  final bool passed;
  final bool typeError;
  final String? message;
}

/// Applies typed comparison operators to rule values.
class ReleaseGovernanceOperatorEvaluator {
  const ReleaseGovernanceOperatorEvaluator();

  ReleaseGovernanceOperatorEvaluation evaluate({
    required ReleaseGovernanceRuleOperator operator,
    required ReleaseGovernanceRuleValue? actualValue,
    ReleaseGovernanceRuleValue? expectedValue,
    String? referenceTime,
  }) {
    switch (operator) {
      case ReleaseGovernanceRuleOperator.isTrue:
        return _boolState(actualValue, true);
      case ReleaseGovernanceRuleOperator.isFalse:
        return _boolState(actualValue, false);
      case ReleaseGovernanceRuleOperator.isAvailable:
        return _availabilityState(actualValue, available: true);
      case ReleaseGovernanceRuleOperator.isUnavailable:
        return _availabilityState(actualValue, available: false);
      case ReleaseGovernanceRuleOperator.isCompatible:
        return _compatibilityState(actualValue, compatible: true);
      case ReleaseGovernanceRuleOperator.isIncompatible:
        return _compatibilityState(actualValue, compatible: false);
      case ReleaseGovernanceRuleOperator.isEligible:
        return _eligibilityState(actualValue, eligible: true);
      case ReleaseGovernanceRuleOperator.isNotEligible:
        return _eligibilityState(actualValue, eligible: false);
      case ReleaseGovernanceRuleOperator.isValid:
        return _validityState(actualValue, true, referenceTime);
      case ReleaseGovernanceRuleOperator.isInvalid:
        return _validityState(actualValue, false, referenceTime);
      case ReleaseGovernanceRuleOperator.isExpired:
        return _expirationState(actualValue, true, referenceTime);
      case ReleaseGovernanceRuleOperator.isNotExpired:
        return _expirationState(actualValue, false, referenceTime);
      case ReleaseGovernanceRuleOperator.exists:
        return ReleaseGovernanceOperatorEvaluation(
          passed: actualValue != null,
        );
      case ReleaseGovernanceRuleOperator.doesNotExist:
        return ReleaseGovernanceOperatorEvaluation(
          passed: actualValue == null,
        );
      case ReleaseGovernanceRuleOperator.equals:
        return _equals(actualValue, expectedValue);
      case ReleaseGovernanceRuleOperator.notEquals:
        final eq = _equals(actualValue, expectedValue);
        return ReleaseGovernanceOperatorEvaluation(
          passed: !eq.passed,
          message: eq.message,
        );
      case ReleaseGovernanceRuleOperator.greaterThan:
        return _compareNumeric(actualValue, expectedValue, (a, b) => a > b);
      case ReleaseGovernanceRuleOperator.greaterThanOrEqual:
        return _compareNumeric(actualValue, expectedValue, (a, b) => a >= b);
      case ReleaseGovernanceRuleOperator.lessThan:
        return _compareNumeric(actualValue, expectedValue, (a, b) => a < b);
      case ReleaseGovernanceRuleOperator.lessThanOrEqual:
        return _compareDuration(actualValue, expectedValue, (a, b) => a <= b);
      case ReleaseGovernanceRuleOperator.betweenInclusive:
        return _between(actualValue, expectedValue, inclusive: true);
      case ReleaseGovernanceRuleOperator.betweenExclusive:
        return _between(actualValue, expectedValue, inclusive: false);
      case ReleaseGovernanceRuleOperator.contains:
        return _contains(actualValue, expectedValue, negate: false);
      case ReleaseGovernanceRuleOperator.containsAny:
        return _containsAny(actualValue, expectedValue, all: false);
      case ReleaseGovernanceRuleOperator.containsAll:
        return _containsAny(actualValue, expectedValue, all: true);
      case ReleaseGovernanceRuleOperator.inSet:
        return _inSet(actualValue, expectedValue, negate: false);
      case ReleaseGovernanceRuleOperator.notInSet:
        return _inSet(actualValue, expectedValue, negate: true);
    }
  }

  ReleaseGovernanceOperatorEvaluation _boolState(
    ReleaseGovernanceRuleValue? actual,
    bool expected,
  ) {
    if (actual is! ReleaseGovernanceBooleanValue) {
      return const ReleaseGovernanceOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Boolean operator requires boolean value',
      );
    }
    return ReleaseGovernanceOperatorEvaluation(
        passed: actual.value == expected);
  }

  ReleaseGovernanceOperatorEvaluation _availabilityState(
    ReleaseGovernanceRuleValue? actual, {
    required bool available,
  }) {
    if (actual is ReleaseGovernanceBooleanValue) {
      return ReleaseGovernanceOperatorEvaluation(
        passed: actual.value == available,
      );
    }
    if (actual is ReleaseGovernanceStringValue) {
      final normalized = actual.value.toLowerCase();
      final isAvailable = normalized == 'available' ||
          normalized == 'true' ||
          normalized == 'passed';
      return ReleaseGovernanceOperatorEvaluation(
        passed: available ? isAvailable : !isAvailable,
      );
    }
    return ReleaseGovernanceOperatorEvaluation(
      passed: available ? actual != null : actual == null,
    );
  }

  ReleaseGovernanceOperatorEvaluation _compatibilityState(
    ReleaseGovernanceRuleValue? actual, {
    required bool compatible,
  }) {
    if (actual is ReleaseGovernanceBooleanValue) {
      return ReleaseGovernanceOperatorEvaluation(
        passed: actual.value == compatible,
      );
    }
    if (actual is ReleaseGovernanceEnumValue) {
      final normalized = actual.value.toLowerCase();
      final isCompatible =
          normalized == 'compatible' || normalized == 'partiallycompatible';
      return ReleaseGovernanceOperatorEvaluation(
        passed: compatible ? isCompatible : !isCompatible,
      );
    }
    return const ReleaseGovernanceOperatorEvaluation(
      passed: false,
      typeError: true,
      message: 'Compatibility operator requires boolean or enum value',
    );
  }

  ReleaseGovernanceOperatorEvaluation _eligibilityState(
    ReleaseGovernanceRuleValue? actual, {
    required bool eligible,
  }) {
    if (actual is ReleaseGovernanceBooleanValue) {
      return ReleaseGovernanceOperatorEvaluation(
        passed: actual.value == eligible,
      );
    }
    if (actual is ReleaseGovernanceEnumValue) {
      final normalized = actual.value.toLowerCase();
      final isEligible =
          normalized == 'eligible' || normalized == 'partiallyeligible';
      return ReleaseGovernanceOperatorEvaluation(
        passed: eligible ? isEligible : !isEligible,
      );
    }
    return const ReleaseGovernanceOperatorEvaluation(
      passed: false,
      typeError: true,
      message: 'Eligibility operator requires boolean or enum value',
    );
  }

  ReleaseGovernanceOperatorEvaluation _validityState(
    ReleaseGovernanceRuleValue? actual,
    bool valid,
    String? referenceTime,
  ) {
    if (actual is ReleaseGovernanceBooleanValue) {
      return ReleaseGovernanceOperatorEvaluation(passed: actual.value == valid);
    }
    if (actual is ReleaseGovernanceDateTimeValue && referenceTime != null) {
      final ref = DateTime.tryParse(referenceTime)?.toUtc();
      final value = DateTime.tryParse(actual.value)?.toUtc();
      if (ref == null || value == null) {
        return const ReleaseGovernanceOperatorEvaluation(
          passed: false,
          message: 'Invalid dateTime for validity check',
        );
      }
      final isValid = !value.isAfter(ref);
      return ReleaseGovernanceOperatorEvaluation(
          passed: valid ? isValid : !isValid);
    }
    return ReleaseGovernanceOperatorEvaluation(
      passed: valid ? actual != null : actual == null,
    );
  }

  ReleaseGovernanceOperatorEvaluation _expirationState(
    ReleaseGovernanceRuleValue? actual,
    bool expired,
    String? referenceTime,
  ) {
    if (actual is ReleaseGovernanceBooleanValue) {
      return ReleaseGovernanceOperatorEvaluation(
        passed: actual.value == expired,
      );
    }
    if (actual is ReleaseGovernanceDateTimeValue && referenceTime != null) {
      final ref = DateTime.tryParse(referenceTime)?.toUtc();
      final value = DateTime.tryParse(actual.value)?.toUtc();
      if (ref == null || value == null) {
        return const ReleaseGovernanceOperatorEvaluation(
          passed: false,
          message: 'Invalid dateTime for expiration check',
        );
      }
      final isExpired = value.isBefore(ref);
      return ReleaseGovernanceOperatorEvaluation(
        passed: expired ? isExpired : !isExpired,
      );
    }
    return const ReleaseGovernanceOperatorEvaluation(
      passed: false,
      typeError: true,
      message: 'Expiration operator requires boolean or dateTime value',
    );
  }

  ReleaseGovernanceOperatorEvaluation _equals(
    ReleaseGovernanceRuleValue? actual,
    ReleaseGovernanceRuleValue? expected,
  ) {
    if (actual == null || expected == null) {
      return const ReleaseGovernanceOperatorEvaluation(
        passed: false,
        message: 'Missing actual or expected value',
      );
    }
    if (actual.valueKind != expected.valueKind) {
      final actualNum = _asNum(actual);
      final expectedNum = _asNum(expected);
      if (actualNum != null && expectedNum != null) {
        return ReleaseGovernanceOperatorEvaluation(
          passed: actualNum == expectedNum,
        );
      }
      return const ReleaseGovernanceOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Incompatible value kinds for equality',
      );
    }
    switch (actual) {
      case ReleaseGovernanceBooleanValue():
        return ReleaseGovernanceOperatorEvaluation(
          passed:
              actual.value == (expected as ReleaseGovernanceBooleanValue).value,
        );
      case ReleaseGovernanceIntegerValue():
        return ReleaseGovernanceOperatorEvaluation(
          passed:
              actual.value == (expected as ReleaseGovernanceIntegerValue).value,
        );
      case ReleaseGovernanceDecimalValue():
        return ReleaseGovernanceOperatorEvaluation(
          passed:
              actual.value == (expected as ReleaseGovernanceDecimalValue).value,
        );
      case ReleaseGovernancePercentageValue():
        return ReleaseGovernanceOperatorEvaluation(
          passed: actual.value ==
              (expected as ReleaseGovernancePercentageValue).value,
        );
      case ReleaseGovernanceStringValue():
        return ReleaseGovernanceOperatorEvaluation(
          passed:
              actual.value == (expected as ReleaseGovernanceStringValue).value,
        );
      case ReleaseGovernanceEnumValue():
        final exp = expected as ReleaseGovernanceEnumValue;
        return ReleaseGovernanceOperatorEvaluation(
          passed: actual.domain == exp.domain && actual.value == exp.value,
        );
      case ReleaseGovernanceRangeValue():
        final exp = expected as ReleaseGovernanceRangeValue;
        return ReleaseGovernanceOperatorEvaluation(
          passed: actual.lower == exp.lower && actual.upper == exp.upper,
        );
      case ReleaseGovernanceSetValue():
        final exp = expected as ReleaseGovernanceSetValue;
        return ReleaseGovernanceOperatorEvaluation(
          passed: _listEquals(actual.values, exp.values),
        );
      case ReleaseGovernanceDurationValue():
        final exp = expected as ReleaseGovernanceDurationValue;
        return ReleaseGovernanceOperatorEvaluation(
          passed: _durationToSeconds(actual.iso8601Duration) ==
              _durationToSeconds(exp.iso8601Duration),
        );
      default:
        return const ReleaseGovernanceOperatorEvaluation(
          passed: false,
          typeError: true,
          message: 'Unsupported value kind for equality',
        );
    }
  }

  ReleaseGovernanceOperatorEvaluation _compareNumeric(
    ReleaseGovernanceRuleValue? actual,
    ReleaseGovernanceRuleValue? expected,
    bool Function(double actual, double expected) compare,
  ) {
    final actualNum = _asNum(actual);
    final expectedNum = _asNum(expected);
    if (actualNum == null || expectedNum == null) {
      return const ReleaseGovernanceOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Numeric operator requires numeric values',
      );
    }
    return ReleaseGovernanceOperatorEvaluation(
      passed: compare(actualNum, expectedNum),
    );
  }

  ReleaseGovernanceOperatorEvaluation _compareDuration(
    ReleaseGovernanceRuleValue? actual,
    ReleaseGovernanceRuleValue? expected,
    bool Function(int actual, int expected) compare,
  ) {
    if (actual is ReleaseGovernanceDurationValue &&
        expected is ReleaseGovernanceDurationValue) {
      return ReleaseGovernanceOperatorEvaluation(
        passed: compare(
          _durationToSeconds(actual.iso8601Duration),
          _durationToSeconds(expected.iso8601Duration),
        ),
      );
    }
    return const ReleaseGovernanceOperatorEvaluation(
      passed: false,
      typeError: true,
      message: 'Duration operator requires duration values',
    );
  }

  ReleaseGovernanceOperatorEvaluation _between(
    ReleaseGovernanceRuleValue? actual,
    ReleaseGovernanceRuleValue? expected, {
    required bool inclusive,
  }) {
    final actualNum = _asNum(actual);
    if (actualNum == null) {
      return const ReleaseGovernanceOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Range operator requires numeric actual value',
      );
    }
    if (expected is! ReleaseGovernanceRangeValue) {
      return const ReleaseGovernanceOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Range operator requires range expected value',
      );
    }
    final inside = inclusive
        ? actualNum >= expected.lower && actualNum <= expected.upper
        : actualNum > expected.lower && actualNum < expected.upper;
    return ReleaseGovernanceOperatorEvaluation(passed: inside);
  }

  ReleaseGovernanceOperatorEvaluation _contains(
    ReleaseGovernanceRuleValue? actual,
    ReleaseGovernanceRuleValue? expected, {
    required bool negate,
  }) {
    if (actual == null || expected == null) {
      return ReleaseGovernanceOperatorEvaluation(passed: negate);
    }
    var matched = false;
    if (actual is ReleaseGovernanceStringValue &&
        expected is ReleaseGovernanceStringValue) {
      matched = actual.value.contains(expected.value);
    } else if (actual is ReleaseGovernanceSetValue &&
        expected is ReleaseGovernanceStringValue) {
      matched = actual.values.contains(expected.value);
    } else {
      return const ReleaseGovernanceOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Contains operator requires string or set actual value',
      );
    }
    return ReleaseGovernanceOperatorEvaluation(
        passed: negate ? !matched : matched);
  }

  ReleaseGovernanceOperatorEvaluation _containsAny(
    ReleaseGovernanceRuleValue? actual,
    ReleaseGovernanceRuleValue? expected, {
    required bool all,
  }) {
    if (expected is! ReleaseGovernanceSetValue) {
      return const ReleaseGovernanceOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Set operator requires set expected value',
      );
    }
    final actualItems = _asStringCollection(actual);
    if (actualItems == null) {
      return const ReleaseGovernanceOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'Set operator requires set or string actual value',
      );
    }
    if (all) {
      return ReleaseGovernanceOperatorEvaluation(
        passed: expected.values.every(actualItems.contains),
      );
    }
    return ReleaseGovernanceOperatorEvaluation(
      passed: expected.values.any(actualItems.contains),
    );
  }

  ReleaseGovernanceOperatorEvaluation _inSet(
    ReleaseGovernanceRuleValue? actual,
    ReleaseGovernanceRuleValue? expected, {
    required bool negate,
  }) {
    if (expected is! ReleaseGovernanceSetValue) {
      return const ReleaseGovernanceOperatorEvaluation(
        passed: false,
        typeError: true,
        message: 'inSet operator requires set expected value',
      );
    }
    final actualText = _asComparableString(actual);
    if (actualText == null) {
      return ReleaseGovernanceOperatorEvaluation(passed: negate);
    }
    final matched = expected.values.contains(actualText);
    return ReleaseGovernanceOperatorEvaluation(
        passed: negate ? !matched : matched);
  }

  double? _asNum(ReleaseGovernanceRuleValue? value) {
    return switch (value) {
      ReleaseGovernanceIntegerValue(:final value) => value.toDouble(),
      ReleaseGovernanceDecimalValue(:final value) => value,
      ReleaseGovernancePercentageValue(:final value) => value,
      _ => null,
    };
  }

  List<String>? _asStringCollection(ReleaseGovernanceRuleValue? value) {
    if (value is ReleaseGovernanceSetValue) return value.values;
    if (value is ReleaseGovernanceStringValue) return [value.value];
    return null;
  }

  String? _asComparableString(ReleaseGovernanceRuleValue? value) {
    return switch (value) {
      ReleaseGovernanceStringValue(:final value) => value,
      ReleaseGovernanceEnumValue(:final value) => value,
      ReleaseGovernanceIntegerValue(:final value) => value.toString(),
      ReleaseGovernanceDecimalValue(:final value) => value.toString(),
      ReleaseGovernancePercentageValue(:final value) => value.toString(),
      ReleaseGovernanceBooleanValue(:final value) => value.toString(),
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

  int _durationToSeconds(String iso8601) {
    if (!iso8601.startsWith('P')) return 0;
    var seconds = 0;
    final dayMatch = RegExp(r'(\d+)D').firstMatch(iso8601);
    if (dayMatch != null) {
      seconds += int.parse(dayMatch.group(1)!) * 86400;
    }
    final hourMatch = RegExp(r'(\d+)H').firstMatch(iso8601);
    if (hourMatch != null) {
      seconds += int.parse(hourMatch.group(1)!) * 3600;
    }
    final minuteMatch = RegExp(r'(\d+)M').firstMatch(iso8601);
    if (minuteMatch != null) {
      seconds += int.parse(minuteMatch.group(1)!) * 60;
    }
    final secondMatch = RegExp(r'(\d+)S').firstMatch(iso8601);
    if (secondMatch != null) {
      seconds += int.parse(secondMatch.group(1)!);
    }
    return seconds;
  }
}
