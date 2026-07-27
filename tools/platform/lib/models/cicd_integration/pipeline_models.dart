import 'pipeline_equality.dart';
import 'pipeline_enums.dart';

/// Atomic step within a pipeline stage.
class PipelineStep {
  const PipelineStep({
    required this.stepId,
    required this.name,
    required this.stepType,
    this.order = 0,
    this.dependsOn = const [],
    this.timeoutSeconds,
    this.optional = false,
    this.metadata = const {},
  });

  final String stepId;
  final String name;
  final PipelineStepType stepType;
  final int order;
  final List<String> dependsOn;
  final int? timeoutSeconds;
  final bool optional;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'stepId': stepId,
        'name': name,
        'stepType': stepType.wireName,
        'order': order,
        if (dependsOn.isNotEmpty) 'dependsOn': dependsOn,
        if (timeoutSeconds != null) 'timeoutSeconds': timeoutSeconds,
        'optional': optional,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PipelineStep.fromJson(Map<String, dynamic> json) {
    return PipelineStep(
      stepId: json['stepId'] as String,
      name: json['name'] as String,
      stepType: PipelineStepTypeX.fromWireName(json['stepType'] as String),
      order: json['order'] as int? ?? 0,
      dependsOn: List.unmodifiable(
        (json['dependsOn'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      timeoutSeconds: json['timeoutSeconds'] as int?,
      optional: json['optional'] as bool? ?? false,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'stepId': stepId,
        'name': name,
        'stepType': stepType.wireName,
        'order': order,
        'dependsOn': List<String>.from(dependsOn)..sort(),
        if (timeoutSeconds != null) 'timeoutSeconds': timeoutSeconds,
        'optional': optional,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  PipelineStep copyWith({
    String? stepId,
    String? name,
    PipelineStepType? stepType,
    int? order,
    List<String>? dependsOn,
    int? timeoutSeconds,
    bool? optional,
    Map<String, String>? metadata,
  }) {
    return PipelineStep(
      stepId: stepId ?? this.stepId,
      name: name ?? this.name,
      stepType: stepType ?? this.stepType,
      order: order ?? this.order,
      dependsOn: dependsOn ?? this.dependsOn,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      optional: optional ?? this.optional,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineStep &&
          stepId == other.stepId &&
          name == other.name &&
          stepType == other.stepType &&
          order == other.order &&
          cicdListEquals(dependsOn, other.dependsOn) &&
          timeoutSeconds == other.timeoutSeconds &&
          optional == other.optional &&
          cicdMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        stepId,
        name,
        stepType,
        order,
        Object.hashAll(dependsOn),
        timeoutSeconds,
        optional,
        Object.hashAll(metadata.entries),
      );
}

/// Stage grouping pipeline steps.
class PipelineStage {
  const PipelineStage({
    required this.stageId,
    required this.name,
    required this.stageType,
    this.order = 0,
    this.steps = const [],
    this.dependsOn = const [],
    this.metadata = const {},
  });

  final String stageId;
  final String name;
  final PipelineStageType stageType;
  final int order;
  final List<PipelineStep> steps;
  final List<String> dependsOn;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'stageId': stageId,
        'name': name,
        'stageType': stageType.wireName,
        'order': order,
        if (steps.isNotEmpty) 'steps': steps.map((e) => e.toJson()).toList(),
        if (dependsOn.isNotEmpty) 'dependsOn': dependsOn,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PipelineStage.fromJson(Map<String, dynamic> json) {
    return PipelineStage(
      stageId: json['stageId'] as String,
      name: json['name'] as String,
      stageType: PipelineStageTypeX.fromWireName(json['stageType'] as String),
      order: json['order'] as int? ?? 0,
      steps: List.unmodifiable(
        (json['steps'] as List<dynamic>? ?? [])
            .map((e) => PipelineStep.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      dependsOn: List.unmodifiable(
        (json['dependsOn'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'stageId': stageId,
        'name': name,
        'stageType': stageType.wireName,
        'order': order,
        if (steps.isNotEmpty)
          'steps': (steps.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) =>
                  (a['stepId'] as String).compareTo(b['stepId'] as String),
            )),
        'dependsOn': List<String>.from(dependsOn)..sort(),
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  PipelineStage copyWith({
    String? stageId,
    String? name,
    PipelineStageType? stageType,
    int? order,
    List<PipelineStep>? steps,
    List<String>? dependsOn,
    Map<String, String>? metadata,
  }) {
    return PipelineStage(
      stageId: stageId ?? this.stageId,
      name: name ?? this.name,
      stageType: stageType ?? this.stageType,
      order: order ?? this.order,
      steps: steps ?? this.steps,
      dependsOn: dependsOn ?? this.dependsOn,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineStage &&
          stageId == other.stageId &&
          name == other.name &&
          stageType == other.stageType &&
          order == other.order &&
          cicdListEquals(steps, other.steps) &&
          cicdListEquals(dependsOn, other.dependsOn) &&
          cicdMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        stageId,
        name,
        stageType,
        order,
        Object.hashAll(steps),
        Object.hashAll(dependsOn),
        Object.hashAll(metadata.entries),
      );
}

/// Trigger descriptor for pipeline execution (domain only).
class PipelineTrigger {
  const PipelineTrigger({
    required this.triggerId,
    required this.triggerType,
    this.enabled = true,
    this.configuration = const {},
    this.metadata = const {},
  });

  final String triggerId;
  final PipelineTriggerType triggerType;
  final bool enabled;
  final Map<String, String> configuration;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'triggerId': triggerId,
        'triggerType': triggerType.wireName,
        'enabled': enabled,
        if (configuration.isNotEmpty) 'configuration': configuration,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PipelineTrigger.fromJson(Map<String, dynamic> json) {
    return PipelineTrigger(
      triggerId: json['triggerId'] as String,
      triggerType:
          PipelineTriggerTypeX.fromWireName(json['triggerType'] as String),
      enabled: json['enabled'] as bool? ?? true,
      configuration: Map.unmodifiable(
        (json['configuration'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'triggerId': triggerId,
        'triggerType': triggerType.wireName,
        'enabled': enabled,
        if (configuration.isNotEmpty)
          'configuration': Map.fromEntries(
            configuration.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)),
          ),
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  PipelineTrigger copyWith({
    String? triggerId,
    PipelineTriggerType? triggerType,
    bool? enabled,
    Map<String, String>? configuration,
    Map<String, String>? metadata,
  }) {
    return PipelineTrigger(
      triggerId: triggerId ?? this.triggerId,
      triggerType: triggerType ?? this.triggerType,
      enabled: enabled ?? this.enabled,
      configuration: configuration ?? this.configuration,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineTrigger &&
          triggerId == other.triggerId &&
          triggerType == other.triggerType &&
          enabled == other.enabled &&
          cicdMapEquals(configuration, other.configuration) &&
          cicdMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        triggerId,
        triggerType,
        enabled,
        Object.hashAll(configuration.entries),
        Object.hashAll(metadata.entries),
      );
}

/// Artifact produced or consumed by a pipeline.
class PipelineArtifact {
  const PipelineArtifact({
    required this.artifactId,
    required this.name,
    required this.artifactType,
    this.uri,
    this.fingerprint,
    this.sizeBytes,
    this.mediaType,
    this.metadata = const {},
  });

  final String artifactId;
  final String name;
  final PipelineArtifactType artifactType;
  final String? uri;
  final String? fingerprint;
  final int? sizeBytes;
  final String? mediaType;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'artifactId': artifactId,
        'name': name,
        'artifactType': artifactType.wireName,
        if (uri != null) 'uri': uri,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (mediaType != null) 'mediaType': mediaType,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PipelineArtifact.fromJson(Map<String, dynamic> json) {
    return PipelineArtifact(
      artifactId: json['artifactId'] as String,
      name: json['name'] as String,
      artifactType:
          PipelineArtifactTypeX.fromWireName(json['artifactType'] as String),
      uri: json['uri'] as String?,
      fingerprint: json['fingerprint'] as String?,
      sizeBytes: json['sizeBytes'] as int?,
      mediaType: json['mediaType'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'artifactId': artifactId,
        'name': name,
        'artifactType': artifactType.wireName,
        if (uri != null) 'uri': uri,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (mediaType != null) 'mediaType': mediaType,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  PipelineArtifact copyWith({
    String? artifactId,
    String? name,
    PipelineArtifactType? artifactType,
    String? uri,
    String? fingerprint,
    int? sizeBytes,
    String? mediaType,
    Map<String, String>? metadata,
  }) {
    return PipelineArtifact(
      artifactId: artifactId ?? this.artifactId,
      name: name ?? this.name,
      artifactType: artifactType ?? this.artifactType,
      uri: uri ?? this.uri,
      fingerprint: fingerprint ?? this.fingerprint,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      mediaType: mediaType ?? this.mediaType,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineArtifact &&
          artifactId == other.artifactId &&
          name == other.name &&
          artifactType == other.artifactType &&
          uri == other.uri &&
          fingerprint == other.fingerprint &&
          sizeBytes == other.sizeBytes &&
          mediaType == other.mediaType &&
          cicdMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        artifactId,
        name,
        artifactType,
        uri,
        fingerprint,
        sizeBytes,
        mediaType,
        Object.hashAll(metadata.entries),
      );
}

/// Deployment or execution environment descriptor.
class PipelineEnvironment {
  const PipelineEnvironment({
    required this.environmentId,
    required this.name,
    required this.environmentType,
    this.variables = const {},
    this.metadata = const {},
  });

  final String environmentId;
  final String name;
  final PipelineEnvironmentType environmentType;
  final Map<String, String> variables;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'environmentId': environmentId,
        'name': name,
        'environmentType': environmentType.wireName,
        if (variables.isNotEmpty) 'variables': variables,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PipelineEnvironment.fromJson(Map<String, dynamic> json) {
    return PipelineEnvironment(
      environmentId: json['environmentId'] as String,
      name: json['name'] as String,
      environmentType: PipelineEnvironmentTypeX.fromWireName(
        json['environmentType'] as String,
      ),
      variables: Map.unmodifiable(
        (json['variables'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'environmentId': environmentId,
        'name': name,
        'environmentType': environmentType.wireName,
        if (variables.isNotEmpty)
          'variables': Map.fromEntries(
            variables.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  PipelineEnvironment copyWith({
    String? environmentId,
    String? name,
    PipelineEnvironmentType? environmentType,
    Map<String, String>? variables,
    Map<String, String>? metadata,
  }) {
    return PipelineEnvironment(
      environmentId: environmentId ?? this.environmentId,
      name: name ?? this.name,
      environmentType: environmentType ?? this.environmentType,
      variables: variables ?? this.variables,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineEnvironment &&
          environmentId == other.environmentId &&
          name == other.name &&
          environmentType == other.environmentType &&
          cicdMapEquals(variables, other.variables) &&
          cicdMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        environmentId,
        name,
        environmentType,
        Object.hashAll(variables.entries),
        Object.hashAll(metadata.entries),
      );
}

/// Terminal result of a pipeline execution.
class PipelineExecutionResult {
  const PipelineExecutionResult({
    required this.resultId,
    required this.outcome,
    required this.status,
    this.summary,
    this.artifactIds = const [],
    this.metrics = const {},
    this.fingerprint,
    this.completedAt,
  });

  final String resultId;
  final PipelineExecutionOutcome outcome;
  final PipelineStatus status;
  final String? summary;
  final List<String> artifactIds;
  final Map<String, String> metrics;
  final String? fingerprint;
  final String? completedAt;

  Map<String, dynamic> toJson() => {
        'resultId': resultId,
        'outcome': outcome.wireName,
        'status': status.wireName,
        if (summary != null) 'summary': summary,
        if (artifactIds.isNotEmpty) 'artifactIds': artifactIds,
        if (metrics.isNotEmpty) 'metrics': metrics,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (completedAt != null) 'completedAt': completedAt,
      };

  factory PipelineExecutionResult.fromJson(Map<String, dynamic> json) {
    return PipelineExecutionResult(
      resultId: json['resultId'] as String,
      outcome:
          PipelineExecutionOutcomeX.fromWireName(json['outcome'] as String),
      status: PipelineStatusX.fromWireName(json['status'] as String),
      summary: json['summary'] as String?,
      artifactIds: List.unmodifiable(
        (json['artifactIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      metrics: Map.unmodifiable(
        (json['metrics'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      fingerprint: json['fingerprint'] as String?,
      completedAt: json['completedAt'] as String?,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'resultId': resultId,
        'outcome': outcome.wireName,
        'status': status.wireName,
        if (summary != null) 'summary': summary,
        'artifactIds': List<String>.from(artifactIds)..sort(),
        if (metrics.isNotEmpty)
          'metrics': Map.fromEntries(
            metrics.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
        if (fingerprint != null) 'fingerprint': fingerprint,
      };

  PipelineExecutionResult copyWith({
    String? resultId,
    PipelineExecutionOutcome? outcome,
    PipelineStatus? status,
    String? summary,
    List<String>? artifactIds,
    Map<String, String>? metrics,
    String? fingerprint,
    String? completedAt,
  }) {
    return PipelineExecutionResult(
      resultId: resultId ?? this.resultId,
      outcome: outcome ?? this.outcome,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      artifactIds: artifactIds ?? this.artifactIds,
      metrics: metrics ?? this.metrics,
      fingerprint: fingerprint ?? this.fingerprint,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineExecutionResult &&
          resultId == other.resultId &&
          outcome == other.outcome &&
          status == other.status &&
          summary == other.summary &&
          cicdListEquals(artifactIds, other.artifactIds) &&
          cicdMapEquals(metrics, other.metrics) &&
          fingerprint == other.fingerprint &&
          completedAt == other.completedAt;

  @override
  int get hashCode => Object.hash(
        resultId,
        outcome,
        status,
        summary,
        Object.hashAll(artifactIds),
        Object.hashAll(metrics.entries),
        fingerprint,
        completedAt,
      );
}

/// Record of a single pipeline execution (domain descriptor — not a live run).
class PipelineExecution {
  const PipelineExecution({
    required this.executionId,
    required this.definitionId,
    required this.status,
    required this.startedAt,
    this.definitionVersion,
    this.definitionFingerprint,
    this.triggerId,
    this.environmentId,
    this.completedAt,
    this.result,
    this.artifacts = const [],
    this.fingerprint,
    this.metadata = const {},
    this.schemaVersion = currentSchemaVersion,
  });

  static const int currentSchemaVersion = 1;

  final String executionId;
  final String definitionId;
  final int? definitionVersion;
  final String? definitionFingerprint;
  final String? triggerId;
  final String? environmentId;
  final PipelineStatus status;
  final String startedAt;
  final String? completedAt;
  final PipelineExecutionResult? result;
  final List<PipelineArtifact> artifacts;
  final String? fingerprint;
  final Map<String, String> metadata;
  final int schemaVersion;

  Map<String, dynamic> toJson() => {
        'executionId': executionId,
        'definitionId': definitionId,
        if (definitionVersion != null) 'definitionVersion': definitionVersion,
        if (definitionFingerprint != null)
          'definitionFingerprint': definitionFingerprint,
        if (triggerId != null) 'triggerId': triggerId,
        if (environmentId != null) 'environmentId': environmentId,
        'status': status.wireName,
        'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
        if (result != null) 'result': result!.toJson(),
        if (artifacts.isNotEmpty)
          'artifacts': artifacts.map((e) => e.toJson()).toList(),
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (metadata.isNotEmpty) 'metadata': metadata,
        'schemaVersion': schemaVersion,
      };

  factory PipelineExecution.fromJson(Map<String, dynamic> json) {
    return PipelineExecution(
      executionId: json['executionId'] as String,
      definitionId: json['definitionId'] as String,
      definitionVersion: json['definitionVersion'] as int?,
      definitionFingerprint: json['definitionFingerprint'] as String?,
      triggerId: json['triggerId'] as String?,
      environmentId: json['environmentId'] as String?,
      status: PipelineStatusX.fromWireName(json['status'] as String),
      startedAt: json['startedAt'] as String,
      completedAt: json['completedAt'] as String?,
      result: json['result'] == null
          ? null
          : PipelineExecutionResult.fromJson(
              json['result'] as Map<String, dynamic>,
            ),
      artifacts: List.unmodifiable(
        (json['artifacts'] as List<dynamic>? ?? [])
            .map((e) => PipelineArtifact.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      fingerprint: json['fingerprint'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'executionId': executionId,
        'definitionId': definitionId,
        if (definitionVersion != null) 'definitionVersion': definitionVersion,
        if (definitionFingerprint != null)
          'definitionFingerprint': definitionFingerprint,
        if (triggerId != null) 'triggerId': triggerId,
        if (environmentId != null) 'environmentId': environmentId,
        'status': status.wireName,
        if (result != null) 'result': result!.toComparableJson(),
        if (artifacts.isNotEmpty)
          'artifacts': (artifacts.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => (a['artifactId'] as String)
                  .compareTo(b['artifactId'] as String),
            )),
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
        'schemaVersion': schemaVersion,
      };

  PipelineExecution copyWith({
    String? executionId,
    String? definitionId,
    int? definitionVersion,
    String? definitionFingerprint,
    String? triggerId,
    String? environmentId,
    PipelineStatus? status,
    String? startedAt,
    String? completedAt,
    PipelineExecutionResult? result,
    List<PipelineArtifact>? artifacts,
    String? fingerprint,
    Map<String, String>? metadata,
    int? schemaVersion,
  }) {
    return PipelineExecution(
      executionId: executionId ?? this.executionId,
      definitionId: definitionId ?? this.definitionId,
      definitionVersion: definitionVersion ?? this.definitionVersion,
      definitionFingerprint:
          definitionFingerprint ?? this.definitionFingerprint,
      triggerId: triggerId ?? this.triggerId,
      environmentId: environmentId ?? this.environmentId,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      result: result ?? this.result,
      artifacts: artifacts ?? this.artifacts,
      fingerprint: fingerprint ?? this.fingerprint,
      metadata: metadata ?? this.metadata,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineExecution &&
          executionId == other.executionId &&
          definitionId == other.definitionId &&
          definitionVersion == other.definitionVersion &&
          definitionFingerprint == other.definitionFingerprint &&
          triggerId == other.triggerId &&
          environmentId == other.environmentId &&
          status == other.status &&
          startedAt == other.startedAt &&
          completedAt == other.completedAt &&
          result == other.result &&
          cicdListEquals(artifacts, other.artifacts) &&
          fingerprint == other.fingerprint &&
          cicdMapEquals(metadata, other.metadata) &&
          schemaVersion == other.schemaVersion;

  @override
  int get hashCode => Object.hash(
        executionId,
        definitionId,
        definitionVersion,
        definitionFingerprint,
        triggerId,
        environmentId,
        status,
        startedAt,
        completedAt,
        result,
        Object.hashAll(artifacts),
        fingerprint,
        Object.hashAll(metadata.entries),
        schemaVersion,
      );
}

/// Canonical pipeline definition (domain descriptor — no execution).
class PipelineDefinition {
  const PipelineDefinition({
    required this.definitionId,
    required this.name,
    required this.version,
    this.stages = const [],
    this.triggers = const [],
    this.environments = const [],
    this.artifacts = const [],
    this.fingerprint,
    this.metadata = const {},
    this.schemaVersion = currentSchemaVersion,
    this.canonicalizationVersion = currentCanonicalizationVersion,
  });

  static const int currentSchemaVersion = 1;
  static const int currentCanonicalizationVersion = 1;

  final String definitionId;
  final String name;
  final int version;
  final List<PipelineStage> stages;
  final List<PipelineTrigger> triggers;
  final List<PipelineEnvironment> environments;
  final List<PipelineArtifact> artifacts;
  final String? fingerprint;
  final Map<String, String> metadata;
  final int schemaVersion;
  final int canonicalizationVersion;

  Map<String, dynamic> toJson() => {
        'definitionId': definitionId,
        'name': name,
        'version': version,
        if (stages.isNotEmpty) 'stages': stages.map((e) => e.toJson()).toList(),
        if (triggers.isNotEmpty)
          'triggers': triggers.map((e) => e.toJson()).toList(),
        if (environments.isNotEmpty)
          'environments': environments.map((e) => e.toJson()).toList(),
        if (artifacts.isNotEmpty)
          'artifacts': artifacts.map((e) => e.toJson()).toList(),
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (metadata.isNotEmpty) 'metadata': metadata,
        'schemaVersion': schemaVersion,
        'canonicalizationVersion': canonicalizationVersion,
      };

  factory PipelineDefinition.fromJson(Map<String, dynamic> json) {
    return PipelineDefinition(
      definitionId: json['definitionId'] as String,
      name: json['name'] as String,
      version: json['version'] as int,
      stages: List.unmodifiable(
        (json['stages'] as List<dynamic>? ?? [])
            .map((e) => PipelineStage.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      triggers: List.unmodifiable(
        (json['triggers'] as List<dynamic>? ?? [])
            .map((e) => PipelineTrigger.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      environments: List.unmodifiable(
        (json['environments'] as List<dynamic>? ?? [])
            .map(
              (e) => PipelineEnvironment.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
      artifacts: List.unmodifiable(
        (json['artifacts'] as List<dynamic>? ?? [])
            .map((e) => PipelineArtifact.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      fingerprint: json['fingerprint'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      canonicalizationVersion: json['canonicalizationVersion'] as int? ??
          currentCanonicalizationVersion,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'definitionId': definitionId,
        'name': name,
        'version': version,
        if (stages.isNotEmpty)
          'stages': (stages.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) =>
                  (a['stageId'] as String).compareTo(b['stageId'] as String),
            )),
        if (triggers.isNotEmpty)
          'triggers': (triggers.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => (a['triggerId'] as String)
                  .compareTo(b['triggerId'] as String),
            )),
        if (environments.isNotEmpty)
          'environments':
              (environments.map((e) => e.toComparableJson()).toList()
                ..sort(
                  (a, b) => (a['environmentId'] as String)
                      .compareTo(b['environmentId'] as String),
                )),
        if (artifacts.isNotEmpty)
          'artifacts': (artifacts.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => (a['artifactId'] as String)
                  .compareTo(b['artifactId'] as String),
            )),
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
        'schemaVersion': schemaVersion,
        'canonicalizationVersion': canonicalizationVersion,
      };

  PipelineDefinition copyWith({
    String? definitionId,
    String? name,
    int? version,
    List<PipelineStage>? stages,
    List<PipelineTrigger>? triggers,
    List<PipelineEnvironment>? environments,
    List<PipelineArtifact>? artifacts,
    String? fingerprint,
    Map<String, String>? metadata,
    int? schemaVersion,
    int? canonicalizationVersion,
  }) {
    return PipelineDefinition(
      definitionId: definitionId ?? this.definitionId,
      name: name ?? this.name,
      version: version ?? this.version,
      stages: stages ?? this.stages,
      triggers: triggers ?? this.triggers,
      environments: environments ?? this.environments,
      artifacts: artifacts ?? this.artifacts,
      fingerprint: fingerprint ?? this.fingerprint,
      metadata: metadata ?? this.metadata,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      canonicalizationVersion:
          canonicalizationVersion ?? this.canonicalizationVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineDefinition &&
          definitionId == other.definitionId &&
          name == other.name &&
          version == other.version &&
          cicdListEquals(stages, other.stages) &&
          cicdListEquals(triggers, other.triggers) &&
          cicdListEquals(environments, other.environments) &&
          cicdListEquals(artifacts, other.artifacts) &&
          fingerprint == other.fingerprint &&
          cicdMapEquals(metadata, other.metadata) &&
          schemaVersion == other.schemaVersion &&
          canonicalizationVersion == other.canonicalizationVersion;

  @override
  int get hashCode => Object.hash(
        definitionId,
        name,
        version,
        Object.hashAll(stages),
        Object.hashAll(triggers),
        Object.hashAll(environments),
        Object.hashAll(artifacts),
        fingerprint,
        Object.hashAll(metadata.entries),
        schemaVersion,
        canonicalizationVersion,
      );
}
