import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';
import 'persistent_artifact_infrastructure_snapshot.dart';
import 'persistent_artifact_operation_models.dart';
import 'persistent_artifact_operational_enums.dart';
import 'persistent_artifact_reference_models.dart';
import 'persistent_artifact_subject.dart';

class PersistentArtifactEvaluationRequest {
  const PersistentArtifactEvaluationRequest({
    required this.evaluationId,
    required this.projectId,
    required this.operationRequest,
    required this.requestedAt,
    this.releaseId,
    this.policyReferences = const [],
    this.injectedSources = const {},
    this.useLatest = true,
    this.allowCandidate = false,
    this.metadata = const {},
  });

  final String evaluationId;
  final String projectId;
  final String? releaseId;
  final PersistentArtifactOperationRequest operationRequest;
  final List<PersistentArtifactPolicyReference> policyReferences;
  final Map<String, String> injectedSources;
  final bool useLatest;
  final bool allowCandidate;
  final String requestedAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'evaluationId': evaluationId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'operationRequest': operationRequest.toJson(),
        if (policyReferences.isNotEmpty)
          'policyReferences': policyReferences.map((e) => e.toJson()).toList(),
        if (injectedSources.isNotEmpty) 'injectedSources': injectedSources,
        'useLatest': useLatest,
        'allowCandidate': allowCandidate,
        'requestedAt': requestedAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactEvaluationRequest.fromJson(
      Map<String, dynamic> json) {
    return PersistentArtifactEvaluationRequest(
      evaluationId: json['evaluationId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      operationRequest: PersistentArtifactOperationRequest.fromJson(
        json['operationRequest'] as Map<String, dynamic>,
      ),
      policyReferences: List.unmodifiable(
        (json['policyReferences'] as List<dynamic>? ?? [])
            .map((e) => PersistentArtifactPolicyReference.fromJson(
                e as Map<String, dynamic>))
            .toList(),
      ),
      injectedSources: Map.unmodifiable(
        (json['injectedSources'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
      ),
      useLatest: json['useLatest'] as bool? ?? true,
      allowCandidate: json['allowCandidate'] as bool? ?? false,
      requestedAt: json['requestedAt'] as String,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'evaluationId': evaluationId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'operationRequest': operationRequest.toComparableJson(),
        if (policyReferences.isNotEmpty)
          'policyReferences': paSortedComparableList(
            policyReferences.map((e) => e.toComparableJson()),
            'policyId',
          ),
        if (injectedSources.isNotEmpty)
          'injectedSources': paSortedStringMap(injectedSources),
        'useLatest': useLatest,
        'allowCandidate': allowCandidate,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactEvaluationRequest copyWith({
    String? evaluationId,
    String? projectId,
    String? releaseId,
    PersistentArtifactOperationRequest? operationRequest,
    List<PersistentArtifactPolicyReference>? policyReferences,
    Map<String, String>? injectedSources,
    bool? useLatest,
    bool? allowCandidate,
    String? requestedAt,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactEvaluationRequest(
      evaluationId: evaluationId ?? this.evaluationId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      operationRequest: operationRequest ?? this.operationRequest,
      policyReferences: policyReferences ?? this.policyReferences,
      injectedSources: injectedSources ?? this.injectedSources,
      useLatest: useLatest ?? this.useLatest,
      allowCandidate: allowCandidate ?? this.allowCandidate,
      requestedAt: requestedAt ?? this.requestedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactEvaluationRequest &&
          evaluationId == other.evaluationId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          operationRequest == other.operationRequest &&
          paListEquals(policyReferences, other.policyReferences) &&
          paMapEquals(injectedSources, other.injectedSources) &&
          useLatest == other.useLatest &&
          allowCandidate == other.allowCandidate &&
          requestedAt == other.requestedAt &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        evaluationId,
        projectId,
        releaseId,
        operationRequest,
        Object.hashAll(policyReferences),
        Object.hashAll(injectedSources.entries),
        useLatest,
        allowCandidate,
        requestedAt,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactEvaluationResult {
  const PersistentArtifactEvaluationResult({
    required this.status,
    required this.evaluationId,
    required this.projectId,
    required this.evaluatedAt,
    this.releaseId,
    this.operationResult,
    this.snapshot,
    this.snapshotReference,
    this.sourceResolutionSummary,
    this.policyResults = const [],
    this.messages = const [],
    this.metadata = const {},
  });

  final PersistentArtifactEvaluationStatus status;
  final String evaluationId;
  final String projectId;
  final String? releaseId;
  final PersistentArtifactOperationResult? operationResult;
  final PersistentArtifactInfrastructureSnapshot? snapshot;
  final PersistentArtifactSnapshotReference? snapshotReference;
  final ResolvedPersistentArtifactSources? sourceResolutionSummary;
  final List<PersistentArtifactPolicyEvaluationResult> policyResults;
  final List<PersistentArtifactOperationMessage> messages;
  final String evaluatedAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'evaluationId': evaluationId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (operationResult != null)
          'operationResult': operationResult!.toJson(),
        if (snapshot != null) 'snapshot': snapshot!.toJson(),
        if (snapshotReference != null)
          'snapshotReference': snapshotReference!.toJson(),
        if (sourceResolutionSummary != null)
          'sourceResolutionSummary': sourceResolutionSummary!.toJson(),
        if (policyResults.isNotEmpty)
          'policyResults': policyResults.map((e) => e.toJson()).toList(),
        if (messages.isNotEmpty)
          'messages': messages.map((e) => e.toJson()).toList(),
        'evaluatedAt': evaluatedAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactEvaluationResult.fromJson(
      Map<String, dynamic> json) {
    return PersistentArtifactEvaluationResult(
      status: PersistentArtifactEvaluationStatusX.fromWireName(
          json['status'] as String),
      evaluationId: json['evaluationId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      operationResult: json['operationResult'] == null
          ? null
          : PersistentArtifactOperationResult.fromJson(
              json['operationResult'] as Map<String, dynamic>,
            ),
      snapshot: json['snapshot'] == null
          ? null
          : PersistentArtifactInfrastructureSnapshot.fromJson(
              json['snapshot'] as Map<String, dynamic>,
            ),
      snapshotReference: json['snapshotReference'] == null
          ? null
          : PersistentArtifactSnapshotReference.fromJson(
              json['snapshotReference'] as Map<String, dynamic>,
            ),
      sourceResolutionSummary: json['sourceResolutionSummary'] == null
          ? null
          : ResolvedPersistentArtifactSources.fromJson(
              json['sourceResolutionSummary'] as Map<String, dynamic>,
            ),
      policyResults: List.unmodifiable(
        (json['policyResults'] as List<dynamic>? ?? [])
            .map((e) => PersistentArtifactPolicyEvaluationResult.fromJson(
                e as Map<String, dynamic>))
            .toList(),
      ),
      messages: List.unmodifiable(
        (json['messages'] as List<dynamic>? ?? [])
            .map((e) => PersistentArtifactOperationMessage.fromJson(
                e as Map<String, dynamic>))
            .toList(),
      ),
      evaluatedAt: json['evaluatedAt'] as String,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'status': status.wireName,
        'evaluationId': evaluationId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (operationResult != null)
          'operationResult': operationResult!.toComparableJson(),
        if (snapshot != null) 'snapshot': snapshot!.toComparableJson(),
        if (snapshotReference != null)
          'snapshotReference': snapshotReference!.toComparableJson(),
        if (sourceResolutionSummary != null)
          'sourceResolutionSummary':
              sourceResolutionSummary!.toComparableJson(),
        if (policyResults.isNotEmpty)
          'policyResults': paSortedComparableList(
              policyResults.map((e) => e.toComparableJson()), 'policyId'),
        if (messages.isNotEmpty)
          'messages': paSortedComparableList(
              messages.map((e) => e.toComparableJson()), 'messageId'),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactEvaluationResult copyWith({
    PersistentArtifactEvaluationStatus? status,
    String? evaluationId,
    String? projectId,
    String? releaseId,
    PersistentArtifactOperationResult? operationResult,
    PersistentArtifactInfrastructureSnapshot? snapshot,
    PersistentArtifactSnapshotReference? snapshotReference,
    ResolvedPersistentArtifactSources? sourceResolutionSummary,
    List<PersistentArtifactPolicyEvaluationResult>? policyResults,
    List<PersistentArtifactOperationMessage>? messages,
    String? evaluatedAt,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactEvaluationResult(
      status: status ?? this.status,
      evaluationId: evaluationId ?? this.evaluationId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      operationResult: operationResult ?? this.operationResult,
      snapshot: snapshot ?? this.snapshot,
      snapshotReference: snapshotReference ?? this.snapshotReference,
      sourceResolutionSummary:
          sourceResolutionSummary ?? this.sourceResolutionSummary,
      policyResults: policyResults ?? this.policyResults,
      messages: messages ?? this.messages,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactEvaluationResult &&
          status == other.status &&
          evaluationId == other.evaluationId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          operationResult == other.operationResult &&
          snapshot == other.snapshot &&
          snapshotReference == other.snapshotReference &&
          sourceResolutionSummary == other.sourceResolutionSummary &&
          paListEquals(policyResults, other.policyResults) &&
          paListEquals(messages, other.messages) &&
          evaluatedAt == other.evaluatedAt &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        status,
        evaluationId,
        projectId,
        releaseId,
        operationResult,
        snapshot,
        snapshotReference,
        sourceResolutionSummary,
        Object.hashAll(policyResults),
        Object.hashAll(messages),
        evaluatedAt,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactQuery {
  const PersistentArtifactQuery({
    this.projectId,
    this.releaseId,
    this.artifactId,
    this.status,
    this.createdFrom,
    this.createdUntil,
    this.limit,
    this.offset,
  });

  final String? projectId;
  final String? releaseId;
  final String? artifactId;
  final PersistentArtifactInfrastructureStatus? status;
  final String? createdFrom;
  final String? createdUntil;
  final int? limit;
  final int? offset;

  Map<String, dynamic> toJson() => {
        if (projectId != null) 'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (artifactId != null) 'artifactId': artifactId,
        if (status != null) 'status': status!.wireName,
        if (createdFrom != null) 'createdFrom': createdFrom,
        if (createdUntil != null) 'createdUntil': createdUntil,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      };

  factory PersistentArtifactQuery.fromJson(Map<String, dynamic> json) {
    return PersistentArtifactQuery(
      projectId: json['projectId'] as String?,
      releaseId: json['releaseId'] as String?,
      artifactId: json['artifactId'] as String?,
      status: json['status'] == null
          ? null
          : PersistentArtifactInfrastructureStatusX.fromWireName(
              json['status'] as String),
      createdFrom: json['createdFrom'] as String?,
      createdUntil: json['createdUntil'] as String?,
      limit: json['limit'] as int?,
      offset: json['offset'] as int?,
    );
  }

  Map<String, dynamic> toComparableJson() => toJson();

  PersistentArtifactQuery copyWith({
    String? projectId,
    String? releaseId,
    String? artifactId,
    PersistentArtifactInfrastructureStatus? status,
    String? createdFrom,
    String? createdUntil,
    int? limit,
    int? offset,
  }) {
    return PersistentArtifactQuery(
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      artifactId: artifactId ?? this.artifactId,
      status: status ?? this.status,
      createdFrom: createdFrom ?? this.createdFrom,
      createdUntil: createdUntil ?? this.createdUntil,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactQuery &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          artifactId == other.artifactId &&
          status == other.status &&
          createdFrom == other.createdFrom &&
          createdUntil == other.createdUntil &&
          limit == other.limit &&
          offset == other.offset;

  @override
  int get hashCode => Object.hash(
        projectId,
        releaseId,
        artifactId,
        status,
        createdFrom,
        createdUntil,
        limit,
        offset,
      );
}

class PersistentArtifactOperationMessage {
  const PersistentArtifactOperationMessage({
    required this.messageId,
    required this.code,
    required this.message,
    required this.severity,
    required this.operation,
    this.sourceType,
    this.conflictType,
    this.metadata = const {},
  });

  final String messageId;
  final String code;
  final String message;
  final PersistentArtifactIssueSeverity severity;
  final PersistentArtifactOperationType operation;
  final PersistentArtifactSourceType? sourceType;
  final PersistentArtifactOperationalConflictType? conflictType;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'code': code,
        'message': message,
        'severity': severity.wireName,
        'operation': operation.wireName,
        if (sourceType != null) 'sourceType': sourceType!.wireName,
        if (conflictType != null) 'conflictType': conflictType!.wireName,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactOperationMessage.fromJson(
      Map<String, dynamic> json) {
    return PersistentArtifactOperationMessage(
      messageId: json['messageId'] as String,
      code: json['code'] as String,
      message: json['message'] as String,
      severity: PersistentArtifactIssueSeverityX.fromWireName(
          json['severity'] as String),
      operation: PersistentArtifactOperationTypeX.fromWireName(
          json['operation'] as String),
      sourceType: json['sourceType'] == null
          ? null
          : PersistentArtifactSourceTypeX.fromWireName(
              json['sourceType'] as String),
      conflictType: json['conflictType'] == null
          ? null
          : PersistentArtifactOperationalConflictTypeX.fromWireName(
              json['conflictType'] as String),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'messageId': messageId,
        'code': code,
        'message': message,
        'severity': severity.wireName,
        'operation': operation.wireName,
        if (sourceType != null) 'sourceType': sourceType!.wireName,
        if (conflictType != null) 'conflictType': conflictType!.wireName,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactOperationMessage copyWith({
    String? messageId,
    String? code,
    String? message,
    PersistentArtifactIssueSeverity? severity,
    PersistentArtifactOperationType? operation,
    PersistentArtifactSourceType? sourceType,
    PersistentArtifactOperationalConflictType? conflictType,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactOperationMessage(
      messageId: messageId ?? this.messageId,
      code: code ?? this.code,
      message: message ?? this.message,
      severity: severity ?? this.severity,
      operation: operation ?? this.operation,
      sourceType: sourceType ?? this.sourceType,
      conflictType: conflictType ?? this.conflictType,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactOperationMessage &&
          messageId == other.messageId &&
          code == other.code &&
          message == other.message &&
          severity == other.severity &&
          operation == other.operation &&
          sourceType == other.sourceType &&
          conflictType == other.conflictType &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        messageId,
        code,
        message,
        severity,
        operation,
        sourceType,
        conflictType,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactRequirementResult {
  const PersistentArtifactRequirementResult({
    required this.requirementId,
    required this.requirementType,
    required this.status,
    this.message,
    this.metadata = const {},
  });

  final String requirementId;
  final PersistentArtifactRequirementType requirementType;
  final PersistentArtifactRequirementStatus status;
  final String? message;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'requirementId': requirementId,
        'requirementType': requirementType.wireName,
        'status': status.wireName,
        if (message != null) 'message': message,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactRequirementResult.fromJson(
      Map<String, dynamic> json) {
    return PersistentArtifactRequirementResult(
      requirementId: json['requirementId'] as String,
      requirementType: PersistentArtifactRequirementTypeX.fromWireName(
        json['requirementType'] as String,
      ),
      status: PersistentArtifactRequirementStatusX.fromWireName(
          json['status'] as String),
      message: json['message'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'requirementId': requirementId,
        'requirementType': requirementType.wireName,
        'status': status.wireName,
        if (message != null) 'message': message,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactRequirementResult copyWith({
    String? requirementId,
    PersistentArtifactRequirementType? requirementType,
    PersistentArtifactRequirementStatus? status,
    String? message,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactRequirementResult(
      requirementId: requirementId ?? this.requirementId,
      requirementType: requirementType ?? this.requirementType,
      status: status ?? this.status,
      message: message ?? this.message,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactRequirementResult &&
          requirementId == other.requirementId &&
          requirementType == other.requirementType &&
          status == other.status &&
          message == other.message &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        requirementId,
        requirementType,
        status,
        message,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactPolicyEvaluationResult {
  const PersistentArtifactPolicyEvaluationResult({
    required this.policyId,
    required this.policyVersion,
    required this.policyType,
    required this.status,
    this.requirementResults = const [],
    this.messages = const [],
    this.metadata = const {},
  });

  final String policyId;
  final int policyVersion;
  final PersistentArtifactPolicyType policyType;
  final PersistentArtifactOperationStatus status;
  final List<PersistentArtifactRequirementResult> requirementResults;
  final List<PersistentArtifactOperationMessage> messages;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'policyType': policyType.wireName,
        'status': status.wireName,
        if (requirementResults.isNotEmpty)
          'requirementResults':
              requirementResults.map((e) => e.toJson()).toList(),
        if (messages.isNotEmpty)
          'messages': messages.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactPolicyEvaluationResult.fromJson(
      Map<String, dynamic> json) {
    return PersistentArtifactPolicyEvaluationResult(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      policyType: PersistentArtifactPolicyTypeX.fromWireName(
          json['policyType'] as String),
      status: PersistentArtifactOperationStatusX.fromWireName(
          json['status'] as String),
      requirementResults: List.unmodifiable(
        (json['requirementResults'] as List<dynamic>? ?? [])
            .map((e) => PersistentArtifactRequirementResult.fromJson(
                e as Map<String, dynamic>))
            .toList(),
      ),
      messages: List.unmodifiable(
        (json['messages'] as List<dynamic>? ?? [])
            .map((e) => PersistentArtifactOperationMessage.fromJson(
                e as Map<String, dynamic>))
            .toList(),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'policyType': policyType.wireName,
        'status': status.wireName,
        if (requirementResults.isNotEmpty)
          'requirementResults': paSortedComparableList(
            requirementResults.map((e) => e.toComparableJson()),
            'requirementId',
          ),
        if (messages.isNotEmpty)
          'messages': paSortedComparableList(
              messages.map((e) => e.toComparableJson()), 'messageId'),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactPolicyEvaluationResult copyWith({
    String? policyId,
    int? policyVersion,
    PersistentArtifactPolicyType? policyType,
    PersistentArtifactOperationStatus? status,
    List<PersistentArtifactRequirementResult>? requirementResults,
    List<PersistentArtifactOperationMessage>? messages,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactPolicyEvaluationResult(
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      policyType: policyType ?? this.policyType,
      status: status ?? this.status,
      requirementResults: requirementResults ?? this.requirementResults,
      messages: messages ?? this.messages,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactPolicyEvaluationResult &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          policyType == other.policyType &&
          status == other.status &&
          paListEquals(requirementResults, other.requirementResults) &&
          paListEquals(messages, other.messages) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        policyId,
        policyVersion,
        policyType,
        status,
        Object.hashAll(requirementResults),
        Object.hashAll(messages),
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactConflict {
  const PersistentArtifactConflict({
    required this.conflictId,
    required this.type,
    required this.message,
    required this.severity,
    this.leftFingerprint,
    this.rightFingerprint,
    this.metadata = const {},
  });

  final String conflictId;
  final PersistentArtifactOperationalConflictType type;
  final String message;
  final PersistentArtifactIssueSeverity severity;
  final String? leftFingerprint;
  final String? rightFingerprint;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'conflictId': conflictId,
        'type': type.wireName,
        'message': message,
        'severity': severity.wireName,
        if (leftFingerprint != null) 'leftFingerprint': leftFingerprint,
        if (rightFingerprint != null) 'rightFingerprint': rightFingerprint,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactConflict.fromJson(Map<String, dynamic> json) {
    return PersistentArtifactConflict(
      conflictId: json['conflictId'] as String,
      type: PersistentArtifactOperationalConflictTypeX.fromWireName(
          json['type'] as String),
      message: json['message'] as String,
      severity: PersistentArtifactIssueSeverityX.fromWireName(
          json['severity'] as String),
      leftFingerprint: json['leftFingerprint'] as String?,
      rightFingerprint: json['rightFingerprint'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'conflictId': conflictId,
        'type': type.wireName,
        'message': message,
        'severity': severity.wireName,
        if (leftFingerprint != null) 'leftFingerprint': leftFingerprint,
        if (rightFingerprint != null) 'rightFingerprint': rightFingerprint,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactConflict copyWith({
    String? conflictId,
    PersistentArtifactOperationalConflictType? type,
    String? message,
    PersistentArtifactIssueSeverity? severity,
    String? leftFingerprint,
    String? rightFingerprint,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactConflict(
      conflictId: conflictId ?? this.conflictId,
      type: type ?? this.type,
      message: message ?? this.message,
      severity: severity ?? this.severity,
      leftFingerprint: leftFingerprint ?? this.leftFingerprint,
      rightFingerprint: rightFingerprint ?? this.rightFingerprint,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactConflict &&
          conflictId == other.conflictId &&
          type == other.type &&
          message == other.message &&
          severity == other.severity &&
          leftFingerprint == other.leftFingerprint &&
          rightFingerprint == other.rightFingerprint &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        conflictId,
        type,
        message,
        severity,
        leftFingerprint,
        rightFingerprint,
        Object.hashAll(metadata.entries),
      );
}

class ResolvedPersistentArtifactSource<T> {
  const ResolvedPersistentArtifactSource({
    required this.sourceType,
    required this.resolutionMode,
    required this.state,
    this.resolvedArtifact,
    this.resolvedId,
    this.requestedId,
    this.fingerprint,
    this.projectId,
    this.releaseId,
  });

  final PersistentArtifactSourceType sourceType;
  final PersistentArtifactSourceResolutionMode resolutionMode;
  final PersistentArtifactSourceState state;
  final T? resolvedArtifact;
  final String? resolvedId;
  final String? requestedId;
  final String? fingerprint;
  final String? projectId;
  final String? releaseId;

  bool get isAvailable => state == PersistentArtifactSourceState.available;
}

class ResolvedPersistentArtifactSources {
  const ResolvedPersistentArtifactSources({
    required this.status,
    this.resolvedSources = const [],
    this.unresolvedSources = const [],
    this.injectedSources = const [],
    this.sourceReferences = const [],
    this.messages = const [],
    this.fingerprint,
  });

  final PersistentArtifactSourceResolutionStatus status;
  final List<String> resolvedSources;
  final List<String> unresolvedSources;
  final List<String> injectedSources;
  final List<PersistentArtifactSourceReference> sourceReferences;
  final List<PersistentArtifactOperationMessage> messages;
  final String? fingerprint;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        if (resolvedSources.isNotEmpty) 'resolvedSources': resolvedSources,
        if (unresolvedSources.isNotEmpty)
          'unresolvedSources': unresolvedSources,
        if (injectedSources.isNotEmpty) 'injectedSources': injectedSources,
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        if (messages.isNotEmpty)
          'messages': messages.map((e) => e.toJson()).toList(),
        if (fingerprint != null) 'fingerprint': fingerprint,
      };

  factory ResolvedPersistentArtifactSources.fromJson(
      Map<String, dynamic> json) {
    return ResolvedPersistentArtifactSources(
      status: PersistentArtifactSourceResolutionStatusX.fromWireName(
          json['status'] as String),
      resolvedSources: List.unmodifiable(
          (json['resolvedSources'] as List<dynamic>? ?? [])
              .map((e) => e.toString())),
      unresolvedSources: List.unmodifiable(
          (json['unresolvedSources'] as List<dynamic>? ?? [])
              .map((e) => e.toString())),
      injectedSources: List.unmodifiable(
          (json['injectedSources'] as List<dynamic>? ?? [])
              .map((e) => e.toString())),
      sourceReferences: List.unmodifiable(
        (json['sourceReferences'] as List<dynamic>? ?? [])
            .map((e) => PersistentArtifactSourceReference.fromJson(
                e as Map<String, dynamic>))
            .toList(),
      ),
      messages: List.unmodifiable(
        (json['messages'] as List<dynamic>? ?? [])
            .map((e) => PersistentArtifactOperationMessage.fromJson(
                e as Map<String, dynamic>))
            .toList(),
      ),
      fingerprint: json['fingerprint'] as String?,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'status': status.wireName,
        if (resolvedSources.isNotEmpty)
          'resolvedSources': List<String>.from(resolvedSources)..sort(),
        if (unresolvedSources.isNotEmpty)
          'unresolvedSources': List<String>.from(unresolvedSources)..sort(),
        if (injectedSources.isNotEmpty)
          'injectedSources': List<String>.from(injectedSources)..sort(),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': paSortedComparableList(
              sourceReferences.map((e) => e.toComparableJson()), 'sourceId'),
        if (messages.isNotEmpty)
          'messages': paSortedComparableList(
              messages.map((e) => e.toComparableJson()), 'messageId'),
        if (fingerprint != null) 'fingerprint': fingerprint,
      };

  ResolvedPersistentArtifactSources copyWith({
    PersistentArtifactSourceResolutionStatus? status,
    List<String>? resolvedSources,
    List<String>? unresolvedSources,
    List<String>? injectedSources,
    List<PersistentArtifactSourceReference>? sourceReferences,
    List<PersistentArtifactOperationMessage>? messages,
    String? fingerprint,
  }) {
    return ResolvedPersistentArtifactSources(
      status: status ?? this.status,
      resolvedSources: resolvedSources ?? this.resolvedSources,
      unresolvedSources: unresolvedSources ?? this.unresolvedSources,
      injectedSources: injectedSources ?? this.injectedSources,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      messages: messages ?? this.messages,
      fingerprint: fingerprint ?? this.fingerprint,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedPersistentArtifactSources &&
          status == other.status &&
          paListEquals(resolvedSources, other.resolvedSources) &&
          paListEquals(unresolvedSources, other.unresolvedSources) &&
          paListEquals(injectedSources, other.injectedSources) &&
          paListEquals(sourceReferences, other.sourceReferences) &&
          paListEquals(messages, other.messages) &&
          fingerprint == other.fingerprint;

  @override
  int get hashCode => Object.hash(
        status,
        Object.hashAll(resolvedSources),
        Object.hashAll(unresolvedSources),
        Object.hashAll(injectedSources),
        Object.hashAll(sourceReferences),
        Object.hashAll(messages),
        fingerprint,
      );
}

class CollectedPersistentArtifactMaterial {
  const CollectedPersistentArtifactMaterial({
    this.subjects = const [],
    this.policies = const [],
    this.sourceReferences = const [],
    this.metadata = const {},
  });

  final List<PersistentArtifactSubject> subjects;
  final List<PersistentArtifactPolicyReference> policies;
  final List<PersistentArtifactSourceReference> sourceReferences;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        if (subjects.isNotEmpty)
          'subjects': subjects.map((e) => e.toJson()).toList(),
        if (policies.isNotEmpty)
          'policies': policies.map((e) => e.toJson()).toList(),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CollectedPersistentArtifactMaterial.fromJson(
      Map<String, dynamic> json) {
    return CollectedPersistentArtifactMaterial(
      subjects: List.unmodifiable(
        (json['subjects'] as List<dynamic>? ?? [])
            .map((e) =>
                PersistentArtifactSubject.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      policies: List.unmodifiable(
        (json['policies'] as List<dynamic>? ?? [])
            .map((e) => PersistentArtifactPolicyReference.fromJson(
                e as Map<String, dynamic>))
            .toList(),
      ),
      sourceReferences: List.unmodifiable(
        (json['sourceReferences'] as List<dynamic>? ?? [])
            .map((e) => PersistentArtifactSourceReference.fromJson(
                e as Map<String, dynamic>))
            .toList(),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        if (subjects.isNotEmpty)
          'subjects': paSortedComparableList(
              subjects.map((e) => e.toComparableJson()), 'subjectId'),
        if (policies.isNotEmpty)
          'policies': paSortedComparableList(
              policies.map((e) => e.toComparableJson()), 'policyId'),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': paSortedComparableList(
              sourceReferences.map((e) => e.toComparableJson()), 'sourceId'),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  CollectedPersistentArtifactMaterial copyWith({
    List<PersistentArtifactSubject>? subjects,
    List<PersistentArtifactPolicyReference>? policies,
    List<PersistentArtifactSourceReference>? sourceReferences,
    Map<String, String>? metadata,
  }) {
    return CollectedPersistentArtifactMaterial(
      subjects: subjects ?? this.subjects,
      policies: policies ?? this.policies,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CollectedPersistentArtifactMaterial &&
          paListEquals(subjects, other.subjects) &&
          paListEquals(policies, other.policies) &&
          paListEquals(sourceReferences, other.sourceReferences) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(subjects),
        Object.hashAll(policies),
        Object.hashAll(sourceReferences),
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactOperationContext {
  const PersistentArtifactOperationContext({
    required this.operation,
    required this.request,
    required this.sources,
    required this.material,
  });

  final PersistentArtifactOperationType operation;
  final PersistentArtifactEvaluationRequest request;
  final ResolvedPersistentArtifactSources sources;
  final CollectedPersistentArtifactMaterial material;

  Map<String, dynamic> toJson() => {
        'operation': operation.wireName,
        'request': request.toJson(),
        'sources': sources.toJson(),
        'material': material.toJson(),
      };

  factory PersistentArtifactOperationContext.fromJson(
      Map<String, dynamic> json) {
    return PersistentArtifactOperationContext(
      operation: PersistentArtifactOperationTypeX.fromWireName(
          json['operation'] as String),
      request: PersistentArtifactEvaluationRequest.fromJson(
          json['request'] as Map<String, dynamic>),
      sources: ResolvedPersistentArtifactSources.fromJson(
          json['sources'] as Map<String, dynamic>),
      material: CollectedPersistentArtifactMaterial.fromJson(
          json['material'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'operation': operation.wireName,
        'request': request.toComparableJson(),
        'sources': sources.toComparableJson(),
        'material': material.toComparableJson(),
      };

  PersistentArtifactOperationContext copyWith({
    PersistentArtifactOperationType? operation,
    PersistentArtifactEvaluationRequest? request,
    ResolvedPersistentArtifactSources? sources,
    CollectedPersistentArtifactMaterial? material,
  }) {
    return PersistentArtifactOperationContext(
      operation: operation ?? this.operation,
      request: request ?? this.request,
      sources: sources ?? this.sources,
      material: material ?? this.material,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactOperationContext &&
          operation == other.operation &&
          request == other.request &&
          sources == other.sources &&
          material == other.material;

  @override
  int get hashCode => Object.hash(operation, request, sources, material);
}

class PersistentArtifactSnapshotReference {
  const PersistentArtifactSnapshotReference({
    required this.snapshotId,
    required this.projectId,
    required this.fingerprint,
    this.releaseId,
    this.createdAt,
  });

  final String snapshotId;
  final String projectId;
  final String? releaseId;
  final String fingerprint;
  final String? createdAt;

  Map<String, dynamic> toJson() => {
        'snapshotId': snapshotId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'fingerprint': fingerprint,
        if (createdAt != null) 'createdAt': createdAt,
      };

  factory PersistentArtifactSnapshotReference.fromJson(
      Map<String, dynamic> json) {
    return PersistentArtifactSnapshotReference(
      snapshotId: json['snapshotId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      fingerprint: json['fingerprint'] as String,
      createdAt: json['createdAt'] as String?,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'snapshotId': snapshotId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'fingerprint': fingerprint,
      };

  PersistentArtifactSnapshotReference copyWith({
    String? snapshotId,
    String? projectId,
    String? releaseId,
    String? fingerprint,
    String? createdAt,
  }) {
    return PersistentArtifactSnapshotReference(
      snapshotId: snapshotId ?? this.snapshotId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      fingerprint: fingerprint ?? this.fingerprint,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactSnapshotReference &&
          snapshotId == other.snapshotId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          fingerprint == other.fingerprint &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      Object.hash(snapshotId, projectId, releaseId, fingerprint, createdAt);
}
