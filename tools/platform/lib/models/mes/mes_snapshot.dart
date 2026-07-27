import 'mes_enums.dart';
import 'mes_policy.dart';

/// Official MES score value on the configured scale.
class MESValue {
  const MESValue({
    required this.value,
    required this.min,
    required this.max,
    required this.precision,
    required this.unit,
  });

  final double value;
  final double min;
  final double max;
  final int precision;
  final String unit;

  Map<String, dynamic> toJson() => {
        'value': value,
        'min': min,
        'max': max,
        'precision': precision,
        'unit': unit,
      };

  factory MESValue.fromJson(Map<String, dynamic> json) {
    return MESValue(
      value: (json['value'] as num).toDouble(),
      min: (json['min'] as num?)?.toDouble() ?? 0,
      max: (json['max'] as num?)?.toDouble() ?? 100,
      precision: json['precision'] as int? ?? 2,
      unit: json['unit'] as String? ?? 'points',
    );
  }
}

/// Hierarchical MES coverage metrics.
class MESCoverage {
  const MESCoverage({
    required this.ruleCoverage,
    required this.dimensionCoverage,
    required this.policyCoverage,
    required this.evidenceCoverage,
    required this.requiredDimensionCoverage,
    required this.optionalDimensionCoverage,
    required this.missingRequiredMetricIds,
    required this.missingOptionalMetricIds,
    required this.totalPolicyWeight,
    required this.appliedPolicyWeight,
    required this.excludedPolicyWeight,
    this.requestedRuleCount = 0,
    this.availableRuleCount = 0,
    this.usedRuleCount = 0,
  });

  final double ruleCoverage;
  final double dimensionCoverage;
  final double policyCoverage;
  final double evidenceCoverage;
  final double requiredDimensionCoverage;
  final double optionalDimensionCoverage;
  final List<String> missingRequiredMetricIds;
  final List<String> missingOptionalMetricIds;
  final double totalPolicyWeight;
  final double appliedPolicyWeight;
  final double excludedPolicyWeight;
  final int requestedRuleCount;
  final int availableRuleCount;
  final int usedRuleCount;

  Map<String, dynamic> toJson() => {
        'ruleCoverage': ruleCoverage,
        'dimensionCoverage': dimensionCoverage,
        'policyCoverage': policyCoverage,
        'evidenceCoverage': evidenceCoverage,
        'requiredDimensionCoverage': requiredDimensionCoverage,
        'optionalDimensionCoverage': optionalDimensionCoverage,
        'missingRequiredMetricIds': missingRequiredMetricIds,
        'missingOptionalMetricIds': missingOptionalMetricIds,
        'totalPolicyWeight': totalPolicyWeight,
        'appliedPolicyWeight': appliedPolicyWeight,
        'excludedPolicyWeight': excludedPolicyWeight,
        'requestedRuleCount': requestedRuleCount,
        'availableRuleCount': availableRuleCount,
        'usedRuleCount': usedRuleCount,
      };

  factory MESCoverage.fromJson(Map<String, dynamic> json) {
    return MESCoverage(
      ruleCoverage: (json['ruleCoverage'] as num).toDouble(),
      dimensionCoverage: (json['dimensionCoverage'] as num).toDouble(),
      policyCoverage: (json['policyCoverage'] as num).toDouble(),
      evidenceCoverage: (json['evidenceCoverage'] as num).toDouble(),
      requiredDimensionCoverage:
          (json['requiredDimensionCoverage'] as num).toDouble(),
      optionalDimensionCoverage:
          (json['optionalDimensionCoverage'] as num).toDouble(),
      missingRequiredMetricIds:
          (json['missingRequiredMetricIds'] as List<dynamic>)
              .map((e) => e.toString())
              .toList(),
      missingOptionalMetricIds:
          (json['missingOptionalMetricIds'] as List<dynamic>)
              .map((e) => e.toString())
              .toList(),
      totalPolicyWeight: (json['totalPolicyWeight'] as num).toDouble(),
      appliedPolicyWeight: (json['appliedPolicyWeight'] as num).toDouble(),
      excludedPolicyWeight: (json['excludedPolicyWeight'] as num).toDouble(),
      requestedRuleCount: json['requestedRuleCount'] as int? ?? 0,
      availableRuleCount: json['availableRuleCount'] as int? ?? 0,
      usedRuleCount: json['usedRuleCount'] as int? ?? 0,
    );
  }
}

