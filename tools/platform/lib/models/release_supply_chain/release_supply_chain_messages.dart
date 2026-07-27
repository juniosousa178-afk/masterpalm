/// Warning surfaced during release supply chain evaluation.
class ReleaseSupplyChainWarning {
  const ReleaseSupplyChainWarning({
    required this.warningId,
    required this.code,
    required this.message,
    this.artifactId,
    this.ruleId,
    this.metadata = const {},
  });

  final String warningId;
  final String code;
  final String message;
  final String? artifactId;
  final String? ruleId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'warningId': warningId,
        'code': code,
        'message': message,
        if (artifactId != null) 'artifactId': artifactId,
        if (ruleId != null) 'ruleId': ruleId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseSupplyChainWarning.fromJson(Map<String, dynamic> json) {
    return ReleaseSupplyChainWarning(
      warningId: json['warningId'] as String,
      code: json['code'] as String,
      message: json['message'] as String,
      artifactId: json['artifactId'] as String?,
      ruleId: json['ruleId'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }
}

/// Sanitized error during release supply chain evaluation.
class ReleaseSupplyChainError {
  const ReleaseSupplyChainError({
    required this.errorId,
    required this.code,
    required this.message,
    this.recoverable = false,
    this.artifactId,
    this.ruleId,
    this.metadata = const {},
  });

  final String errorId;
  final String code;
  final String message;
  final bool recoverable;
  final String? artifactId;
  final String? ruleId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'errorId': errorId,
        'code': code,
        'message': message,
        'recoverable': recoverable,
        if (artifactId != null) 'artifactId': artifactId,
        if (ruleId != null) 'ruleId': ruleId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseSupplyChainError.fromJson(Map<String, dynamic> json) {
    return ReleaseSupplyChainError(
      errorId: json['errorId'] as String,
      code: json['code'] as String,
      message: json['message'] as String,
      recoverable: json['recoverable'] as bool? ?? false,
      artifactId: json['artifactId'] as String?,
      ruleId: json['ruleId'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }
}

/// Documented limitation during release supply chain evaluation.
class ReleaseSupplyChainLimitation {
  const ReleaseSupplyChainLimitation({
    required this.limitationId,
    required this.code,
    required this.description,
    required this.impact,
    this.resolvable = false,
  });

  final String limitationId;
  final String code;
  final String description;
  final String impact;
  final bool resolvable;

  Map<String, dynamic> toJson() => {
        'limitationId': limitationId,
        'code': code,
        'description': description,
        'impact': impact,
        'resolvable': resolvable,
      };

  factory ReleaseSupplyChainLimitation.fromJson(Map<String, dynamic> json) {
    return ReleaseSupplyChainLimitation(
      limitationId: json['limitationId'] as String,
      code: json['code'] as String,
      description: json['description'] as String,
      impact: json['impact'] as String,
      resolvable: json['resolvable'] as bool? ?? false,
    );
  }
}

/// Reference to a resolved release supply chain source artifact.
class ReleaseSupplyChainSourceReference {
  const ReleaseSupplyChainSourceReference({
    required this.sourceType,
    required this.resolutionMode,
    required this.requestedId,
    this.resolvedId,
    this.fingerprint,
    this.projectId,
    this.policyId,
    this.policyVersion,
    this.commitId,
    this.limitations = const [],
  });

  final String sourceType;
  final String resolutionMode;
  final String requestedId;
  final String? resolvedId;
  final String? fingerprint;
  final String? projectId;
  final String? policyId;
  final int? policyVersion;
  final String? commitId;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'sourceType': sourceType,
        'resolutionMode': resolutionMode,
        'requestedId': requestedId,
        if (resolvedId != null) 'resolvedId': resolvedId,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (projectId != null) 'projectId': projectId,
        if (policyId != null) 'policyId': policyId,
        if (policyVersion != null) 'policyVersion': policyVersion,
        if (commitId != null) 'commitId': commitId,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseSupplyChainSourceReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseSupplyChainSourceReference(
      sourceType: json['sourceType'] as String,
      resolutionMode: json['resolutionMode'] as String,
      requestedId: json['requestedId'] as String,
      resolvedId: json['resolvedId'] as String?,
      fingerprint: json['fingerprint'] as String?,
      projectId: json['projectId'] as String?,
      policyId: json['policyId'] as String?,
      policyVersion: json['policyVersion'] as int?,
      commitId: json['commitId'] as String?,
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }
}
