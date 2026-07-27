import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';

/// Structured issue for Persistent Artifact domain models.
class PersistentArtifactIssue {
  const PersistentArtifactIssue({
    required this.code,
    required this.severity,
    required this.path,
    required this.message,
    this.artifactId,
    this.versionId,
    this.locationId,
    this.policyId,
    this.metadata = const {},
  });

  final String code;
  final PersistentArtifactIssueSeverity severity;
  final String path;
  final String message;
  final String? artifactId;
  final String? versionId;
  final String? locationId;
  final String? policyId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'code': code,
        'severity': severity.wireName,
        'path': path,
        'message': message,
        if (artifactId != null) 'artifactId': artifactId,
        if (versionId != null) 'versionId': versionId,
        if (locationId != null) 'locationId': locationId,
        if (policyId != null) 'policyId': policyId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactIssue.fromJson(Map<String, dynamic> json) {
    return PersistentArtifactIssue(
      code: json['code'] as String,
      severity: PersistentArtifactIssueSeverityX.fromWireName(
        json['severity'] as String,
      ),
      path: json['path'] as String,
      message: json['message'] as String,
      artifactId: json['artifactId'] as String?,
      versionId: json['versionId'] as String?,
      locationId: json['locationId'] as String?,
      policyId: json['policyId'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'code': code,
        'severity': severity.wireName,
        'path': path,
        'message': message,
        if (artifactId != null) 'artifactId': artifactId,
        if (versionId != null) 'versionId': versionId,
        if (locationId != null) 'locationId': locationId,
        if (policyId != null) 'policyId': policyId,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactIssue copyWith({
    String? code,
    PersistentArtifactIssueSeverity? severity,
    String? path,
    String? message,
    String? artifactId,
    String? versionId,
    String? locationId,
    String? policyId,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactIssue(
      code: code ?? this.code,
      severity: severity ?? this.severity,
      path: path ?? this.path,
      message: message ?? this.message,
      artifactId: artifactId ?? this.artifactId,
      versionId: versionId ?? this.versionId,
      locationId: locationId ?? this.locationId,
      policyId: policyId ?? this.policyId,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactIssue &&
          code == other.code &&
          severity == other.severity &&
          path == other.path &&
          message == other.message &&
          artifactId == other.artifactId &&
          versionId == other.versionId &&
          locationId == other.locationId &&
          policyId == other.policyId &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        code,
        severity,
        path,
        message,
        artifactId,
        versionId,
        locationId,
        policyId,
        Object.hashAll(metadata.entries),
      );
}

/// Aggregate validation result for Persistent Artifact domain models.
class PersistentArtifactValidationResult {
  const PersistentArtifactValidationResult({
    required this.isValid,
    this.issues = const [],
    this.warnings = const [],
    this.errors = const [],
    this.infos = const [],
  });

  final bool isValid;
  final List<PersistentArtifactIssue> issues;
  final List<String> warnings;
  final List<String> errors;
  final List<String> infos;

  Map<String, dynamic> toJson() => {
        'isValid': isValid,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (errors.isNotEmpty) 'errors': errors,
        if (infos.isNotEmpty) 'infos': infos,
      };

  factory PersistentArtifactValidationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactValidationResult(
      isValid: json['isValid'] as bool,
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactIssue.fromJson(
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
      infos: List.unmodifiable(
        (json['infos'] as List<dynamic>? ?? [])
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
        if (infos.isNotEmpty) 'infos': List<String>.from(infos)..sort(),
      };

  PersistentArtifactValidationResult copyWith({
    bool? isValid,
    List<PersistentArtifactIssue>? issues,
    List<String>? warnings,
    List<String>? errors,
    List<String>? infos,
  }) {
    return PersistentArtifactValidationResult(
      isValid: isValid ?? this.isValid,
      issues: issues ?? this.issues,
      warnings: warnings ?? this.warnings,
      errors: errors ?? this.errors,
      infos: infos ?? this.infos,
    );
  }

  static PersistentArtifactValidationResult merge(
    Iterable<PersistentArtifactValidationResult> results,
  ) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];
    final infos = <String>[];
    final seenIssueKeys = <String>{};

    for (final result in results) {
      warnings.addAll(result.warnings);
      errors.addAll(result.errors);
      infos.addAll(result.infos);
      for (final issue in result.issues) {
        final key = '${issue.code}|${issue.path}|${issue.message}';
        if (seenIssueKeys.add(key)) {
          issues.add(issue);
        }
      }
    }

    issues.sort((a, b) => a.code.compareTo(b.code));
    warnings.sort();
    errors.sort();
    infos.sort();

    return PersistentArtifactValidationResult(
      isValid: errors.isEmpty,
      issues: List.unmodifiable(issues),
      warnings: List.unmodifiable(warnings),
      errors: List.unmodifiable(errors),
      infos: List.unmodifiable(infos),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactValidationResult &&
          isValid == other.isValid &&
          paListEquals(issues, other.issues) &&
          paListEquals(warnings, other.warnings) &&
          paListEquals(errors, other.errors) &&
          paListEquals(infos, other.infos);

  @override
  int get hashCode => Object.hash(
        isValid,
        Object.hashAll(issues),
        Object.hashAll(warnings),
        Object.hashAll(errors),
        Object.hashAll(infos),
      );
}