/// Evidence summary for a single metric in MES context.
class MESEvidenceSummary {
  const MESEvidenceSummary({
    required this.metricId,
    required this.tier,
    required this.available,
    this.observedValue,
    this.limitation,
  });

  final String metricId;
  final MESEvidenceTier tier;
  final bool available;
  final dynamic observedValue;
  final String? limitation;

  Map<String, dynamic> toJson() => {
        'metricId': metricId,
        'tier': tier.wireName,
        'available': available,
        if (observedValue != null) 'observedValue': observedValue,
        if (limitation != null) 'limitation': limitation,
      };

  factory MESEvidenceSummary.fromJson(Map<String, dynamic> json) {
    return MESEvidenceSummary(
      metricId: json['metricId'] as String,
      tier: MESEvidenceTierX.fromWireName(json['tier'] as String),
      available: json['available'] as bool,
      observedValue: json['observedValue'],
      limitation: json['limitation'] as String?,
    );
  }
}

/// Result for a single MES dimension.
class MESDimensionResult {
  const MESDimensionResult({
    required this.dimensionId,
    required this.name,
    required this.required,
    required this.weightPercent,
    required this.available,
    this.normalizedScore,
    this.weightedContribution,
    this.ruleCoverage,
    this.evidenceTier,
    this.limitations = const [],
    this.missingMetricIds = const [],
  });

  final String dimensionId;
  final String name;
  final bool required;
  final double weightPercent;
  final bool available;
  final double? normalizedScore;
  final double? weightedContribution;
  final double? ruleCoverage;
  final MESEvidenceTier? evidenceTier;
  final List<String> limitations;
  final List<String> missingMetricIds;

  Map<String, dynamic> toJson() => {
        'dimensionId': dimensionId,
        'name': name,
        'required': required,
        'weightPercent': weightPercent,
        'available': available,
        if (normalizedScore != null) 'normalizedScore': normalizedScore,
        if (weightedContribution != null)
          'weightedContribution': weightedContribution,
        if (ruleCoverage != null) 'ruleCoverage': ruleCoverage,
        if (evidenceTier != null) 'evidenceTier': evidenceTier!.wireName,
        if (limitations.isNotEmpty) 'limitations': limitations,
        if (missingMetricIds.isNotEmpty) 'missingMetricIds': missingMetricIds,
      };

