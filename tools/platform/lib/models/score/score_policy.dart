import 'score_enums.dart';

/// Declared score scale for a policy.
class ScoreScale {
  const ScoreScale({
    this.min = 0,
    this.max = 100,
    this.precision = 2,
    this.direction = ScoreScaleDirection.higherIsPreferred,
    this.unit = 'points',
  });

  final double min;
  final double max;
  final int precision;
  final ScoreScaleDirection direction;
  final String unit;

  Map<String, dynamic> toJson() => {
        'min': min,
        'max': max,
        'precision': precision,
        'direction': direction.wireName,
        'unit': unit,
      };

  factory ScoreScale.fromJson(Map<String, dynamic> json) {
    return ScoreScale(
      min: (json['min'] as num?)?.toDouble() ?? 0,
      max: (json['max'] as num?)?.toDouble() ?? 100,
      precision: json['precision'] as int? ?? 2,
      direction: ScoreScaleDirectionX.fromWireName(
        json['direction'] as String? ?? 'higherIsPreferred',
      ),
      unit: json['unit'] as String? ?? 'points',
    );
  }
}

/// Weight for dimension or rule aggregation.
class ScoreWeight {
  const ScoreWeight({required this.value});

  final double value;

  Map<String, dynamic> toJson() => {'value': value};

  factory ScoreWeight.fromJson(Map<String, dynamic> json) {
    return ScoreWeight(value: (json['value'] as num).toDouble());
  }
}

/// Threshold band configuration.
class ScoreThresholdBoundary {
  const ScoreThresholdBoundary({
    required this.min,
    required this.max,
    required this.bandId,
  });

  final double min;
  final double max;
  final String bandId;

  Map<String, dynamic> toJson() => {
        'min': min,
        'max': max,
        'bandId': bandId,
      };

  factory ScoreThresholdBoundary.fromJson(Map<String, dynamic> json) {
    return ScoreThresholdBoundary(
      min: (json['min'] as num).toDouble(),
      max: (json['max'] as num).toDouble(),
      bandId: json['bandId'] as String,
    );
  }
}

/// Band grouping for threshold normalization.
class ScoreThresholdBand {
  const ScoreThresholdBand({
    required this.bandId,
    required this.min,
    required this.max,
    required this.score,
  });

  final String bandId;
  final double min;
  final double max;
  final double score;

  Map<String, dynamic> toJson() => {
        'bandId': bandId,
        'min': min,
        'max': max,
        'score': score,
      };

  factory ScoreThresholdBand.fromJson(Map<String, dynamic> json) {
    return ScoreThresholdBand(
      bandId: json['bandId'] as String,
      min: (json['min'] as num).toDouble(),
      max: (json['max'] as num).toDouble(),
      score: (json['score'] as num).toDouble(),
    );
  }
}

/// Normalization configuration for a rule.
class ScoreNormalization {
  const ScoreNormalization({
    required this.method,
    this.domainMin,
    this.domainMax,
    this.clamp = true,
    this.booleanTrueScore,
    this.booleanFalseScore,
    this.textMatchScores = const {},
    this.bands = const [],
  });

  final ScoreNormalizationMethod method;
  final double? domainMin;
  final double? domainMax;
  final bool clamp;
  final double? booleanTrueScore;
  final double? booleanFalseScore;
  final Map<String, double> textMatchScores;
  final List<ScoreThresholdBand> bands;

  Map<String, dynamic> toJson() => {
        'method': method.wireName,
        if (domainMin != null) 'domainMin': domainMin,
        if (domainMax != null) 'domainMax': domainMax,
        'clamp': clamp,
        if (booleanTrueScore != null) 'booleanTrueScore': booleanTrueScore,
        if (booleanFalseScore != null) 'booleanFalseScore': booleanFalseScore,
        if (textMatchScores.isNotEmpty) 'textMatchScores': textMatchScores,
        if (bands.isNotEmpty) 'bands': bands.map((b) => b.toJson()).toList(),
      };

