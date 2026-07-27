import 'score_enums.dart';

/// Numeric score value with scale context.
class ScoreValue {
  const ScoreValue({
    required this.value,
    required this.scaleMin,
    required this.scaleMax,
    this.bandId,
  });

  final double value;
  final double scaleMin;
  final double scaleMax;
  final String? bandId;

  Map<String, dynamic> toJson() => {
        'value': value,
        'scaleMin': scaleMin,
        'scaleMax': scaleMax,
        if (bandId != null) 'bandId': bandId,
      };

  factory ScoreValue.fromJson(Map<String, dynamic> json) {
    return ScoreValue(
      value: (json['value'] as num).toDouble(),
      scaleMin: (json['scaleMin'] as num?)?.toDouble() ?? 0,
      scaleMax: (json['scaleMax'] as num?)?.toDouble() ?? 100,
      bandId: json['bandId'] as String?,
    );
  }
}

/// Classification band applied to a score.
class ScoreBand {
  const ScoreBand({
    required this.bandId,
    required this.min,
    required this.max,
  });

  final String bandId;
  final double min;
  final double max;

  Map<String, dynamic> toJson() => {
        'bandId': bandId,
        'min': min,
        'max': max,
      };

  factory ScoreBand.fromJson(Map<String, dynamic> json) {
    return ScoreBand(
      bandId: json['bandId'] as String,
      min: (json['min'] as num).toDouble(),
      max: (json['max'] as num).toDouble(),
    );
  }
}

/// Evidence used for scoring.
class ScoreEvidence {
  const ScoreEvidence({
    required this.evidenceId,
    required this.sourceType,
    required this.metricId,
    this.observedValue,
    this.observedText,
    this.availability = ScoreAvailability.available,
    this.unit,
    this.calculationVersion,
    this.message,
  });

  final String evidenceId;
  final String sourceType;
  final String metricId;
  final double? observedValue;
  final String? observedText;
  final ScoreAvailability availability;
  final String? unit;
  final int? calculationVersion;
  final String? message;

  Map<String, dynamic> toJson() => {
        'evidenceId': evidenceId,
        'sourceType': sourceType,
        'metricId': metricId,
        if (observedValue != null) 'observedValue': observedValue,
        if (observedText != null) 'observedText': observedText,
        'availability': availability.wireName,
        if (unit != null) 'unit': unit,
        if (calculationVersion != null)
          'calculationVersion': calculationVersion,
        if (message != null) 'message': message,
      };

  factory ScoreEvidence.fromJson(Map<String, dynamic> json) {
    return ScoreEvidence(
      evidenceId: json['evidenceId'] as String,
      sourceType: json['sourceType'] as String,
      metricId: json['metricId'] as String,
      observedValue: (json['observedValue'] as num?)?.toDouble(),
      observedText: json['observedText'] as String?,
      availability: ScoreAvailabilityX.fromWireName(
        json['availability'] as String? ?? 'available',
      ),
      unit: json['unit'] as String?,
      calculationVersion: json['calculationVersion'] as int?,
      message: json['message'] as String?,
    );
  }
}

/// Weighted contribution to a dimension or overall score.
class ScoreContribution {
  const ScoreContribution({
    required this.subjectId,
    required this.weight,
    required this.score,
    required this.weightedContribution,
  });

  final String subjectId;
  final double weight;
  final double score;
  final double weightedContribution;

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'weight': weight,
        'score': score,
        'weightedContribution': weightedContribution,
      };

  factory ScoreContribution.fromJson(Map<String, dynamic> json) {
    return ScoreContribution(
      subjectId: json['subjectId'] as String,
      weight: (json['weight'] as num).toDouble(),
      score: (json['score'] as num).toDouble(),
      weightedContribution: (json['weightedContribution'] as num).toDouble(),
    );
  }
}

/// Result of evaluating a single rule.
class ScoreRuleResult {
  const ScoreRuleResult({
    required this.ruleId,
    required this.metricId,
    required this.availability,
    required this.matched,
    this.rawScore,
    this.normalizedScore,
    this.contribution,
    this.evidence,
    this.explanation,
    this.warnings = const [],
  });

