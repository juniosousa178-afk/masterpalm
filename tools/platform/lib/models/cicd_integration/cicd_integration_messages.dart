import 'cicd_integration_operational_enums.dart';
import 'pipeline_equality.dart';

/// Structured message surfaced during CI/CD integration evaluation.
class CicdIntegrationMessage {
  const CicdIntegrationMessage({
    required this.messageId,
    required this.code,
    required this.message,
    required this.severity,
    this.operation,
    this.sourceType,
    this.metadata = const {},
  });

  final String messageId;
  final String code;
  final String message;
  final CicdIntegrationMessageSeverity severity;
  final CicdIntegrationOperation? operation;
  final CicdIntegrationSourceType? sourceType;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'code': code,
        'message': message,
        'severity': severity.wireName,
        if (operation != null) 'operation': operation!.wireName,
        if (sourceType != null) 'sourceType': sourceType!.wireName,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CicdIntegrationMessage.fromJson(Map<String, dynamic> json) {
    return CicdIntegrationMessage(
      messageId: json['messageId'] as String,
      code: json['code'] as String,
      message: json['message'] as String,
      severity: CicdIntegrationMessageSeverityX.fromWireName(
        json['severity'] as String,
      ),
      operation: json['operation'] == null
          ? null
          : CicdIntegrationOperationX.fromWireName(
              json['operation'] as String,
            ),
      sourceType: json['sourceType'] == null
          ? null
          : CicdIntegrationSourceTypeX.fromWireName(
              json['sourceType'] as String,
            ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  CicdIntegrationMessage copyWith({
    String? messageId,
    String? code,
    String? message,
    CicdIntegrationMessageSeverity? severity,
    CicdIntegrationOperation? operation,
    CicdIntegrationSourceType? sourceType,
    Map<String, String>? metadata,
  }) {
    return CicdIntegrationMessage(
      messageId: messageId ?? this.messageId,
      code: code ?? this.code,
      message: message ?? this.message,
      severity: severity ?? this.severity,
      operation: operation ?? this.operation,
      sourceType: sourceType ?? this.sourceType,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CicdIntegrationMessage &&
          messageId == other.messageId &&
          code == other.code &&
          message == other.message &&
          severity == other.severity &&
          operation == other.operation &&
          sourceType == other.sourceType &&
          cicdMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        messageId,
        code,
        message,
        severity,
        operation,
        sourceType,
        Object.hashAll(metadata.entries),
      );
}

/// Warning surfaced during CI/CD integration evaluation.
class CicdIntegrationWarning {
  const CicdIntegrationWarning({
    required this.warningId,
    required this.code,
    required this.message,
    this.pipelineDefinitionId,
    this.pipelineExecutionId,
    this.deploymentPlanId,
    this.ruleId,
    this.metadata = const {},
  });

  final String warningId;
  final String code;
  final String message;
  final String? pipelineDefinitionId;
  final String? pipelineExecutionId;
  final String? deploymentPlanId;
  final String? ruleId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'warningId': warningId,
        'code': code,
        'message': message,
        if (pipelineDefinitionId != null)
          'pipelineDefinitionId': pipelineDefinitionId,
        if (pipelineExecutionId != null)
          'pipelineExecutionId': pipelineExecutionId,
        if (deploymentPlanId != null) 'deploymentPlanId': deploymentPlanId,
        if (ruleId != null) 'ruleId': ruleId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CicdIntegrationWarning.fromJson(Map<String, dynamic> json) {
    return CicdIntegrationWarning(
      warningId: json['warningId'] as String,
      code: json['code'] as String,
      message: json['message'] as String,
      pipelineDefinitionId: json['pipelineDefinitionId'] as String?,
      pipelineExecutionId: json['pipelineExecutionId'] as String?,
      deploymentPlanId: json['deploymentPlanId'] as String?,
      ruleId: json['ruleId'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  CicdIntegrationWarning copyWith({
    String? warningId,
    String? code,
    String? message,
    String? pipelineDefinitionId,
    String? pipelineExecutionId,
    String? deploymentPlanId,
    String? ruleId,
    Map<String, String>? metadata,
  }) {
    return CicdIntegrationWarning(
      warningId: warningId ?? this.warningId,
      code: code ?? this.code,
      message: message ?? this.message,
      pipelineDefinitionId: pipelineDefinitionId ?? this.pipelineDefinitionId,
      pipelineExecutionId: pipelineExecutionId ?? this.pipelineExecutionId,
      deploymentPlanId: deploymentPlanId ?? this.deploymentPlanId,
      ruleId: ruleId ?? this.ruleId,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CicdIntegrationWarning &&
          warningId == other.warningId &&
          code == other.code &&
          message == other.message &&
          pipelineDefinitionId == other.pipelineDefinitionId &&
          pipelineExecutionId == other.pipelineExecutionId &&
          deploymentPlanId == other.deploymentPlanId &&
          ruleId == other.ruleId &&
          cicdMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        warningId,
        code,
        message,
        pipelineDefinitionId,
        pipelineExecutionId,
        deploymentPlanId,
        ruleId,
        Object.hashAll(metadata.entries),
      );
}

/// Sanitized error during CI/CD integration evaluation.
class CicdIntegrationError {
  const CicdIntegrationError({
    required this.errorId,
    required this.code,
    required this.message,
    this.recoverable = false,
    this.pipelineDefinitionId,
    this.pipelineExecutionId,
    this.deploymentPlanId,
    this.ruleId,
    this.metadata = const {},
  });

  final String errorId;
  final String code;
  final String message;
  final bool recoverable;
  final String? pipelineDefinitionId;
  final String? pipelineExecutionId;
  final String? deploymentPlanId;
  final String? ruleId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'errorId': errorId,
        'code': code,
        'message': message,
        'recoverable': recoverable,
        if (pipelineDefinitionId != null)
          'pipelineDefinitionId': pipelineDefinitionId,
        if (pipelineExecutionId != null)
          'pipelineExecutionId': pipelineExecutionId,
        if (deploymentPlanId != null) 'deploymentPlanId': deploymentPlanId,
        if (ruleId != null) 'ruleId': ruleId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CicdIntegrationError.fromJson(Map<String, dynamic> json) {
    return CicdIntegrationError(
      errorId: json['errorId'] as String,
      code: json['code'] as String,
      message: json['message'] as String,
      recoverable: json['recoverable'] as bool? ?? false,
      pipelineDefinitionId: json['pipelineDefinitionId'] as String?,
      pipelineExecutionId: json['pipelineExecutionId'] as String?,
      deploymentPlanId: json['deploymentPlanId'] as String?,
      ruleId: json['ruleId'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  CicdIntegrationError copyWith({
    String? errorId,
    String? code,
    String? message,
    bool? recoverable,
    String? pipelineDefinitionId,
    String? pipelineExecutionId,
    String? deploymentPlanId,
    String? ruleId,
    Map<String, String>? metadata,
  }) {
    return CicdIntegrationError(
      errorId: errorId ?? this.errorId,
      code: code ?? this.code,
      message: message ?? this.message,
      recoverable: recoverable ?? this.recoverable,
      pipelineDefinitionId: pipelineDefinitionId ?? this.pipelineDefinitionId,
      pipelineExecutionId: pipelineExecutionId ?? this.pipelineExecutionId,
      deploymentPlanId: deploymentPlanId ?? this.deploymentPlanId,
      ruleId: ruleId ?? this.ruleId,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CicdIntegrationError &&
          errorId == other.errorId &&
          code == other.code &&
          message == other.message &&
          recoverable == other.recoverable &&
          pipelineDefinitionId == other.pipelineDefinitionId &&
          pipelineExecutionId == other.pipelineExecutionId &&
          deploymentPlanId == other.deploymentPlanId &&
          ruleId == other.ruleId &&
          cicdMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        errorId,
        code,
        message,
        recoverable,
        pipelineDefinitionId,
        pipelineExecutionId,
        deploymentPlanId,
        ruleId,
        Object.hashAll(metadata.entries),
      );
}

/// Documented limitation during CI/CD integration evaluation.
class CicdIntegrationLimitation {
  const CicdIntegrationLimitation({
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

  factory CicdIntegrationLimitation.fromJson(Map<String, dynamic> json) {
    return CicdIntegrationLimitation(
      limitationId: json['limitationId'] as String,
      code: json['code'] as String,
      description: json['description'] as String,
      impact: json['impact'] as String,
      resolvable: json['resolvable'] as bool? ?? false,
    );
  }

  CicdIntegrationLimitation copyWith({
    String? limitationId,
    String? code,
    String? description,
    String? impact,
    bool? resolvable,
  }) {
    return CicdIntegrationLimitation(
      limitationId: limitationId ?? this.limitationId,
      code: code ?? this.code,
      description: description ?? this.description,
      impact: impact ?? this.impact,
      resolvable: resolvable ?? this.resolvable,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CicdIntegrationLimitation &&
          limitationId == other.limitationId &&
          code == other.code &&
          description == other.description &&
          impact == other.impact &&
          resolvable == other.resolvable;

  @override
  int get hashCode =>
      Object.hash(limitationId, code, description, impact, resolvable);
}

/// Reference to a resolved CI/CD integration source artifact.
class CicdIntegrationSourceReference {
  const CicdIntegrationSourceReference({
    required this.sourceType,
    required this.resolutionMode,
    required this.requestedId,
    this.resolvedId,
    this.fingerprint,
    this.projectId,
    this.releaseId,
    this.policyId,
    this.policyVersion,
    this.limitations = const [],
  });

  final String sourceType;
  final String resolutionMode;
  final String requestedId;
  final String? resolvedId;
  final String? fingerprint;
  final String? projectId;
  final String? releaseId;
  final String? policyId;
  final int? policyVersion;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'sourceType': sourceType,
        'resolutionMode': resolutionMode,
        'requestedId': requestedId,
        if (resolvedId != null) 'resolvedId': resolvedId,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (projectId != null) 'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (policyId != null) 'policyId': policyId,
        if (policyVersion != null) 'policyVersion': policyVersion,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory CicdIntegrationSourceReference.fromJson(Map<String, dynamic> json) {
    return CicdIntegrationSourceReference(
      sourceType: json['sourceType'] as String,
      resolutionMode: json['resolutionMode'] as String,
      requestedId: json['requestedId'] as String,
      resolvedId: json['resolvedId'] as String?,
      fingerprint: json['fingerprint'] as String?,
      projectId: json['projectId'] as String?,
      releaseId: json['releaseId'] as String?,
      policyId: json['policyId'] as String?,
      policyVersion: json['policyVersion'] as int?,
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'sourceType': sourceType,
        'resolutionMode': resolutionMode,
        'requestedId': requestedId,
        if (resolvedId != null) 'resolvedId': resolvedId,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (projectId != null) 'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (policyId != null) 'policyId': policyId,
        if (policyVersion != null) 'policyVersion': policyVersion,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  CicdIntegrationSourceReference copyWith({
    String? sourceType,
    String? resolutionMode,
    String? requestedId,
    String? resolvedId,
    String? fingerprint,
    String? projectId,
    String? releaseId,
    String? policyId,
    int? policyVersion,
    List<String>? limitations,
  }) {
    return CicdIntegrationSourceReference(
      sourceType: sourceType ?? this.sourceType,
      resolutionMode: resolutionMode ?? this.resolutionMode,
      requestedId: requestedId ?? this.requestedId,
      resolvedId: resolvedId ?? this.resolvedId,
      fingerprint: fingerprint ?? this.fingerprint,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CicdIntegrationSourceReference &&
          sourceType == other.sourceType &&
          resolutionMode == other.resolutionMode &&
          requestedId == other.requestedId &&
          resolvedId == other.resolvedId &&
          fingerprint == other.fingerprint &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          cicdListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        sourceType,
        resolutionMode,
        requestedId,
        resolvedId,
        fingerprint,
        projectId,
        releaseId,
        policyId,
        policyVersion,
        Object.hashAll(limitations),
      );
}
