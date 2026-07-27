import 'release_evidence_enums.dart';

/// Warning surfaced during release evidence evaluation.
class ReleaseEvidenceWarning {
  const ReleaseEvidenceWarning({
    required this.warningId,
    required this.code,
    required this.message,
    required this.severity,
    this.evidenceId,
    this.attestationId,
    this.ruleId,
    this.metadata = const {},
  });

  final String warningId;
  final ReleaseEvidenceWarningCode code;
  final String message;
  final ReleaseEvidenceCollectionRuleSeverity severity;
  final String? evidenceId;
  final String? attestationId;
  final String? ruleId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'warningId': warningId,
        'code': code.wireName,
        'message': message,
        'severity': severity.wireName,
        if (evidenceId != null) 'evidenceId': evidenceId,
        if (attestationId != null) 'attestationId': attestationId,
        if (ruleId != null) 'ruleId': ruleId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseEvidenceWarning.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceWarning(
      warningId: json['warningId'] as String,
      code: ReleaseEvidenceWarningCodeX.fromWireName(json['code'] as String),
      message: json['message'] as String,
      severity: ReleaseEvidenceCollectionRuleSeverityX.fromWireName(
        json['severity'] as String,
      ),
      evidenceId: json['evidenceId'] as String?,
      attestationId: json['attestationId'] as String?,
      ruleId: json['ruleId'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceWarning &&
          runtimeType == other.runtimeType &&
          warningId == other.warningId &&
          code == other.code &&
          message == other.message &&
          severity == other.severity &&
          evidenceId == other.evidenceId &&
          attestationId == other.attestationId &&
          ruleId == other.ruleId &&
          _mapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        warningId,
        code,
        message,
        severity,
        evidenceId,
        attestationId,
        ruleId,
        Object.hashAll(metadata.entries),
      );
}

/// Sanitized error during release evidence evaluation.
class ReleaseEvidenceError {
  const ReleaseEvidenceError({
    required this.errorId,
    required this.code,
    required this.message,
    required this.recoverable,
    required this.classification,
    this.evidenceId,
    this.attestationId,
    this.ruleId,
    this.metadata = const {},
  });

  final String errorId;
  final ReleaseEvidenceErrorCode code;
  final String message;
  final bool recoverable;
  final String classification;
  final String? evidenceId;
  final String? attestationId;
  final String? ruleId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'errorId': errorId,
        'code': code.wireName,
        'message': message,
        'recoverable': recoverable,
        'classification': classification,
        if (evidenceId != null) 'evidenceId': evidenceId,
        if (attestationId != null) 'attestationId': attestationId,
        if (ruleId != null) 'ruleId': ruleId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseEvidenceError.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceError(
      errorId: json['errorId'] as String,
      code: ReleaseEvidenceErrorCodeX.fromWireName(json['code'] as String),
      message: json['message'] as String,
      recoverable: json['recoverable'] as bool? ?? false,
      classification: json['classification'] as String? ?? 'internal',
      evidenceId: json['evidenceId'] as String?,
      attestationId: json['attestationId'] as String?,
      ruleId: json['ruleId'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceError &&
          runtimeType == other.runtimeType &&
          errorId == other.errorId &&
          code == other.code &&
          message == other.message &&
          recoverable == other.recoverable &&
          classification == other.classification &&
          evidenceId == other.evidenceId &&
          attestationId == other.attestationId &&
          ruleId == other.ruleId &&
          _mapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        errorId,
        code,
        message,
        recoverable,
        classification,
        evidenceId,
        attestationId,
        ruleId,
        Object.hashAll(metadata.entries),
      );
}

/// Explicit limitation during release evidence evaluation.
class ReleaseEvidenceLimitation {
  const ReleaseEvidenceLimitation({
    required this.limitationId,
    required this.code,
    required this.description,
    required this.impact,
    required this.resolvable,
    this.severity = ReleaseEvidenceCollectionRuleSeverity.warning,
    this.evidenceId,
    this.attestationId,
    this.ruleId,
    this.remediationHint,
  });

  final String limitationId;
  final ReleaseEvidenceLimitationCode code;
  final String description;
  final String impact;
  final bool resolvable;
  final ReleaseEvidenceCollectionRuleSeverity severity;
  final String? evidenceId;
  final String? attestationId;
  final String? ruleId;
  final String? remediationHint;

  Map<String, dynamic> toJson() => {
        'limitationId': limitationId,
        'code': code.wireName,
        'description': description,
        'impact': impact,
        'resolvable': resolvable,
        'severity': severity.wireName,
        if (evidenceId != null) 'evidenceId': evidenceId,
        if (attestationId != null) 'attestationId': attestationId,
        if (ruleId != null) 'ruleId': ruleId,
        if (remediationHint != null) 'remediationHint': remediationHint,
      };