  final String ruleId;
  final String metricId;
  final ScoreAvailability availability;
  final bool matched;
  final double? rawScore;
  final double? normalizedScore;
  final double? contribution;
  final ScoreEvidence? evidence;
  final String? explanation;
  final List<String> warnings;

  Map<String, dynamic> toJson() => {
        'ruleId': ruleId,
        'metricId': metricId,
        'availability': availability.wireName,
        'matched': matched,
        if (rawScore != null) 'rawScore': rawScore,
        if (normalizedScore != null) 'normalizedScore': normalizedScore,
        if (contribution != null) 'contribution': contribution,
        if (evidence != null) 'evidence': evidence!.toJson(),
        if (explanation != null) 'explanation': explanation,
        if (warnings.isNotEmpty) 'warnings': warnings,
      };

  factory ScoreRuleResult.fromJson(Map<String, dynamic> json) {
    return ScoreRuleResult(
      ruleId: json['ruleId'] as String,
      metricId: json['metricId'] as String,
      availability: ScoreAvailabilityX.fromWireName(
        json['availability'] as String,
      ),
      matched: json['matched'] as bool? ?? false,
      rawScore: (json['rawScore'] as num?)?.toDouble(),
      normalizedScore: (json['normalizedScore'] as num?)?.toDouble(),
      contribution: (json['contribution'] as num?)?.toDouble(),
      evidence: json['evidence'] == null
          ? null
          : ScoreEvidence.fromJson(json['evidence'] as Map<String, dynamic>),
      explanation: json['explanation'] as String?,
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Coverage statistics for score calculation.
class ScoreCoverage {
  const ScoreCoverage({
    required this.requestedEvidenceCount,
    required this.availableEvidenceCount,
    required this.unavailableEvidenceCount,
    required this.usedEvidenceCount,
    required this.coveragePercentage,
    required this.totalConfiguredWeight,
    required this.appliedWeight,
    required this.excludedWeight,
    this.missingMetricIds = const [],
  });

  final int requestedEvidenceCount;
  final int availableEvidenceCount;
  final int unavailableEvidenceCount;
  final int usedEvidenceCount;
  final double coveragePercentage;
  final double totalConfiguredWeight;
  final double appliedWeight;
  final double excludedWeight;
  final List<String> missingMetricIds;

  Map<String, dynamic> toJson() => {
        'requestedEvidenceCount': requestedEvidenceCount,
        'availableEvidenceCount': availableEvidenceCount,
        'unavailableEvidenceCount': unavailableEvidenceCount,
        'usedEvidenceCount': usedEvidenceCount,
        'coveragePercentage': coveragePercentage,
        'totalConfiguredWeight': totalConfiguredWeight,
        'appliedWeight': appliedWeight,
        'excludedWeight': excludedWeight,
        if (missingMetricIds.isNotEmpty) 'missingMetricIds': missingMetricIds,
      };

  factory ScoreCoverage.fromJson(Map<String, dynamic> json) {
    return ScoreCoverage(
      requestedEvidenceCount: json['requestedEvidenceCount'] as int? ?? 0,
      availableEvidenceCount: json['availableEvidenceCount'] as int? ?? 0,
      unavailableEvidenceCount: json['unavailableEvidenceCount'] as int? ?? 0,
      usedEvidenceCount: json['usedEvidenceCount'] as int? ?? 0,
      coveragePercentage: (json['coveragePercentage'] as num?)?.toDouble() ?? 0,
      totalConfiguredWeight:
          (json['totalConfiguredWeight'] as num?)?.toDouble() ?? 0,
      appliedWeight: (json['appliedWeight'] as num?)?.toDouble() ?? 0,
      excludedWeight: (json['excludedWeight'] as num?)?.toDouble() ?? 0,
      missingMetricIds: (json['missingMetricIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Result for a single dimension.
class ScoreDimensionResult {
  const ScoreDimensionResult({
    required this.dimensionId,
    required this.name,
    required this.availability,
    required this.weight,
    required this.rules,
    required this.coverage,
    this.rawScore,
    this.normalizedScore,
    this.weightedContribution,
    this.band,
    this.warnings = const [],
    this.contributions = const [],
  });

  final String dimensionId;
  final String name;
  final ScoreAvailability availability;
  final double weight;
  final List<ScoreRuleResult> rules;
  final ScoreCoverage coverage;
  final double? rawScore;
  final double? normalizedScore;
  final double? weightedContribution;
  final ScoreBand? band;
  final List<String> warnings;
  final List<ScoreContribution> contributions;

  Map<String, dynamic> toJson() => {
        'dimensionId': dimensionId,
        'name': name,
        'availability': availability.wireName,
        'weight': weight,
        'rules': rules.map((r) => r.toJson()).toList(),
        'coverage': coverage.toJson(),
        if (rawScore != null) 'rawScore': rawScore,
        if (normalizedScore != null) 'normalizedScore': normalizedScore,
        if (weightedContribution != null)
          'weightedContribution': weightedContribution,
        if (band != null) 'band': band!.toJson(),
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (contributions.isNotEmpty)
          'contributions': contributions.map((c) => c.toJson()).toList(),
      };

  factory ScoreDimensionResult.fromJson(Map<String, dynamic> json) {
    return ScoreDimensionResult(
      dimensionId: json['dimensionId'] as String,
      name: json['name'] as String,
      availability: ScoreAvailabilityX.fromWireName(
        json['availability'] as String,
      ),
      weight: (json['weight'] as num).toDouble(),
      rules: (json['rules'] as List<dynamic>)
          .map((e) => ScoreRuleResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      coverage: ScoreCoverage.fromJson(
        json['coverage'] as Map<String, dynamic>,
      ),
      rawScore: (json['rawScore'] as num?)?.toDouble(),
      normalizedScore: (json['normalizedScore'] as num?)?.toDouble(),
      weightedContribution: (json['weightedContribution'] as num?)?.toDouble(),
      band: json['band'] == null
          ? null
          : ScoreBand.fromJson(json['band'] as Map<String, dynamic>),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      contributions: (json['contributions'] as List<dynamic>? ?? [])
          .map((e) => ScoreContribution.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Structured explanation for a score snapshot.
class ScoreExplanation {
  const ScoreExplanation({
    required this.summary,
    required this.policySummary,
    required this.dimensionSummaries,
    required this.limitations,
    this.aggregationFormula,
    this.trace = const [],
  });

  final String summary;
  final String policySummary;
  final List<String> dimensionSummaries;
  final List<String> limitations;
  final String? aggregationFormula;
  final List<String> trace;

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'policySummary': policySummary,
        'dimensionSummaries': dimensionSummaries,
        'limitations': limitations,
        if (aggregationFormula != null)
          'aggregationFormula': aggregationFormula,
        if (trace.isNotEmpty) 'trace': trace,
      };

  factory ScoreExplanation.fromJson(Map<String, dynamic> json) {
    return ScoreExplanation(
      summary: json['summary'] as String,
      policySummary: json['policySummary'] as String,
      dimensionSummaries: (json['dimensionSummaries'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      limitations: (json['limitations'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      aggregationFormula: json['aggregationFormula'] as String?,
      trace: (json['trace'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Snapshot metadata.
class ScoreMetadata {
  const ScoreMetadata({
    required this.scoreSnapshotId,
    required this.scoreSchemaVersion,
    required this.scoreCalculationVersion,
    required this.scoreCanonicalizationVersion,
    required this.projectId,
    required this.policyId,
    required this.policyVersion,
    required this.sourceMetricsSnapshotId,
    required this.createdAt,
    required this.scoreFingerprint,
    required this.status,
    required this.confidence,
    required this.compatibilityStatus,
    required this.dimensionCount,
    required this.ruleCount,
    required this.warningCount,
    required this.errorCount,
    this.sourceHistorySnapshotId,
    this.sourceHistoryDiffId,
    this.gitRef,
    this.branch,
    this.sourceEventId,
    this.tags = const [],
    this.extra = const {},
  });

  static const int currentSchemaVersion = 1;
  static const int currentCalculationVersion = 1;
  static const int currentCanonicalizationVersion = 1;
  static const String fingerprintAlgorithm = 'sha256';

  final String scoreSnapshotId;
  final int scoreSchemaVersion;
  final int scoreCalculationVersion;
  final int scoreCanonicalizationVersion;
  final String projectId;
  final String policyId;
  final int policyVersion;
  final String sourceMetricsSnapshotId;
  final String createdAt;
  final String scoreFingerprint;
  final ScoreStatus status;
  final ScoreConfidence confidence;
  final ScoreCompatibilityStatus compatibilityStatus;
  final int dimensionCount;
  final int ruleCount;
  final int warningCount;
  final int errorCount;
  final String? sourceHistorySnapshotId;
  final String? sourceHistoryDiffId;
  final String? gitRef;
  final String? branch;
  final String? sourceEventId;
  final List<String> tags;
  final Map<String, String> extra;

  Map<String, dynamic> toJson() => {
        'scoreSnapshotId': scoreSnapshotId,
        'scoreSchemaVersion': scoreSchemaVersion,
        'scoreCalculationVersion': scoreCalculationVersion,
        'scoreCanonicalizationVersion': scoreCanonicalizationVersion,
        'fingerprintAlgorithm': fingerprintAlgorithm,
        'projectId': projectId,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'sourceMetricsSnapshotId': sourceMetricsSnapshotId,
        'createdAt': createdAt,
        'scoreFingerprint': scoreFingerprint,
        'status': status.wireName,
        'confidence': confidence.wireName,
        'compatibilityStatus': compatibilityStatus.wireName,
        'dimensionCount': dimensionCount,
        'ruleCount': ruleCount,
        'warningCount': warningCount,
        'errorCount': errorCount,
        if (sourceHistorySnapshotId != null)
          'sourceHistorySnapshotId': sourceHistorySnapshotId,
        if (sourceHistoryDiffId != null)
          'sourceHistoryDiffId': sourceHistoryDiffId,
        if (gitRef != null) 'gitRef': gitRef,
        if (branch != null) 'branch': branch,
        if (sourceEventId != null) 'sourceEventId': sourceEventId,
        if (tags.isNotEmpty) 'tags': tags,
        if (extra.isNotEmpty) 'extra': extra,
      };

  factory ScoreMetadata.fromJson(Map<String, dynamic> json) {
    return ScoreMetadata(
      scoreSnapshotId: json['scoreSnapshotId'] as String,
      scoreSchemaVersion:
          json['scoreSchemaVersion'] as int? ?? currentSchemaVersion,
      scoreCalculationVersion:
          json['scoreCalculationVersion'] as int? ?? currentCalculationVersion,
      scoreCanonicalizationVersion:
          json['scoreCanonicalizationVersion'] as int? ??
              currentCanonicalizationVersion,
      projectId: json['projectId'] as String,
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int? ?? 1,
      sourceMetricsSnapshotId: json['sourceMetricsSnapshotId'] as String,
      createdAt: json['createdAt'] as String,
      scoreFingerprint: json['scoreFingerprint'] as String,
      status: ScoreStatusX.fromWireName(json['status'] as String),
      confidence: ScoreConfidenceX.fromWireName(json['confidence'] as String),
      compatibilityStatus: ScoreCompatibilityStatusX.fromWireName(
        json['compatibilityStatus'] as String,
      ),
      dimensionCount: json['dimensionCount'] as int? ?? 0,
      ruleCount: json['ruleCount'] as int? ?? 0,
      warningCount: json['warningCount'] as int? ?? 0,
      errorCount: json['errorCount'] as int? ?? 0,
      sourceHistorySnapshotId: json['sourceHistorySnapshotId'] as String?,
      sourceHistoryDiffId: json['sourceHistoryDiffId'] as String?,
      gitRef: json['gitRef'] as String?,
      branch: json['branch'] as String?,
      sourceEventId: json['sourceEventId'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      extra: (json['extra'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }

  Map<String, dynamic> toComparableJson() {
    final json = toJson();
    json.remove('createdAt');
    return json;
  }

  ScoreMetadata copyWith({
    String? scoreSnapshotId,
    String? scoreFingerprint,
    ScoreStatus? status,
    ScoreConfidence? confidence,
    int? warningCount,
    int? errorCount,
  }) {
    return ScoreMetadata(
      scoreSnapshotId: scoreSnapshotId ?? this.scoreSnapshotId,
      scoreSchemaVersion: scoreSchemaVersion,
      scoreCalculationVersion: scoreCalculationVersion,
      scoreCanonicalizationVersion: scoreCanonicalizationVersion,
      projectId: projectId,
      policyId: policyId,
      policyVersion: policyVersion,
      sourceMetricsSnapshotId: sourceMetricsSnapshotId,
      createdAt: createdAt,
      scoreFingerprint: scoreFingerprint ?? this.scoreFingerprint,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
      compatibilityStatus: compatibilityStatus,
      dimensionCount: dimensionCount,
      ruleCount: ruleCount,
      warningCount: warningCount ?? this.warningCount,
      errorCount: errorCount ?? this.errorCount,
      sourceHistorySnapshotId: sourceHistorySnapshotId,
      sourceHistoryDiffId: sourceHistoryDiffId,
      gitRef: gitRef,
      branch: branch,
      sourceEventId: sourceEventId,
      tags: tags,
      extra: extra,
    );
  }
}

/// Immutable engineering score snapshot.
class EngineeringScoreSnapshot {
  const EngineeringScoreSnapshot({
    required this.metadata,
    required this.overallScore,
    required this.dimensions,
    required this.coverage,
    required this.explanation,
    this.warnings = const [],
    this.errors = const [],
  });

  final ScoreMetadata metadata;
  final ScoreValue overallScore;
  final List<ScoreDimensionResult> dimensions;
  final ScoreCoverage coverage;
  final ScoreExplanation explanation;
  final List<ScoreWarning> warnings;
  final List<ScoreError> errors;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'overallScore': overallScore.toJson(),
        'dimensions': dimensions.map((d) => d.toJson()).toList(),
        'coverage': coverage.toJson(),
        'explanation': explanation.toJson(),
        if (warnings.isNotEmpty)
          'warnings': warnings.map((w) => w.toJson()).toList(),
        if (errors.isNotEmpty) 'errors': errors.map((e) => e.toJson()).toList(),
      };

  factory EngineeringScoreSnapshot.fromJson(Map<String, dynamic> json) {
    return EngineeringScoreSnapshot(
      metadata: ScoreMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      overallScore: ScoreValue.fromJson(
        json['overallScore'] as Map<String, dynamic>,
      ),
      dimensions: (json['dimensions'] as List<dynamic>)
          .map((e) => ScoreDimensionResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      coverage: ScoreCoverage.fromJson(
        json['coverage'] as Map<String, dynamic>,
      ),
      explanation: ScoreExplanation.fromJson(
        json['explanation'] as Map<String, dynamic>,
      ),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((e) => ScoreWarning.fromJson(e as Map<String, dynamic>))
          .toList(),
      errors: (json['errors'] as List<dynamic>? ?? [])
          .map((e) => ScoreError.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'metadata': metadata.toComparableJson(),
        'overallScore': overallScore.toJson(),
        'dimensions': dimensions.map((d) => d.toJson()).toList(),
        'coverage': coverage.toJson(),
        'explanation': explanation.toJson(),
      };
}

/// Score warning.
class ScoreWarning {
  const ScoreWarning({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, dynamic> toJson() => {'code': code, 'message': message};

  factory ScoreWarning.fromJson(Map<String, dynamic> json) {
    return ScoreWarning(
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }
}

/// Score error.
class ScoreError {
  const ScoreError({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, dynamic> toJson() => {'code': code, 'message': message};

  factory ScoreError.fromJson(Map<String, dynamic> json) {
    return ScoreError(
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }
}

/// Snapshot validation result.
class ScoreValidationResult {
  const ScoreValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
  });

  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
}
