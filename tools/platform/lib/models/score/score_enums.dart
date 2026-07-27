/// Score scale direction semantics.
enum ScoreScaleDirection {
  higherIsPreferred,
  lowerIsPreferred,
  neutral,
}

extension ScoreScaleDirectionX on ScoreScaleDirection {
  String get wireName => name;

  static ScoreScaleDirection fromWireName(String value) {
    return ScoreScaleDirection.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ScoreScaleDirection: $value'),
    );
  }
}

/// Typed rule operators.
enum ScoreRuleOperator {
  equals,
  notEquals,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  betweenInclusive,
  betweenExclusive,
  exists,
  unavailable,
  changed,
  increased,
  decreased,
}

extension ScoreRuleOperatorX on ScoreRuleOperator {
  String get wireName => name;

  static ScoreRuleOperator fromWireName(String value) {
    return ScoreRuleOperator.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown ScoreRuleOperator: $value'),
    );
  }
}

/// Normalization methods.
enum ScoreNormalizationMethod {
  direct,
  inverse,
  linearRange,
  cappedLinear,
  booleanMapping,
  thresholdBands,
}

extension ScoreNormalizationMethodX on ScoreNormalizationMethod {
  String get wireName => name;

  static ScoreNormalizationMethod fromWireName(String value) {
    return ScoreNormalizationMethod.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ScoreNormalizationMethod: $value'),
    );
  }
}

/// Aggregation methods.
enum ScoreAggregationMethod {
  weightedAverage,
  arithmeticMean,
  minimum,
  maximum,
}

extension ScoreAggregationMethodX on ScoreAggregationMethod {
  String get wireName => name;

  static ScoreAggregationMethod fromWireName(String value) {
    return ScoreAggregationMethod.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ScoreAggregationMethod: $value'),
    );
  }
}

/// Missing data handling policy.
enum ScoreMissingDataPolicy {
  fail,
  markUnavailable,
  excludeAndReweight,
  useNeutralValue,
  useConfiguredFallback,
}

extension ScoreMissingDataPolicyX on ScoreMissingDataPolicy {
  String get wireName => name;

  static ScoreMissingDataPolicy fromWireName(String value) {
    return ScoreMissingDataPolicy.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ScoreMissingDataPolicy: $value'),
    );
  }
}

/// Score calculation result status.
enum ScoreStatus {
  success,
  partial,
  unavailable,
  failure,
}

extension ScoreStatusX on ScoreStatus {
  String get wireName => name;

  static ScoreStatus fromWireName(String value) {
    return ScoreStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown ScoreStatus: $value'),
    );
  }
}

/// Availability of score evidence or dimension.
enum ScoreAvailability {
  available,
  unavailable,
  partial,
  incompatible,
}

extension ScoreAvailabilityX on ScoreAvailability {
  String get wireName => name;

  static ScoreAvailability fromWireName(String value) {
    return ScoreAvailability.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown ScoreAvailability: $value'),
    );
  }
}

/// Confidence derived from coverage and compatibility.
enum ScoreConfidence {
  full,
  partial,
  insufficient,
  incompatible,
  unknown,
}

extension ScoreConfidenceX on ScoreConfidence {
  String get wireName => name;

  static ScoreConfidence fromWireName(String value) {
    return ScoreConfidence.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown ScoreConfidence: $value'),
    );
  }
}

/// Compatibility between policy and input evidence.
enum ScoreCompatibilityStatus {
  compatible,
  partiallyCompatible,
  incompatible,
  unknown,
}

extension ScoreCompatibilityStatusX on ScoreCompatibilityStatus {
  String get wireName => name;

  static ScoreCompatibilityStatus fromWireName(String value) {
    return ScoreCompatibilityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ScoreCompatibilityStatus: $value'),
    );
  }
}