  factory ReleaseEvidenceLimitation.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceLimitation(
      limitationId: json['limitationId'] as String,
      code: ReleaseEvidenceLimitationCodeX.fromWireName(
        json['code'] as String,
      ),
      description: json['description'] as String,
      impact: json['impact'] as String,
      resolvable: json['resolvable'] as bool,
      severity: ReleaseEvidenceCollectionRuleSeverityX.fromWireName(
        json['severity'] as String? ?? 'warning',
      ),
      evidenceId: json['evidenceId'] as String?,
      attestationId: json['attestationId'] as String?,
      ruleId: json['ruleId'] as String?,
      remediationHint: json['remediationHint'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceLimitation &&
          runtimeType == other.runtimeType &&
          limitationId == other.limitationId &&
          code == other.code &&
          description == other.description &&
          impact == other.impact &&
          resolvable == other.resolvable &&
          severity == other.severity &&
          evidenceId == other.evidenceId &&
          attestationId == other.attestationId &&
          ruleId == other.ruleId &&
          remediationHint == other.remediationHint;

  @override
  int get hashCode => Object.hash(
        limitationId,
        code,
        description,
        impact,
        resolvable,
        severity,
        evidenceId,
        attestationId,
        ruleId,
        remediationHint,
      );
}

/// Deterministic explanation for release evidence outcomes.
class ReleaseEvidenceExplanation {
  const ReleaseEvidenceExplanation({
    required this.explanationId,
    required this.type,
    required this.summary,
    required this.detail,
    required this.templateId,
    this.evidenceExplanation,
    this.attestationExplanation,
    this.verificationExplanation,
    this.compatibilityExplanation,
    this.eligibilityExplanation,
    this.impactExplanation,
    this.parameters = const {},
    this.limitations = const [],
  });

  final String explanationId;
  final ReleaseEvidenceExplanationType type;
  final String summary;
  final String detail;
  final String templateId;
  final String? evidenceExplanation;
  final String? attestationExplanation;
  final String? verificationExplanation;
  final String? compatibilityExplanation;
  final String? eligibilityExplanation;
  final String? impactExplanation;
  final Map<String, String> parameters;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'explanationId': explanationId,
        'type': type.wireName,
        'summary': summary,
        'detail': detail,
        'templateId': templateId,
        if (evidenceExplanation != null)
          'evidenceExplanation': evidenceExplanation,
        if (attestationExplanation != null)
          'attestationExplanation': attestationExplanation,
        if (verificationExplanation != null)
          'verificationExplanation': verificationExplanation,
        if (compatibilityExplanation != null)
          'compatibilityExplanation': compatibilityExplanation,
        if (eligibilityExplanation != null)
          'eligibilityExplanation': eligibilityExplanation,
        if (impactExplanation != null) 'impactExplanation': impactExplanation,
        if (parameters.isNotEmpty) 'parameters': parameters,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseEvidenceExplanation.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceExplanation(
      explanationId: json['explanationId'] as String,
      type: ReleaseEvidenceExplanationTypeX.fromWireName(
        json['type'] as String,
      ),
      summary: json['summary'] as String,
      detail: json['detail'] as String,
      templateId: json['templateId'] as String,
      evidenceExplanation: json['evidenceExplanation'] as String?,
      attestationExplanation: json['attestationExplanation'] as String?,
      verificationExplanation: json['verificationExplanation'] as String?,
      compatibilityExplanation: json['compatibilityExplanation'] as String?,
      eligibilityExplanation: json['eligibilityExplanation'] as String?,
      impactExplanation: json['impactExplanation'] as String?,
      parameters: Map.unmodifiable(
        (json['parameters'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceExplanation &&
          runtimeType == other.runtimeType &&
          explanationId == other.explanationId &&
          type == other.type &&
          summary == other.summary &&
          detail == other.detail &&
          templateId == other.templateId &&
          evidenceExplanation == other.evidenceExplanation &&
          attestationExplanation == other.attestationExplanation &&
          verificationExplanation == other.verificationExplanation &&
          compatibilityExplanation == other.compatibilityExplanation &&
          eligibilityExplanation == other.eligibilityExplanation &&
          impactExplanation == other.impactExplanation &&
          _mapEquals(parameters, other.parameters) &&
          _listEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        explanationId,
        type,
        summary,
        detail,
        templateId,
        evidenceExplanation,
        attestationExplanation,
        verificationExplanation,
        compatibilityExplanation,
        eligibilityExplanation,
        impactExplanation,
        Object.hashAll(parameters.entries),
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

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
