import 'release_supply_chain_enums.dart';
import 'release_supply_chain_equality.dart';

/// Structured validation issue for release supply chain domain models.
class ReleaseSupplyChainValidationIssue {
  const ReleaseSupplyChainValidationIssue({
    required this.code,
    required this.path,
    required this.severity,
    required this.message,
    this.relatedId,
    this.suggestedAction,
  });

  final String code;
  final String path;
  final ReleaseSupplyChainValidationSeverity severity;
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

  factory ReleaseSupplyChainValidationIssue.fromJson(
      Map<String, dynamic> json) {
    return ReleaseSupplyChainValidationIssue(
      code: json['code'] as String,
      path: json['path'] as String,
      severity: ReleaseSupplyChainValidationSeverityX.fromWireName(
        json['severity'] as String,
      ),
      message: json['message'] as String,
      relatedId: json['relatedId'] as String?,
      suggestedAction: json['suggestedAction'] as String?,
    );
  }

  ReleaseSupplyChainValidationIssue copyWith({
    String? code,
    String? path,
    ReleaseSupplyChainValidationSeverity? severity,
    String? message,
    String? relatedId,
    String? suggestedAction,
  }) {
    return ReleaseSupplyChainValidationIssue(
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
      other is ReleaseSupplyChainValidationIssue &&
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

/// Typed validation result for release supply chain domain artifacts.
class ReleaseSupplyChainValidationResult {
  ReleaseSupplyChainValidationResult({
    required this.isValid,
    List<ReleaseSupplyChainValidationIssue> issues = const [],
    List<String> warnings = const [],
    List<String> errors = const [],
    List<String> limitations = const [],
  })  : issues = List.unmodifiable(issues),
        warnings = List.unmodifiable(warnings),
        errors = List.unmodifiable(errors),
        limitations = List.unmodifiable(limitations);

  final bool isValid;
  final List<ReleaseSupplyChainValidationIssue> issues;
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

  factory ReleaseSupplyChainValidationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseSupplyChainValidationResult(
      isValid: json['isValid'] as bool,
      issues: (json['issues'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseSupplyChainValidationIssue.fromJson(
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

  ReleaseSupplyChainValidationResult copyWith({
    bool? isValid,
    List<ReleaseSupplyChainValidationIssue>? issues,
    List<String>? warnings,
    List<String>? errors,
    List<String>? limitations,
  }) {
    return ReleaseSupplyChainValidationResult(
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
      other is ReleaseSupplyChainValidationResult &&
          isValid == other.isValid &&
          rscListEquals(issues, other.issues) &&
          rscListEquals(warnings, other.warnings) &&
          rscListEquals(errors, other.errors) &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        isValid,
        Object.hashAll(issues),
        Object.hashAll(warnings),
        Object.hashAll(errors),
        Object.hashAll(limitations),
      );
}
