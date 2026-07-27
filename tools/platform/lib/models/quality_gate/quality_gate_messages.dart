import 'quality_gate_enums.dart';

/// Warning surfaced during gate evaluation.
class QualityGateWarning {
  const QualityGateWarning({
    required this.warningId,
    required this.code,
    required this.message,
    required this.severity,
    this.sourceType,
    this.ruleId,
    this.metadata = const {},
  });

  final String warningId;
  final String code;
  final String message;
  final QualityGateRuleSeverity severity;
  final QualityGateSourceType? sourceType;
  final String? ruleId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'warningId': warningId,
        'code': code,
        'message': message,
        'severity': severity.wireName,
        if (sourceType != null) 'sourceType': sourceType!.wireName,
        if (ruleId != null) 'ruleId': ruleId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory QualityGateWarning.fromJson(Map<String, dynamic> json) {
    return QualityGateWarning(
      warningId: json['warningId'] as String,
      code: json['code'] as String,
      message: json['message'] as String,
      severity: QualityGateRuleSeverityX.fromWireName(
        json['severity'] as String,
      ),
      sourceType: json['sourceType'] == null
          ? null
          : QualityGateSourceTypeX.fromWireName(json['sourceType'] as String),
      ruleId: json['ruleId'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

/// Sanitized error during gate evaluation.
class QualityGateError {
  const QualityGateError({
    required this.errorId,
    required this.code,
    required this.message,
    required this.recoverable,
    required this.classification,
    this.sourceType,
    this.ruleId,
    this.metadata = const {},
  });

  final String errorId;
  final String code;
  final String message;
  final QualityGateSourceType? sourceType;
  final String? ruleId;
  final bool recoverable;
  final String classification;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'errorId': errorId,
        'code': code,
        'message': message,
        if (sourceType != null) 'sourceType': sourceType!.wireName,
        if (ruleId != null) 'ruleId': ruleId,
        'recoverable': recoverable,
        'classification': classification,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory QualityGateError.fromJson(Map<String, dynamic> json) {
    return QualityGateError(
      errorId: json['errorId'] as String,
      code: json['code'] as String,
      message: json['message'] as String,
      sourceType: json['sourceType'] == null
          ? null
          : QualityGateSourceTypeX.fromWireName(json['sourceType'] as String),
      ruleId: json['ruleId'] as String?,
      recoverable: json['recoverable'] as bool? ?? false,
      classification: json['classification'] as String? ?? 'internal',
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

/// Explicit limitation during gate evaluation.
class QualityGateLimitation {
  const QualityGateLimitation({
    required this.limitationId,
    required this.type,
    required this.severity,
    required this.description,
    required this.impact,
    required this.resolvable,
    this.sourceType,
    this.ruleId,
    this.remediationHint,
  });

  final String limitationId;
  final QualityGateLimitationType type;
  final QualityGateRuleSeverity severity;
  final QualityGateSourceType? sourceType;
  final String? ruleId;
  final String description;
  final String impact;
  final bool resolvable;
  final String? remediationHint;

  Map<String, dynamic> toJson() => {
        'limitationId': limitationId,
        'type': type.wireName,
        'severity': severity.wireName,
        if (sourceType != null) 'sourceType': sourceType!.wireName,
        if (ruleId != null) 'ruleId': ruleId,
        'description': description,
        'impact': impact,
        'resolvable': resolvable,
        if (remediationHint != null) 'remediationHint': remediationHint,
      };

  factory QualityGateLimitation.fromJson(Map<String, dynamic> json) {
    return QualityGateLimitation(
      limitationId: json['limitationId'] as String,
      type: QualityGateLimitationTypeX.fromWireName(json['type'] as String),
      severity: QualityGateRuleSeverityX.fromWireName(
        json['severity'] as String,
      ),
      sourceType: json['sourceType'] == null
          ? null
          : QualityGateSourceTypeX.fromWireName(json['sourceType'] as String),
      ruleId: json['ruleId'] as String?,
      description: json['description'] as String,
      impact: json['impact'] as String,
      resolvable: json['resolvable'] as bool? ?? false,
      remediationHint: json['remediationHint'] as String?,
    );
  }
}

/// Coverage of rule and source evaluation completeness.
class QualityGateCoverage {
  const QualityGateCoverage({
    required this.totalRuleCount,
    required this.enabledRuleCount,
    required this.evaluatedRuleCount,
    required this.passedRuleCount,
    required this.failedRuleCount,
    required this.unavailableRuleCount,
    required this.incompatibleRuleCount,
    required this.skippedRuleCount,
    required this.notApplicableRuleCount,
    required this.requiredRuleCount,
    required this.evaluatedRequiredRuleCount,
    required this.requiredRuleCoveragePercentage,
    required this.overallRuleCoveragePercentage,
    required this.evidenceCoveragePercentage,
    required this.sourceCoveragePercentage,
    required this.ruleSetCoverage,
    required this.missingRuleIds,
    required this.missingSourceTypes,
    required this.limitations,
  });

  final int totalRuleCount;
  final int enabledRuleCount;
  final int evaluatedRuleCount;
  final int passedRuleCount;
  final int failedRuleCount;
  final int unavailableRuleCount;
  final int incompatibleRuleCount;
  final int skippedRuleCount;
  final int notApplicableRuleCount;
  final int requiredRuleCount;
  final int evaluatedRequiredRuleCount;
  final double requiredRuleCoveragePercentage;
  final double overallRuleCoveragePercentage;
  final double evidenceCoveragePercentage;
  final double sourceCoveragePercentage;
  final Map<String, double> ruleSetCoverage;
  final List<String> missingRuleIds;
  final List<QualityGateSourceType> missingSourceTypes;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'totalRuleCount': totalRuleCount,
        'enabledRuleCount': enabledRuleCount,
        'evaluatedRuleCount': evaluatedRuleCount,
        'passedRuleCount': passedRuleCount,
        'failedRuleCount': failedRuleCount,
        'unavailableRuleCount': unavailableRuleCount,
        'incompatibleRuleCount': incompatibleRuleCount,
        'skippedRuleCount': skippedRuleCount,
        'notApplicableRuleCount': notApplicableRuleCount,
        'requiredRuleCount': requiredRuleCount,
        'evaluatedRequiredRuleCount': evaluatedRequiredRuleCount,
        'requiredRuleCoveragePercentage': requiredRuleCoveragePercentage,
        'overallRuleCoveragePercentage': overallRuleCoveragePercentage,
        'evidenceCoveragePercentage': evidenceCoveragePercentage,
        'sourceCoveragePercentage': sourceCoveragePercentage,
        'ruleSetCoverage': ruleSetCoverage,
        'missingRuleIds': missingRuleIds,
        'missingSourceTypes':
            missingSourceTypes.map((e) => e.wireName).toList(),
        'limitations': limitations,
      };

  factory QualityGateCoverage.fromJson(Map<String, dynamic> json) {
    return QualityGateCoverage(
      totalRuleCount: json['totalRuleCount'] as int,
      enabledRuleCount: json['enabledRuleCount'] as int,
      evaluatedRuleCount: json['evaluatedRuleCount'] as int,
      passedRuleCount: json['passedRuleCount'] as int,
      failedRuleCount: json['failedRuleCount'] as int,
      unavailableRuleCount: json['unavailableRuleCount'] as int,
      incompatibleRuleCount: json['incompatibleRuleCount'] as int,
      skippedRuleCount: json['skippedRuleCount'] as int,
      notApplicableRuleCount: json['notApplicableRuleCount'] as int,
      requiredRuleCount: json['requiredRuleCount'] as int,
      evaluatedRequiredRuleCount: json['evaluatedRequiredRuleCount'] as int,
      requiredRuleCoveragePercentage:
          (json['requiredRuleCoveragePercentage'] as num).toDouble(),
      overallRuleCoveragePercentage:
          (json['overallRuleCoveragePercentage'] as num).toDouble(),
      evidenceCoveragePercentage:
          (json['evidenceCoveragePercentage'] as num).toDouble(),
      sourceCoveragePercentage:
          (json['sourceCoveragePercentage'] as num).toDouble(),
      ruleSetCoverage: (json['ruleSetCoverage'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
      missingRuleIds: (json['missingRuleIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      missingSourceTypes: (json['missingSourceTypes'] as List<dynamic>? ?? [])
          .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Whether evaluation has minimum conditions to produce a decision.
class QualityGateEligibility {
  const QualityGateEligibility({
    required this.status,
    required this.reasons,
    required this.requiredSources,
    required this.availableSources,
    required this.missingSources,
    required this.incompatibleSources,
    required this.eligibilityFingerprint,
  });

  final QualityGateEligibilityStatus status;
  final List<String> reasons;
  final List<QualityGateSourceType> requiredSources;
  final List<QualityGateSourceType> availableSources;
  final List<QualityGateSourceType> missingSources;
  final List<QualityGateSourceType> incompatibleSources;
  final String eligibilityFingerprint;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'reasons': reasons,
        'requiredSources': requiredSources.map((e) => e.wireName).toList(),
        'availableSources': availableSources.map((e) => e.wireName).toList(),
        'missingSources': missingSources.map((e) => e.wireName).toList(),
        'incompatibleSources':
            incompatibleSources.map((e) => e.wireName).toList(),
        'eligibilityFingerprint': eligibilityFingerprint,
      };

  factory QualityGateEligibility.fromJson(Map<String, dynamic> json) {
    return QualityGateEligibility(
      status: QualityGateEligibilityStatusX.fromWireName(
        json['status'] as String,
      ),
      reasons: (json['reasons'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      requiredSources: (json['requiredSources'] as List<dynamic>? ?? [])
          .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
          .toList(),
      availableSources: (json['availableSources'] as List<dynamic>? ?? [])
          .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
          .toList(),
      missingSources: (json['missingSources'] as List<dynamic>? ?? [])
          .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
          .toList(),
      incompatibleSources: (json['incompatibleSources'] as List<dynamic>? ?? [])
          .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
          .toList(),
      eligibilityFingerprint: json['eligibilityFingerprint'] as String,
    );
  }
}

/// Structural compatibility between policy and sources.
class QualityGateCompatibility {
  const QualityGateCompatibility({
    required this.status,
    required this.checks,
    required this.compatibleSources,
    required this.partiallyCompatibleSources,
    required this.incompatibleSources,
    required this.unknownSources,
    required this.reasons,
    required this.compatibilityFingerprint,
  });

  final QualityGateCompatibilityStatus status;
  final List<String> checks;
  final List<QualityGateSourceType> compatibleSources;
  final List<QualityGateSourceType> partiallyCompatibleSources;
  final List<QualityGateSourceType> incompatibleSources;
  final List<QualityGateSourceType> unknownSources;
  final List<String> reasons;
  final String compatibilityFingerprint;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'checks': checks,
        'compatibleSources': compatibleSources.map((e) => e.wireName).toList(),
        'partiallyCompatibleSources':
            partiallyCompatibleSources.map((e) => e.wireName).toList(),
        'incompatibleSources':
            incompatibleSources.map((e) => e.wireName).toList(),
        'unknownSources': unknownSources.map((e) => e.wireName).toList(),
        'reasons': reasons,
        'compatibilityFingerprint': compatibilityFingerprint,
      };

  factory QualityGateCompatibility.fromJson(Map<String, dynamic> json) {
    return QualityGateCompatibility(
      status: QualityGateCompatibilityStatusX.fromWireName(
        json['status'] as String,
      ),
      checks: (json['checks'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      compatibleSources: (json['compatibleSources'] as List<dynamic>? ?? [])
          .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
          .toList(),
      partiallyCompatibleSources:
          (json['partiallyCompatibleSources'] as List<dynamic>? ?? [])
              .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
              .toList(),
      incompatibleSources: (json['incompatibleSources'] as List<dynamic>? ?? [])
          .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
          .toList(),
      unknownSources: (json['unknownSources'] as List<dynamic>? ?? [])
          .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
          .toList(),
      reasons: (json['reasons'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      compatibilityFingerprint: json['compatibilityFingerprint'] as String,
    );
  }
}

/// Domain validation result.
class QualityGateValidationResult {
  const QualityGateValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
  });

  final bool isValid;
  final List<String> errors;
  final List<String> warnings;

  Map<String, dynamic> toJson() => {
        'isValid': isValid,
        'errors': errors,
        'warnings': warnings,
      };

  factory QualityGateValidationResult.fromJson(Map<String, dynamic> json) {
    return QualityGateValidationResult(
      isValid: json['isValid'] as bool,
      errors: (json['errors'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}
