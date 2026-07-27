import 'release_evidence_enums.dart';

/// Validation issue with structured path for release evidence artifacts.
class ReleaseEvidenceValidationIssue {
  const ReleaseEvidenceValidationIssue({
    required this.code,
    required this.path,
    required this.severity,
    required this.message,
    this.relatedId,
    this.suggestedAction,
  });

  final String code;
  final String path;
  final ReleaseEvidenceCollectionRuleSeverity severity;
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

  factory ReleaseEvidenceValidationIssue.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceValidationIssue(
      code: json['code'] as String,
      path: json['path'] as String,
      severity: ReleaseEvidenceCollectionRuleSeverityX.fromWireName(
        json['severity'] as String,
      ),
      message: json['message'] as String,
      relatedId: json['relatedId'] as String?,
      suggestedAction: json['suggestedAction'] as String?,
    );
  }

  ReleaseEvidenceValidationIssue copyWith({
    String? code,
    String? path,
    ReleaseEvidenceCollectionRuleSeverity? severity,
    String? message,
    String? relatedId,
    String? suggestedAction,
  }) {
    return ReleaseEvidenceValidationIssue(
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
      other is ReleaseEvidenceValidationIssue &&
          runtimeType == other.runtimeType &&
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

/// Typed validation result for release evidence artifacts.
class ReleaseEvidenceValidationResult {
  ReleaseEvidenceValidationResult({
    required this.isValid,
    List<ReleaseEvidenceValidationIssue> issues = const [],
    List<String> warnings = const [],
    List<String> errors = const [],
    List<String> limitations = const [],
  })  : issues = List.unmodifiable(issues),
        warnings = List.unmodifiable(warnings),
        errors = List.unmodifiable(errors),
        limitations = List.unmodifiable(limitations);

  final bool isValid;
  final List<ReleaseEvidenceValidationIssue> issues;
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

  factory ReleaseEvidenceValidationResult.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceValidationResult(
      isValid: json['isValid'] as bool,
      issues: (json['issues'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseEvidenceValidationIssue.fromJson(
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

  ReleaseEvidenceValidationResult copyWith({
    bool? isValid,
    List<ReleaseEvidenceValidationIssue>? issues,
    List<String>? warnings,
    List<String>? errors,
    List<String>? limitations,
  }) {
    return ReleaseEvidenceValidationResult(
      isValid: isValid ?? this.isValid,
      issues: issues ?? this.issues,
      warnings: warnings ?? this.warnings,
      errors: errors ?? this.errors,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceValidationResult &&
          runtimeType == other.runtimeType &&
          isValid == other.isValid &&
          _listEquals(issues, other.issues) &&
          _listEquals(warnings, other.warnings) &&
          _listEquals(errors, other.errors) &&
          _listEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        isValid,
        Object.hashAll(issues),
        Object.hashAll(warnings),
        Object.hashAll(errors),
        Object.hashAll(limitations),
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
