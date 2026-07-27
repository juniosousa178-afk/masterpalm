import '../score/score_enums.dart';
import '../score/score_policy.dart';
import 'mes_enums.dart';

/// Official metadata for an MES policy version.
class MESPolicyMetadata {
  const MESPolicyMetadata({
    required this.officialName,
    required this.acronym,
    required this.policyId,
    required this.policyVersion,
    required this.mesSchemaVersion,
    required this.mesCalculationVersion,
    required this.mesCanonicalizationVersion,
    required this.status,
    required this.owner,
    this.calibrated = false,
    this.description,
    this.tags = const [],
  });

  static const officialNameValue = 'MasterPalm Engineering Score';
  static const acronymValue = 'MES';

  final String officialName;
  final String acronym;
  final String policyId;
  final int policyVersion;
  final int mesSchemaVersion;
  final int mesCalculationVersion;
  final int mesCanonicalizationVersion;
  final MESPolicyStatus status;
  final String owner;
  final bool calibrated;
  final String? description;
  final List<String> tags;

  Map<String, dynamic> toJson() => {
        'officialName': officialName,
        'acronym': acronym,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'mesSchemaVersion': mesSchemaVersion,
        'mesCalculationVersion': mesCalculationVersion,
        'mesCanonicalizationVersion': mesCanonicalizationVersion,
        'status': status.wireName,
        'owner': owner,
        'calibrated': calibrated,
        if (description != null) 'description': description,
        if (tags.isNotEmpty) 'tags': tags,
      };

