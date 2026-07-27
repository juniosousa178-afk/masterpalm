import 'cryptographic_trust_enums.dart';
import 'cryptographic_trust_equality.dart';

/// Structured validation issue for Cryptographic Trust domain models.
class CryptographicValidationIssue {
  const CryptographicValidationIssue({
    required this.code,
    required this.path,
    required this.severity,
    required this.message,
    this.relatedId,
    this.suggestedAction,
  });

  final String code;
  final String path;
  final CryptographicIssueSeverity severity;
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

  factory CryptographicValidationIssue.fromJson(Map<String, dynamic> json) {
    return CryptographicValidationIssue(
      code: json['code'] as String,
      path: json['path'] as String,
      severity: CryptographicIssueSeverityX.fromWireName(
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

  CryptographicValidationIssue copyWith({
    String? code,
    String? path,
    CryptographicIssueSeverity? severity,
    String? message,
    String? relatedId,
    String? suggestedAction,
  }) {
    return CryptographicValidationIssue(
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
      other is CryptographicValidationIssue &&
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

/// Aggregate validation result for Cryptographic Trust domain models.
class CryptographicValidationResult {
  const CryptographicValidationResult({
    required this.isValid,
    this.issues = const [],
    this.warnings = const [],
    this.errors = const [],
  });

  final bool isValid;
  final List<CryptographicValidationIssue> issues;
  final List<String> warnings;
  final List<String> errors;

  Map<String, dynamic> toJson() => {
        'isValid': isValid,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (errors.isNotEmpty) 'errors': errors,
      };

  factory CryptographicValidationResult.fromJson(Map<String, dynamic> json) {
    return CryptographicValidationResult(
      isValid: json['isValid'] as bool,
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicValidationIssue.fromJson(
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

  CryptographicValidationResult copyWith({
    bool? isValid,
    List<CryptographicValidationIssue>? issues,
    List<String>? warnings,
    List<String>? errors,
  }) {
    return CryptographicValidationResult(
      isValid: isValid ?? this.isValid,
      issues: issues ?? this.issues,
      warnings: warnings ?? this.warnings,
      errors: errors ?? this.errors,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicValidationResult &&
          isValid == other.isValid &&
          trustListEquals(issues, other.issues) &&
          trustListEquals(warnings, other.warnings) &&
          trustListEquals(errors, other.errors);

  @override
  int get hashCode => Object.hash(
        isValid,
        Object.hashAll(issues),
        Object.hashAll(warnings),
        Object.hashAll(errors),
      );
}
