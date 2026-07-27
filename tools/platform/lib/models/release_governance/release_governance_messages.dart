import 'release_governance_enums.dart';

/// Validation issue with structured path.
class ReleaseGovernanceValidationIssue {
  const ReleaseGovernanceValidationIssue({
    required this.code,
    required this.path,
    required this.severity,
    required this.message,
    this.relatedId,
    this.suggestedAction,
  });

  final String code;
  final String path;
  final ReleaseGovernanceRuleSeverity severity;
  final String message;
  final String? relatedId;
  final String? suggestedAction;

  Map<String, dynamic> toJson() => {
        'code': code,
        'path': path,
        'severity': severity.wireName,
        'message': message,
        if (relatedId != null) 'relatedId': relatedId,
        if (suggestedAction != null) 'suggestedAction': suggestedAction,
      };

  factory ReleaseGovernanceValidationIssue.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceValidationIssue(
      code: json['code'] as String,
      path: json['path'] as String,
      severity: ReleaseGovernanceRuleSeverityX.fromWireName(
        json['severity'] as String,
      ),
      message: json['message'] as String,
      relatedId: json['relatedId'] as String?,
      suggestedAction: json['suggestedAction'] as String?,
    );
  }
}

/// Typed validation result for release governance artifacts.
class ReleaseGovernanceValidationResult {
  const ReleaseGovernanceValidationResult({
    required this.isValid,
    this.issues = const [],
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
  });