  factory ScoreNormalization.fromJson(Map<String, dynamic> json) {
    return ScoreNormalization(
      method: ScoreNormalizationMethodX.fromWireName(json['method'] as String),
      domainMin: (json['domainMin'] as num?)?.toDouble(),
      domainMax: (json['domainMax'] as num?)?.toDouble(),
      clamp: json['clamp'] as bool? ?? true,
      booleanTrueScore: (json['booleanTrueScore'] as num?)?.toDouble(),
      booleanFalseScore: (json['booleanFalseScore'] as num?)?.toDouble(),
      textMatchScores: (json['textMatchScores'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
      bands: (json['bands'] as List<dynamic>? ?? [])
          .map((e) => ScoreThresholdBand.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Rule condition for evaluation.
class ScoreRuleCondition {
  const ScoreRuleCondition({
    required this.operator,
    this.threshold,
    this.thresholdMax,
    this.expectedText,
    this.historyChangeType,
  });

  final ScoreRuleOperator operator;
  final double? threshold;
  final double? thresholdMax;
  final String? expectedText;
  final String? historyChangeType;

  Map<String, dynamic> toJson() => {
        'operator': operator.wireName,
        if (threshold != null) 'threshold': threshold,
        if (thresholdMax != null) 'thresholdMax': thresholdMax,
        if (expectedText != null) 'expectedText': expectedText,
        if (historyChangeType != null) 'historyChangeType': historyChangeType,
      };

  factory ScoreRuleCondition.fromJson(Map<String, dynamic> json) {
    return ScoreRuleCondition(
      operator: ScoreRuleOperatorX.fromWireName(json['operator'] as String),
      threshold: (json['threshold'] as num?)?.toDouble(),
      thresholdMax: (json['thresholdMax'] as num?)?.toDouble(),
      expectedText: json['expectedText'] as String?,
      historyChangeType: json['historyChangeType'] as String?,
    );
  }
}

/// Outcome when a rule matches.
class ScoreRuleOutcome {
  const ScoreRuleOutcome({
    required this.score,
    this.explanation,
  });

  final double score;
  final String? explanation;

  Map<String, dynamic> toJson() => {
        'score': score,
        if (explanation != null) 'explanation': explanation,
      };

  factory ScoreRuleOutcome.fromJson(Map<String, dynamic> json) {
    return ScoreRuleOutcome(
      score: (json['score'] as num).toDouble(),
      explanation: json['explanation'] as String?,
    );
  }
}

/// Single typed scoring rule.
class ScoreRule {
  const ScoreRule({
    required this.ruleId,
    required this.metricId,
    required this.condition,
    required this.outcome,
    required this.normalization,
    this.weight = const ScoreWeight(value: 1),
    this.fallbackScore,
    this.description,
    this.requiresHistoryDiff = false,
    this.requiresGuardian = false,
  });

  final String ruleId;
  final String metricId;
  final ScoreRuleCondition condition;
  final ScoreRuleOutcome outcome;
  final ScoreNormalization normalization;
  final ScoreWeight weight;
  final double? fallbackScore;
  final String? description;
  final bool requiresHistoryDiff;
  final bool requiresGuardian;

  Map<String, dynamic> toJson() => {
        'ruleId': ruleId,
        'metricId': metricId,
        'condition': condition.toJson(),
        'outcome': outcome.toJson(),
        'normalization': normalization.toJson(),
        'weight': weight.toJson(),
        if (fallbackScore != null) 'fallbackScore': fallbackScore,
        if (description != null) 'description': description,
        'requiresHistoryDiff': requiresHistoryDiff,
        'requiresGuardian': requiresGuardian,
      };

  factory ScoreRule.fromJson(Map<String, dynamic> json) {
    return ScoreRule(
      ruleId: json['ruleId'] as String,
      metricId: json['metricId'] as String,
      condition: ScoreRuleCondition.fromJson(
        json['condition'] as Map<String, dynamic>,
      ),
      outcome: ScoreRuleOutcome.fromJson(
        json['outcome'] as Map<String, dynamic>,
      ),
      normalization: ScoreNormalization.fromJson(
        json['normalization'] as Map<String, dynamic>,
      ),
      weight: ScoreWeight.fromJson(
        json['weight'] as Map<String, dynamic>? ?? {'value': 1},
      ),
      fallbackScore: (json['fallbackScore'] as num?)?.toDouble(),
      description: json['description'] as String?,
      requiresHistoryDiff: json['requiresHistoryDiff'] as bool? ?? false,
      requiresGuardian: json['requiresGuardian'] as bool? ?? false,
    );
  }
}

/// Dimension policy grouping rules.
class ScoreDimensionPolicy {
  const ScoreDimensionPolicy({
    required this.dimensionId,
    required this.name,
    required this.weight,
    required this.rules,
    required this.aggregationMethod,
    this.description,
    this.missingDataPolicy,
    this.fallbackScore,
  });

  final String dimensionId;
  final String name;
  final ScoreWeight weight;
  final List<ScoreRule> rules;
  final ScoreAggregationMethod aggregationMethod;
  final String? description;
  final ScoreMissingDataPolicy? missingDataPolicy;
  final double? fallbackScore;

  Map<String, dynamic> toJson() => {
        'dimensionId': dimensionId,
        'name': name,
        'weight': weight.toJson(),
        'rules': rules.map((r) => r.toJson()).toList(),
        'aggregationMethod': aggregationMethod.wireName,
        if (description != null) 'description': description,
        if (missingDataPolicy != null)
          'missingDataPolicy': missingDataPolicy!.wireName,
        if (fallbackScore != null) 'fallbackScore': fallbackScore,
      };

  factory ScoreDimensionPolicy.fromJson(Map<String, dynamic> json) {
    return ScoreDimensionPolicy(
      dimensionId: json['dimensionId'] as String,
      name: json['name'] as String,
      weight: ScoreWeight.fromJson(json['weight'] as Map<String, dynamic>),
      rules: (json['rules'] as List<dynamic>)
          .map((e) => ScoreRule.fromJson(e as Map<String, dynamic>))
          .toList(),
      aggregationMethod: ScoreAggregationMethodX.fromWireName(
        json['aggregationMethod'] as String,
      ),
      description: json['description'] as String?,
      missingDataPolicy: json['missingDataPolicy'] == null
          ? null
          : ScoreMissingDataPolicyX.fromWireName(
              json['missingDataPolicy'] as String,
            ),
      fallbackScore: (json['fallbackScore'] as num?)?.toDouble(),
    );
  }
}

/// Policy metadata.
class ScorePolicyMetadata {
  const ScorePolicyMetadata({
    required this.experimental,
    this.author,
    this.tags = const [],
    this.extra = const {},
  });

  final bool experimental;
  final String? author;
  final List<String> tags;
  final Map<String, String> extra;

  Map<String, dynamic> toJson() => {
        'experimental': experimental,
        if (author != null) 'author': author,
        if (tags.isNotEmpty) 'tags': tags,
        if (extra.isNotEmpty) 'extra': extra,
      };

  factory ScorePolicyMetadata.fromJson(Map<String, dynamic> json) {
    return ScorePolicyMetadata(
      experimental: json['experimental'] as bool? ?? false,
      author: json['author'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      extra: (json['extra'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

/// Immutable scoring policy.
class ScorePolicy {
  const ScorePolicy({
    required this.policyId,
    required this.name,
    required this.description,
    required this.policySchemaVersion,
    required this.policyVersion,
    required this.canonicalizationVersion,
    required this.scoreScale,
    required this.dimensions,
    required this.aggregationMethod,
    required this.missingDataPolicy,
    required this.minimumEvidenceCoverage,
    this.supportedMetricVersions = const [1],
    this.tags = const [],
    this.metadata = const ScorePolicyMetadata(experimental: false),
  });

  static const int currentSchemaVersion = 1;
  static const int currentCanonicalizationVersion = 1;

  final String policyId;
  final String name;
  final String description;
  final int policySchemaVersion;
  final int policyVersion;
  final int canonicalizationVersion;
  final ScoreScale scoreScale;
  final List<ScoreDimensionPolicy> dimensions;
  final ScoreAggregationMethod aggregationMethod;
  final ScoreMissingDataPolicy missingDataPolicy;
  final double minimumEvidenceCoverage;
  final List<int> supportedMetricVersions;
  final List<String> tags;
  final ScorePolicyMetadata metadata;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'name': name,
        'description': description,
        'policySchemaVersion': policySchemaVersion,
        'policyVersion': policyVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'scoreScale': scoreScale.toJson(),
        'dimensions': dimensions.map((d) => d.toJson()).toList(),
        'aggregationMethod': aggregationMethod.wireName,
        'missingDataPolicy': missingDataPolicy.wireName,
        'minimumEvidenceCoverage': minimumEvidenceCoverage,
        'supportedMetricVersions': supportedMetricVersions,
        if (tags.isNotEmpty) 'tags': tags,
        'metadata': metadata.toJson(),
      };

  factory ScorePolicy.fromJson(Map<String, dynamic> json) {
    return ScorePolicy(
      policyId: json['policyId'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      policySchemaVersion:
          json['policySchemaVersion'] as int? ?? currentSchemaVersion,
      policyVersion: json['policyVersion'] as int? ?? 1,
      canonicalizationVersion: json['canonicalizationVersion'] as int? ??
          currentCanonicalizationVersion,
      scoreScale: ScoreScale.fromJson(
        json['scoreScale'] as Map<String, dynamic>,
      ),
      dimensions: (json['dimensions'] as List<dynamic>)
          .map((e) => ScoreDimensionPolicy.fromJson(e as Map<String, dynamic>))
          .toList(),
      aggregationMethod: ScoreAggregationMethodX.fromWireName(
        json['aggregationMethod'] as String,
      ),
      missingDataPolicy: ScoreMissingDataPolicyX.fromWireName(
        json['missingDataPolicy'] as String,
      ),
      minimumEvidenceCoverage:
          (json['minimumEvidenceCoverage'] as num?)?.toDouble() ?? 0,
      supportedMetricVersions:
          (json['supportedMetricVersions'] as List<dynamic>?)
                  ?.map((e) => e as int)
                  .toList() ??
              const [1],
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      metadata: ScorePolicyMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toComparableJson() {
    final json = toJson();
    final dims = (json['dimensions'] as List<dynamic>)
      ..sort((a, b) => (a as Map)['dimensionId']
          .toString()
          .compareTo((b as Map)['dimensionId'].toString()));
    json['dimensions'] = dims;
    return json;
  }
}

/// Policy validation result.
class ScorePolicyValidationResult {
  const ScorePolicyValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
  });

  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
}