  factory MESDimensionResult.fromJson(Map<String, dynamic> json) {
    return MESDimensionResult(
      dimensionId: json['dimensionId'] as String,
      name: json['name'] as String,
      required: json['required'] as bool,
      weightPercent: (json['weightPercent'] as num).toDouble(),
      available: json['available'] as bool,
      normalizedScore: (json['normalizedScore'] as num?)?.toDouble(),
      weightedContribution: (json['weightedContribution'] as num?)?.toDouble(),
      ruleCoverage: (json['ruleCoverage'] as num?)?.toDouble(),
      evidenceTier: json['evidenceTier'] == null
          ? null
          : MESEvidenceTierX.fromWireName(json['evidenceTier'] as String),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      missingMetricIds: (json['missingMetricIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Eligibility evaluation result.
class MESEligibility {
  const MESEligibility({
    required this.status,
    required this.reasons,
    required this.missingRequiredDimensions,
    required this.missingOptionalDimensions,
  });

  final MESEligibilityStatus status;
  final List<String> reasons;
  final List<String> missingRequiredDimensions;
  final List<String> missingOptionalDimensions;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'reasons': reasons,
        'missingRequiredDimensions': missingRequiredDimensions,
        'missingOptionalDimensions': missingOptionalDimensions,
      };

  factory MESEligibility.fromJson(Map<String, dynamic> json) {
    return MESEligibility(
      status: MESEligibilityStatusX.fromWireName(json['status'] as String),
      reasons:
          (json['reasons'] as List<dynamic>).map((e) => e.toString()).toList(),
      missingRequiredDimensions:
          (json['missingRequiredDimensions'] as List<dynamic>)
              .map((e) => e.toString())
              .toList(),
      missingOptionalDimensions:
          (json['missingOptionalDimensions'] as List<dynamic>)
              .map((e) => e.toString())
              .toList(),
    );
  }
}

/// Structured limitation on MES interpretation.
class MESLimitation {
  const MESLimitation({
    required this.code,
    required this.message,
    this.metricId,
    this.dimensionId,
  });

  final String code;
  final String message;
  final String? metricId;
  final String? dimensionId;

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (metricId != null) 'metricId': metricId,
        if (dimensionId != null) 'dimensionId': dimensionId,
      };

  factory MESLimitation.fromJson(Map<String, dynamic> json) {
    return MESLimitation(
      code: json['code'] as String,
      message: json['message'] as String,
      metricId: json['metricId'] as String?,
      dimensionId: json['dimensionId'] as String?,
    );
  }
}

/// Structured MES explanation.
class MESExplanation {
  const MESExplanation({
    required this.summary,
    required this.policySummary,
    required this.eligibilitySummary,
    required this.coverageSummary,
    required this.confidenceSummary,
    required this.dimensionSummaries,
    required this.weightAdjustments,
    this.calculationReference,
  });

  final String summary;
  final String policySummary;
  final String eligibilitySummary;
  final String coverageSummary;
  final String confidenceSummary;
  final List<String> dimensionSummaries;
  final List<String> weightAdjustments;
  final MESCalculationReference? calculationReference;

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'policySummary': policySummary,
        'eligibilitySummary': eligibilitySummary,
        'coverageSummary': coverageSummary,
        'confidenceSummary': confidenceSummary,
        'dimensionSummaries': dimensionSummaries,
        'weightAdjustments': weightAdjustments,
        if (calculationReference != null)
          'calculationReference': calculationReference!.toJson(),
      };

  factory MESExplanation.fromJson(Map<String, dynamic> json) {
    return MESExplanation(
      summary: json['summary'] as String,
      policySummary: json['policySummary'] as String,
      eligibilitySummary: json['eligibilitySummary'] as String,
      coverageSummary: json['coverageSummary'] as String,
      confidenceSummary: json['confidenceSummary'] as String,
      dimensionSummaries: (json['dimensionSummaries'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      weightAdjustments: (json['weightAdjustments'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      calculationReference: json['calculationReference'] == null
          ? null
          : MESCalculationReference.fromJson(
              json['calculationReference'] as Map<String, dynamic>,
            ),
    );
  }
}

/// Reference to underlying Score Engine calculation.
class MESCalculationReference {
  const MESCalculationReference({
    required this.sourceEngineeringScoreSnapshotId,
    required this.scoreFingerprint,
    required this.policyFingerprint,
    this.traceIncluded = false,
  });

  final String sourceEngineeringScoreSnapshotId;
  final String scoreFingerprint;
  final String policyFingerprint;
  final bool traceIncluded;

  Map<String, dynamic> toJson() => {
        'sourceEngineeringScoreSnapshotId': sourceEngineeringScoreSnapshotId,
        'scoreFingerprint': scoreFingerprint,
        'policyFingerprint': policyFingerprint,
        'traceIncluded': traceIncluded,
      };

  factory MESCalculationReference.fromJson(Map<String, dynamic> json) {
    return MESCalculationReference(
      sourceEngineeringScoreSnapshotId:
          json['sourceEngineeringScoreSnapshotId'] as String,
      scoreFingerprint: json['scoreFingerprint'] as String,
      policyFingerprint: json['policyFingerprint'] as String,
      traceIncluded: json['traceIncluded'] as bool? ?? false,
    );
  }
}

/// MES metadata with identity and versioning.
class MESMetadata {
  const MESMetadata({
    required this.mesSnapshotId,
    required this.mesSchemaVersion,
    required this.mesCalculationVersion,
    required this.mesCanonicalizationVersion,
    required this.projectId,
    required this.policyId,
    required this.policyVersion,
    required this.policyStatus,
    required this.sourceMetricsSnapshotId,
    required this.sourceEngineeringScoreSnapshotId,
    required this.createdAt,
    required this.mesFingerprint,
    required this.status,
    required this.confidence,
    required this.compatibilityStatus,
    required this.dimensionCount,
    required this.availableDimensionCount,
    required this.unavailableDimensionCount,
    required this.warningCount,
    required this.errorCount,
    this.sourceHistorySnapshotId,
    this.sourceHistoryDiffId,
    this.gitRef,
    this.branch,
    this.policyFingerprint,
    this.bandId,
  });

  static const int currentSchemaVersion = 1;
  static const int currentCalculationVersion = 1;
  static const int currentCanonicalizationVersion = 1;

  final String mesSnapshotId;
  final int mesSchemaVersion;
  final int mesCalculationVersion;
  final int mesCanonicalizationVersion;
  final String projectId;
  final String policyId;
  final int policyVersion;
  final MESPolicyStatus policyStatus;
  final String sourceMetricsSnapshotId;
  final String sourceEngineeringScoreSnapshotId;
  final String? sourceHistorySnapshotId;
  final String? sourceHistoryDiffId;
  final String createdAt;
  final String? gitRef;
  final String? branch;
  final String mesFingerprint;
  final String? policyFingerprint;
  final MESStatus status;
  final MESConfidence confidence;
  final MESCompatibilityStatus compatibilityStatus;
  final String? bandId;
  final int dimensionCount;
  final int availableDimensionCount;
  final int unavailableDimensionCount;
  final int warningCount;
  final int errorCount;

  Map<String, dynamic> toJson() => {
        'mesSnapshotId': mesSnapshotId,
        'mesSchemaVersion': mesSchemaVersion,
        'mesCalculationVersion': mesCalculationVersion,
        'mesCanonicalizationVersion': mesCanonicalizationVersion,
        'projectId': projectId,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'policyStatus': policyStatus.wireName,
        'sourceMetricsSnapshotId': sourceMetricsSnapshotId,
        'sourceEngineeringScoreSnapshotId': sourceEngineeringScoreSnapshotId,
        if (sourceHistorySnapshotId != null)
          'sourceHistorySnapshotId': sourceHistorySnapshotId,
        if (sourceHistoryDiffId != null)
          'sourceHistoryDiffId': sourceHistoryDiffId,
        'createdAt': createdAt,
        if (gitRef != null) 'gitRef': gitRef,
        if (branch != null) 'branch': branch,
        'mesFingerprint': mesFingerprint,
        if (policyFingerprint != null) 'policyFingerprint': policyFingerprint,
        'status': status.wireName,
        'confidence': confidence.wireName,
        'compatibilityStatus': compatibilityStatus.wireName,
        if (bandId != null) 'bandId': bandId,
        'dimensionCount': dimensionCount,
        'availableDimensionCount': availableDimensionCount,
        'unavailableDimensionCount': unavailableDimensionCount,
        'warningCount': warningCount,
        'errorCount': errorCount,
      };

  factory MESMetadata.fromJson(Map<String, dynamic> json) {
    return MESMetadata(
      mesSnapshotId: json['mesSnapshotId'] as String,
      mesSchemaVersion:
          json['mesSchemaVersion'] as int? ?? currentSchemaVersion,
      mesCalculationVersion:
          json['mesCalculationVersion'] as int? ?? currentCalculationVersion,
      mesCanonicalizationVersion: json['mesCanonicalizationVersion'] as int? ??
          currentCanonicalizationVersion,
      projectId: json['projectId'] as String,
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      policyStatus:
          MESPolicyStatusX.fromWireName(json['policyStatus'] as String),
      sourceMetricsSnapshotId: json['sourceMetricsSnapshotId'] as String,
      sourceEngineeringScoreSnapshotId:
          json['sourceEngineeringScoreSnapshotId'] as String,
      sourceHistorySnapshotId: json['sourceHistorySnapshotId'] as String?,
      sourceHistoryDiffId: json['sourceHistoryDiffId'] as String?,
      createdAt: json['createdAt'] as String,
      gitRef: json['gitRef'] as String?,
      branch: json['branch'] as String?,
      mesFingerprint: json['mesFingerprint'] as String,
      policyFingerprint: json['policyFingerprint'] as String?,
      status: MESStatusX.fromWireName(json['status'] as String),
      confidence: MESConfidenceX.fromWireName(json['confidence'] as String),
      compatibilityStatus: MESCompatibilityStatusX.fromWireName(
        json['compatibilityStatus'] as String,
      ),
      bandId: json['bandId'] as String?,
      dimensionCount: json['dimensionCount'] as int,
      availableDimensionCount: json['availableDimensionCount'] as int,
      unavailableDimensionCount: json['unavailableDimensionCount'] as int,
      warningCount: json['warningCount'] as int,
      errorCount: json['errorCount'] as int,
    );
  }
}

class MESWarning {
  const MESWarning({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, dynamic> toJson() => {'code': code, 'message': message};

  factory MESWarning.fromJson(Map<String, dynamic> json) {
    return MESWarning(
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }
}

class MESError {
  const MESError({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, dynamic> toJson() => {'code': code, 'message': message};

  factory MESError.fromJson(Map<String, dynamic> json) {
    return MESError(
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }
}

/// Official immutable MES snapshot.
class MESSnapshot {
  const MESSnapshot({
    required this.metadata,
    required this.mesValue,
    required this.dimensions,
    required this.eligibility,
    required this.coverage,
    required this.confidence,
    required this.evidenceSummary,
    required this.explanation,
    required this.limitations,
    required this.warnings,
    required this.errors,
    this.band,
  });

  final MESMetadata metadata;
  final MESValue mesValue;
  final List<MESDimensionResult> dimensions;
  final MESEligibility eligibility;
  final MESCoverage coverage;
  final MESConfidence confidence;
  final List<MESEvidenceSummary> evidenceSummary;
  final MESExplanation explanation;
  final List<MESLimitation> limitations;
  final List<MESWarning> warnings;
  final List<MESError> errors;
  final MESBand? band;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'mesValue': mesValue.toJson(),
        'dimensions': dimensions.map((d) => d.toJson()).toList(),
        'eligibility': eligibility.toJson(),
        'coverage': coverage.toJson(),
        'confidence': confidence.wireName,
        'evidenceSummary': evidenceSummary.map((e) => e.toJson()).toList(),
        'explanation': explanation.toJson(),
        'limitations': limitations.map((l) => l.toJson()).toList(),
        'warnings': warnings.map((w) => w.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
        if (band != null) 'band': band!.toJson(),
      };

  factory MESSnapshot.fromJson(Map<String, dynamic> json) {
    return MESSnapshot(
      metadata: MESMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
      mesValue: MESValue.fromJson(json['mesValue'] as Map<String, dynamic>),
      dimensions: (json['dimensions'] as List<dynamic>)
          .map((e) => MESDimensionResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      eligibility: MESEligibility.fromJson(
        json['eligibility'] as Map<String, dynamic>,
      ),
      coverage: MESCoverage.fromJson(json['coverage'] as Map<String, dynamic>),
      confidence: MESConfidenceX.fromWireName(json['confidence'] as String),
      evidenceSummary: (json['evidenceSummary'] as List<dynamic>)
          .map((e) => MESEvidenceSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      explanation: MESExplanation.fromJson(
        json['explanation'] as Map<String, dynamic>,
      ),
      limitations: (json['limitations'] as List<dynamic>)
          .map((e) => MESLimitation.fromJson(e as Map<String, dynamic>))
          .toList(),
      warnings: (json['warnings'] as List<dynamic>)
          .map((e) => MESWarning.fromJson(e as Map<String, dynamic>))
          .toList(),
      errors: (json['errors'] as List<dynamic>)
          .map((e) => MESError.fromJson(e as Map<String, dynamic>))
          .toList(),
      band: json['band'] == null
          ? null
          : MESBand.fromJson(json['band'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toComparableJson() {
    final json = toJson();
    final dims = (json['dimensions'] as List<dynamic>)
      ..sort((a, b) => (a as Map)['dimensionId']
          .toString()
          .compareTo((b as Map)['dimensionId'].toString()));
    json['dimensions'] = dims;
    final evidence = (json['evidenceSummary'] as List<dynamic>)
      ..sort((a, b) => (a as Map)['metricId']
          .toString()
          .compareTo((b as Map)['metricId'].toString()));
    json['evidenceSummary'] = evidence;
    json.remove('createdAt');
    final meta = Map<String, dynamic>.from(json['metadata'] as Map);
    meta.remove('createdAt');
    json['metadata'] = meta;
    return json;
  }
}

/// MES snapshot validation result.
class MESValidationResult {
  const MESValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
  });

  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
}
