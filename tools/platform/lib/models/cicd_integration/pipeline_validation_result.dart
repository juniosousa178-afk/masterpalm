import 'pipeline_enums.dart';
import 'pipeline_equality.dart';

/// Structured validation issue for CI/CD integration domain models.
class PipelineValidationIssue {
  const PipelineValidationIssue({
    required this.code,
    required this.path,
    required this.severity,
    required this.message,
    this.relatedId,
    this.suggestedAction,
  });

  final String code;
  final String path;
  final PipelineValidationSeverity severity;
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

  factory PipelineValidationIssue.fromJson(Map<String, dynamic> json) {
    return PipelineValidationIssue(
      code: json['code'] as String,
      path: json['path'] as String,
      severity: PipelineValidationSeverityX.fromWireName(
        json['severity'] as String,
      ),
      message: json['message'] as String,
      relatedId: json['relatedId'] as String?,
      suggestedAction: json['suggestedAction'] as String?,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'code': code,
        'path': path,
        'severity': severity.wireName,
        'message': message,
        if (relatedId != null) 'relatedId': relatedId,
        if (suggestedAction != null) 'suggestedAction': suggestedAction,
      };

  PipelineValidationIssue copyWith({
    String? code,
    String? path,
    PipelineValidationSeverity? severity,
    String? message,
    String? relatedId,
    String? suggestedAction,
  }) {
    return PipelineValidationIssue(
      code: code ?? this.code,
      path: path ?? this.path,
      severity: severity ?? this.severity,
      message: message ?? this.message,
      relatedId: relatedId ?? this.relatedId,
      suggestedAction: suggestedAction ?? this.suggestedAction,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineValidationIssue &&
          code == other.code &&
          path == other.path &&
          severity == other.severity &&
          message == other.message &&
          relatedId == other.relatedId &&
          suggestedAction == other.suggestedAction;

  @override
  int get hashCode => Object.hash(
        code,
        path,
        severity,
        message,
        relatedId,
        suggestedAction,
      );
}

/// Aggregate validation result for CI/CD integration domain models.
class PipelineValidationResult {
  const PipelineValidationResult({
    required this.isValid,
    this.issues = const [],
    this.warnings = const [],
    this.errors = const [],
  });

  final bool isValid;
  final List<PipelineValidationIssue> issues;
  final List<String> warnings;
  final List<String> errors;

  Map<String, dynamic> toJson() => {
        'isValid': isValid,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (errors.isNotEmpty) 'errors': errors,
      };

  factory PipelineValidationResult.fromJson(Map<String, dynamic> json) {
    return PipelineValidationResult(
      isValid: json['isValid'] as bool,
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map(
              (e) => PipelineValidationIssue.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      warnings: List.unmodifiable(
        (json['warnings'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      errors: List.unmodifiable(
        (json['errors'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'isValid': isValid,
        if (issues.isNotEmpty)
          'issues': (issues.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => (a['code'] as String).compareTo(b['code'] as String),
            )),
        if (warnings.isNotEmpty)
          'warnings': List<String>.from(warnings)..sort(),
        if (errors.isNotEmpty) 'errors': List<String>.from(errors)..sort(),
      };

  PipelineValidationResult copyWith({
    bool? isValid,
    List<PipelineValidationIssue>? issues,
    List<String>? warnings,
    List<String>? errors,
  }) {
    return PipelineValidationResult(
      isValid: isValid ?? this.isValid,
      issues: issues ?? this.issues,
      warnings: warnings ?? this.warnings,
      errors: errors ?? this.errors,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineValidationResult &&
          isValid == other.isValid &&
          cicdListEquals(issues, other.issues) &&
          cicdListEquals(warnings, other.warnings) &&
          cicdListEquals(errors, other.errors);

  @override
  int get hashCode => Object.hash(
        isValid,
        Object.hashAll(issues),
        Object.hashAll(warnings),
        Object.hashAll(errors),
      );
}