  final bool isValid;
  final List<ReleaseGovernanceValidationIssue> issues;
  final List<String> warnings;
  final List<String> errors;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'isValid': isValid,
        'issues': issues.map((e) => e.toJson()).toList(),
        'warnings': warnings,
        'errors': errors,
        'limitations': limitations,
      };

  factory ReleaseGovernanceValidationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseGovernanceValidationResult(
      isValid: json['isValid'] as bool,
      issues: (json['issues'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseGovernanceValidationIssue.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      errors: (json['errors'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class ReleaseGovernanceWarning {
  const ReleaseGovernanceWarning({
    required this.warningId,
    required this.code,
    required this.message,
    required this.severity,
    this.ruleId,
    this.approvalId,
    this.waiverId,
    this.metadata = const {},
  });

  final String warningId;
  final ReleaseGovernanceWarningCode code;
  final String message;
  final ReleaseGovernanceRuleSeverity severity;
  final String? ruleId;
  final String? approvalId;
  final String? waiverId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'warningId': warningId,
        'code': code.wireName,
        'message': message,
        'severity': severity.wireName,
        if (ruleId != null) 'ruleId': ruleId,
        if (approvalId != null) 'approvalId': approvalId,
        if (waiverId != null) 'waiverId': waiverId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseGovernanceWarning.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceWarning(
      warningId: json['warningId'] as String,
      code: ReleaseGovernanceWarningCodeX.fromWireName(json['code'] as String),
      message: json['message'] as String,
      severity: ReleaseGovernanceRuleSeverityX.fromWireName(
        json['severity'] as String,
      ),
      ruleId: json['ruleId'] as String?,
      approvalId: json['approvalId'] as String?,
      waiverId: json['waiverId'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

class ReleaseGovernanceError {
  const ReleaseGovernanceError({
    required this.errorId,
    required this.code,
    required this.message,
    required this.recoverable,
    required this.classification,
    this.ruleId,
    this.approvalId,
    this.waiverId,
    this.metadata = const {},
  });

  final String errorId;
  final ReleaseGovernanceErrorCode code;
  final String message;
  final bool recoverable;
  final String classification;
  final String? ruleId;
  final String? approvalId;
  final String? waiverId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'errorId': errorId,
        'code': code.wireName,
        'message': message,
        'recoverable': recoverable,
        'classification': classification,
        if (ruleId != null) 'ruleId': ruleId,
        if (approvalId != null) 'approvalId': approvalId,
        if (waiverId != null) 'waiverId': waiverId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseGovernanceError.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceError(
      errorId: json['errorId'] as String,
      code: ReleaseGovernanceErrorCodeX.fromWireName(json['code'] as String),
      message: json['message'] as String,
      recoverable: json['recoverable'] as bool? ?? false,
      classification: json['classification'] as String? ?? 'internal',
      ruleId: json['ruleId'] as String?,
      approvalId: json['approvalId'] as String?,
      waiverId: json['waiverId'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

class ReleaseGovernanceLimitation {
  const ReleaseGovernanceLimitation({
    required this.limitationId,
    required this.code,
    required this.description,
    required this.impact,
    required this.resolvable,
    this.severity = ReleaseGovernanceRuleSeverity.warning,
    this.ruleId,
    this.remediationHint,
  });

  final String limitationId;
  final ReleaseGovernanceLimitationCode code;
  final String description;
  final String impact;
  final bool resolvable;
  final ReleaseGovernanceRuleSeverity severity;
  final String? ruleId;
  final String? remediationHint;

  Map<String, dynamic> toJson() => {
        'limitationId': limitationId,
        'code': code.wireName,
        'description': description,
        'impact': impact,
        'resolvable': resolvable,
        'severity': severity.wireName,
        if (ruleId != null) 'ruleId': ruleId,
        if (remediationHint != null) 'remediationHint': remediationHint,
      };

  factory ReleaseGovernanceLimitation.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceLimitation(
      limitationId: json['limitationId'] as String,
      code: ReleaseGovernanceLimitationCodeX.fromWireName(
        json['code'] as String,
      ),
      description: json['description'] as String,
      impact: json['impact'] as String,
      resolvable: json['resolvable'] as bool,
      severity: ReleaseGovernanceRuleSeverityX.fromWireName(
        json['severity'] as String? ?? 'warning',
      ),
      ruleId: json['ruleId'] as String?,
      remediationHint: json['remediationHint'] as String?,
    );
  }
}

class ReleaseGovernanceExplanation {
  const ReleaseGovernanceExplanation({
    required this.explanationId,
    required this.type,
    required this.summary,
    required this.detail,
    required this.templateId,
    this.ruleExplanation,
    this.decisionExplanation,
    this.evidenceExplanation,
    this.impactExplanation,
    this.parameters = const {},
    this.limitations = const [],
  });

  final String explanationId;
  final ReleaseGovernanceExplanationType type;
  final String summary;
  final String detail;
  final String templateId;
  final String? ruleExplanation;
  final String? decisionExplanation;
  final String? evidenceExplanation;
  final String? impactExplanation;
  final Map<String, String> parameters;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'explanationId': explanationId,
        'type': type.wireName,
        'summary': summary,
        'detail': detail,
        'templateId': templateId,
        if (ruleExplanation != null) 'ruleExplanation': ruleExplanation,
        if (decisionExplanation != null)
          'decisionExplanation': decisionExplanation,
        if (evidenceExplanation != null)
          'evidenceExplanation': evidenceExplanation,
        if (impactExplanation != null) 'impactExplanation': impactExplanation,
        if (parameters.isNotEmpty) 'parameters': parameters,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseGovernanceExplanation.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceExplanation(
      explanationId: json['explanationId'] as String,
      type: ReleaseGovernanceExplanationTypeX.fromWireName(
        json['type'] as String,
      ),
      summary: json['summary'] as String,
      detail: json['detail'] as String,
      templateId: json['templateId'] as String,
      ruleExplanation: json['ruleExplanation'] as String?,
      decisionExplanation: json['decisionExplanation'] as String?,
      evidenceExplanation: json['evidenceExplanation'] as String?,
      impactExplanation: json['impactExplanation'] as String?,
      parameters: (json['parameters'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Contract for snapshot validation (implementation in Part 2).
abstract class ReleaseDecisionSnapshotValidator {
  const ReleaseDecisionSnapshotValidator();

  ReleaseGovernanceValidationResult validate(dynamic snapshot);
}