  factory MESPolicyMetadata.fromJson(Map<String, dynamic> json) {
    return MESPolicyMetadata(
      officialName: json['officialName'] as String,
      acronym: json['acronym'] as String,
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      mesSchemaVersion: json['mesSchemaVersion'] as int? ?? 1,
      mesCalculationVersion: json['mesCalculationVersion'] as int? ?? 1,
      mesCanonicalizationVersion:
          json['mesCanonicalizationVersion'] as int? ?? 1,
      status: MESPolicyStatusX.fromWireName(json['status'] as String),
      owner: json['owner'] as String,
      calibrated: json['calibrated'] as bool? ?? false,
      description: json['description'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Metric requirement with evidence tier and rationale.
class MESMetricRequirement {
  const MESMetricRequirement({
    required this.metricId,
    required this.tier,
    required this.rationale,
    this.limitation,
    this.required = true,
  });

  final String metricId;
  final MESEvidenceTier tier;
  final String rationale;
  final String? limitation;
  final bool required;

  Map<String, dynamic> toJson() => {
        'metricId': metricId,
        'tier': tier.wireName,
        'rationale': rationale,
        if (limitation != null) 'limitation': limitation,
        'required': required,
      };

  factory MESMetricRequirement.fromJson(Map<String, dynamic> json) {
    return MESMetricRequirement(
      metricId: json['metricId'] as String,
      tier: MESEvidenceTierX.fromWireName(json['tier'] as String),
      rationale: json['rationale'] as String,
      limitation: json['limitation'] as String?,
      required: json['required'] as bool? ?? true,
    );
  }
}

/// Official MES dimension definition.
class MESDimensionDefinition {
  const MESDimensionDefinition({
    required this.dimensionId,
    required this.name,
    required this.objective,
    required this.weightPercent,
    required this.required,
    required this.metricRequirements,
    required this.rules,
    required this.aggregationMethod,
    this.minimumCoverage = 0,
    this.missingDataPolicy = ScoreMissingDataPolicy.excludeAndReweight,
    this.limitations = const [],
    this.evidenceTier = MESEvidenceTier.authoritative,
  });

  final String dimensionId;
  final String name;
  final String objective;
  final double weightPercent;
  final bool required;
  final MESEvidenceTier evidenceTier;
  final double minimumCoverage;
  final ScoreMissingDataPolicy missingDataPolicy;
  final List<MESMetricRequirement> metricRequirements;
  final List<ScoreRule> rules;
  final List<String> limitations;
  final ScoreAggregationMethod aggregationMethod;

  Map<String, dynamic> toJson() => {
        'dimensionId': dimensionId,
        'name': name,
        'objective': objective,
        'weightPercent': weightPercent,
        'required': required,
        'evidenceTier': evidenceTier.wireName,
        'minimumCoverage': minimumCoverage,
        'missingDataPolicy': missingDataPolicy.wireName,
        'metricRequirements':
            metricRequirements.map((m) => m.toJson()).toList(),
        'rules': rules.map((r) => r.toJson()).toList(),
        if (limitations.isNotEmpty) 'limitations': limitations,
        'aggregationMethod': aggregationMethod.wireName,
      };

  factory MESDimensionDefinition.fromJson(Map<String, dynamic> json) {
    return MESDimensionDefinition(
      dimensionId: json['dimensionId'] as String,
      name: json['name'] as String,
      objective: json['objective'] as String,
      weightPercent: (json['weightPercent'] as num).toDouble(),
      required: json['required'] as bool? ?? true,
      evidenceTier: MESEvidenceTierX.fromWireName(
        json['evidenceTier'] as String? ?? 'authoritative',
      ),
      minimumCoverage: (json['minimumCoverage'] as num?)?.toDouble() ?? 0,
      missingDataPolicy: ScoreMissingDataPolicyX.fromWireName(
        json['missingDataPolicy'] as String? ?? 'excludeAndReweight',
      ),
      metricRequirements: (json['metricRequirements'] as List<dynamic>)
          .map((e) => MESMetricRequirement.fromJson(e as Map<String, dynamic>))
          .toList(),
      rules: (json['rules'] as List<dynamic>)
          .map((e) => ScoreRule.fromJson(e as Map<String, dynamic>))
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      aggregationMethod: ScoreAggregationMethodX.fromWireName(
        json['aggregationMethod'] as String,
      ),
    );
  }
}

/// Eligibility criteria for MES evaluation.
class MESEligibilityPolicy {
  const MESEligibilityPolicy({
    required this.minimumPolicyCoverage,
    required this.minimumRequiredDimensionCoverage,
    required this.allowPartialWithOptionalMissing,
    required this.requireCompatibleMetricsSchema,
    this.allowedPolicyStatuses = const [
      MESPolicyStatus.candidate,
      MESPolicyStatus.active,
    ],
  });

  final double minimumPolicyCoverage;
  final double minimumRequiredDimensionCoverage;
  final bool allowPartialWithOptionalMissing;
  final bool requireCompatibleMetricsSchema;
  final List<MESPolicyStatus> allowedPolicyStatuses;

  Map<String, dynamic> toJson() => {
        'minimumPolicyCoverage': minimumPolicyCoverage,
        'minimumRequiredDimensionCoverage': minimumRequiredDimensionCoverage,
        'allowPartialWithOptionalMissing': allowPartialWithOptionalMissing,
        'requireCompatibleMetricsSchema': requireCompatibleMetricsSchema,
        'allowedPolicyStatuses':
            allowedPolicyStatuses.map((s) => s.wireName).toList(),
      };

  factory MESEligibilityPolicy.fromJson(Map<String, dynamic> json) {
    return MESEligibilityPolicy(
      minimumPolicyCoverage:
          (json['minimumPolicyCoverage'] as num?)?.toDouble() ?? 50,
      minimumRequiredDimensionCoverage:
          (json['minimumRequiredDimensionCoverage'] as num?)?.toDouble() ?? 75,
      allowPartialWithOptionalMissing:
          json['allowPartialWithOptionalMissing'] as bool? ?? true,
      requireCompatibleMetricsSchema:
          json['requireCompatibleMetricsSchema'] as bool? ?? true,
      allowedPolicyStatuses: (json['allowedPolicyStatuses'] as List<dynamic>?)
              ?.map((e) => MESPolicyStatusX.fromWireName(e as String))
              .toList() ??
          const [MESPolicyStatus.candidate, MESPolicyStatus.active],
    );
  }
}

/// Coverage thresholds for hierarchical MES coverage.
class MESCoveragePolicy {
  const MESCoveragePolicy({
    required this.minimumRuleCoverage,
    required this.minimumDimensionCoverage,
    required this.minimumPolicyCoverage,
    required this.minimumEvidenceCoverage,
  });

  final double minimumRuleCoverage;
  final double minimumDimensionCoverage;
  final double minimumPolicyCoverage;
  final double minimumEvidenceCoverage;

  Map<String, dynamic> toJson() => {
        'minimumRuleCoverage': minimumRuleCoverage,
        'minimumDimensionCoverage': minimumDimensionCoverage,
        'minimumPolicyCoverage': minimumPolicyCoverage,
        'minimumEvidenceCoverage': minimumEvidenceCoverage,
      };

  factory MESCoveragePolicy.fromJson(Map<String, dynamic> json) {
    return MESCoveragePolicy(
      minimumRuleCoverage:
          (json['minimumRuleCoverage'] as num?)?.toDouble() ?? 0,
      minimumDimensionCoverage:
          (json['minimumDimensionCoverage'] as num?)?.toDouble() ?? 0,
      minimumPolicyCoverage:
          (json['minimumPolicyCoverage'] as num?)?.toDouble() ?? 50,
      minimumEvidenceCoverage:
          (json['minimumEvidenceCoverage'] as num?)?.toDouble() ?? 50,
    );
  }
}

/// Policy governance changelog entry.
class MESPolicyChange {
  const MESPolicyChange({
    required this.changeType,
    required this.description,
    required this.version,
  });

  final MESPolicyChangeType changeType;
  final String description;
  final int version;

  Map<String, dynamic> toJson() => {
        'changeType': changeType.wireName,
        'description': description,
        'version': version,
      };

  factory MESPolicyChange.fromJson(Map<String, dynamic> json) {
    return MESPolicyChange(
      changeType:
          MESPolicyChangeTypeX.fromWireName(json['changeType'] as String),
      description: json['description'] as String,
      version: json['version'] as int,
    );
  }
}

/// Governance metadata for an MES policy.
class MESGovernance {
  const MESGovernance({
    required this.status,
    required this.owner,
    required this.rationale,
    this.effectiveFrom,
    this.deprecatedAt,
    this.supersedes,
    this.changeLog = const [],
  });

  final MESGovernanceStatus status;
  final String owner;
  final String rationale;
  final String? effectiveFrom;
  final String? deprecatedAt;
  final String? supersedes;
  final List<MESPolicyChange> changeLog;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'owner': owner,
        'rationale': rationale,
        if (effectiveFrom != null) 'effectiveFrom': effectiveFrom,
        if (deprecatedAt != null) 'deprecatedAt': deprecatedAt,
        if (supersedes != null) 'supersedes': supersedes,
        if (changeLog.isNotEmpty)
          'changeLog': changeLog.map((c) => c.toJson()).toList(),
      };

  factory MESGovernance.fromJson(Map<String, dynamic> json) {
    return MESGovernance(
      status: MESGovernanceStatusX.fromWireName(json['status'] as String),
      owner: json['owner'] as String,
      rationale: json['rationale'] as String,
      effectiveFrom: json['effectiveFrom'] as String?,
      deprecatedAt: json['deprecatedAt'] as String?,
      supersedes: json['supersedes'] as String?,
      changeLog: (json['changeLog'] as List<dynamic>? ?? [])
          .map((e) => MESPolicyChange.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Neutral MES classification band.
class MESBand {
  const MESBand({
    required this.bandId,
    required this.min,
    required this.max,
    this.label,
  });

  final String bandId;
  final double min;
  final double max;
  final String? label;

  Map<String, dynamic> toJson() => {
        'bandId': bandId,
        'min': min,
        'max': max,
        if (label != null) 'label': label,
      };

  factory MESBand.fromJson(Map<String, dynamic> json) {
    return MESBand(
      bandId: json['bandId'] as String,
      min: (json['min'] as num).toDouble(),
      max: (json['max'] as num).toDouble(),
      label: json['label'] as String?,
    );
  }
}

/// Official MasterPalm Engineering Score policy.
class MESPolicy {
  const MESPolicy({
    required this.metadata,
    required this.dimensions,
    required this.eligibility,
    required this.coveragePolicy,
    required this.governance,
    required this.bands,
    this.scoreScale = const ScoreScale(),
    this.globalMissingDataPolicy = ScoreMissingDataPolicy.excludeAndReweight,
    this.globalAggregationMethod = ScoreAggregationMethod.weightedAverage,
  });

  static const int currentSchemaVersion = 1;
  static const int currentCalculationVersion = 1;
  static const int currentCanonicalizationVersion = 1;

  final MESPolicyMetadata metadata;
  final List<MESDimensionDefinition> dimensions;
  final MESEligibilityPolicy eligibility;
  final MESCoveragePolicy coveragePolicy;
  final MESGovernance governance;
  final List<MESBand> bands;
  final ScoreScale scoreScale;
  final ScoreMissingDataPolicy globalMissingDataPolicy;
  final ScoreAggregationMethod globalAggregationMethod;

  String get policyId => metadata.policyId;
  int get policyVersion => metadata.policyVersion;

  double get totalWeightPercent =>
      dimensions.fold<double>(0, (sum, d) => sum + d.weightPercent);

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'dimensions': dimensions.map((d) => d.toJson()).toList(),
        'eligibility': eligibility.toJson(),
        'coveragePolicy': coveragePolicy.toJson(),
        'governance': governance.toJson(),
        'bands': bands.map((b) => b.toJson()).toList(),
        'scoreScale': scoreScale.toJson(),
        'globalMissingDataPolicy': globalMissingDataPolicy.wireName,
        'globalAggregationMethod': globalAggregationMethod.wireName,
      };

  factory MESPolicy.fromJson(Map<String, dynamic> json) {
    return MESPolicy(
      metadata: MESPolicyMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      dimensions: (json['dimensions'] as List<dynamic>)
          .map(
              (e) => MESDimensionDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      eligibility: MESEligibilityPolicy.fromJson(
        json['eligibility'] as Map<String, dynamic>,
      ),
      coveragePolicy: MESCoveragePolicy.fromJson(
        json['coveragePolicy'] as Map<String, dynamic>,
      ),
      governance: MESGovernance.fromJson(
        json['governance'] as Map<String, dynamic>,
      ),
      bands: (json['bands'] as List<dynamic>)
          .map((e) => MESBand.fromJson(e as Map<String, dynamic>))
          .toList(),
      scoreScale: ScoreScale.fromJson(
        json['scoreScale'] as Map<String, dynamic>? ?? {},
      ),
      globalMissingDataPolicy: ScoreMissingDataPolicyX.fromWireName(
        json['globalMissingDataPolicy'] as String? ?? 'excludeAndReweight',
      ),
      globalAggregationMethod: ScoreAggregationMethodX.fromWireName(
        json['globalAggregationMethod'] as String? ?? 'weightedAverage',
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
    final bands = (json['bands'] as List<dynamic>)
      ..sort((a, b) =>
          (a as Map)['bandId'].toString().compareTo((b as Map)['bandId']));
    json['bands'] = bands;
    return json;
  }
}

/// MES policy validation result.
class MESPolicyValidationResult {
  const MESPolicyValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
  });

  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
}
