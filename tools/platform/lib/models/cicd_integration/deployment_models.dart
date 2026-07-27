import 'pipeline_equality.dart';
import 'pipeline_enums.dart';

/// Deployment target descriptor.
class DeploymentTarget {
  const DeploymentTarget({
    required this.targetId,
    required this.name,
    required this.targetType,
    required this.uri,
    this.region,
    this.metadata = const {},
  });

  final String targetId;
  final String name;
  final DeploymentTargetType targetType;
  final String uri;
  final String? region;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'targetId': targetId,
        'name': name,
        'targetType': targetType.wireName,
        'uri': uri,
        if (region != null) 'region': region,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory DeploymentTarget.fromJson(Map<String, dynamic> json) {
    return DeploymentTarget(
      targetId: json['targetId'] as String,
      name: json['name'] as String,
      targetType:
          DeploymentTargetTypeX.fromWireName(json['targetType'] as String),
      uri: json['uri'] as String,
      region: json['region'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'targetId': targetId,
        'name': name,
        'targetType': targetType.wireName,
        'uri': uri,
        if (region != null) 'region': region,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  DeploymentTarget copyWith({
    String? targetId,
    String? name,
    DeploymentTargetType? targetType,
    String? uri,
    String? region,
    Map<String, String>? metadata,
  }) {
    return DeploymentTarget(
      targetId: targetId ?? this.targetId,
      name: name ?? this.name,
      targetType: targetType ?? this.targetType,
      uri: uri ?? this.uri,
      region: region ?? this.region,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeploymentTarget &&
          targetId == other.targetId &&
          name == other.name &&
          targetType == other.targetType &&
          uri == other.uri &&
          region == other.region &&
          cicdMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(targetId, name, targetType, uri, region,
      Object.hashAll(metadata.entries));
}

/// Deployment approval gate descriptor.
class DeploymentApproval {
  const DeploymentApproval({
    required this.approvalId,
    required this.status,
    this.approver,
    this.approvedAt,
    this.expiresAt,
    this.metadata = const {},
  });

  final String approvalId;
  final DeploymentApprovalStatus status;
  final String? approver;
  final String? approvedAt;
  final String? expiresAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'approvalId': approvalId,
        'status': status.wireName,
        if (approver != null) 'approver': approver,
        if (approvedAt != null) 'approvedAt': approvedAt,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory DeploymentApproval.fromJson(Map<String, dynamic> json) {
    return DeploymentApproval(
      approvalId: json['approvalId'] as String,
      status: DeploymentApprovalStatusX.fromWireName(json['status'] as String),
      approver: json['approver'] as String?,
      approvedAt: json['approvedAt'] as String?,
      expiresAt: json['expiresAt'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'approvalId': approvalId,
        'status': status.wireName,
        if (approver != null) 'approver': approver,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  DeploymentApproval copyWith({
    String? approvalId,
    DeploymentApprovalStatus? status,
    String? approver,
    String? approvedAt,
    String? expiresAt,
    Map<String, String>? metadata,
  }) {
    return DeploymentApproval(
      approvalId: approvalId ?? this.approvalId,
      status: status ?? this.status,
      approver: approver ?? this.approver,
      approvedAt: approvedAt ?? this.approvedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeploymentApproval &&
          approvalId == other.approvalId &&
          status == other.status &&
          approver == other.approver &&
          approvedAt == other.approvedAt &&
          expiresAt == other.expiresAt &&
          cicdMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        approvalId,
        status,
        approver,
        approvedAt,
        expiresAt,
        Object.hashAll(metadata.entries),
      );
}

/// Allowed deployment time window.
class DeploymentWindow {
  const DeploymentWindow({
    required this.windowId,
    required this.startAt,
    required this.endAt,
    this.timezone = 'UTC',
    this.metadata = const {},
  });

  final String windowId;
  final String startAt;
  final String endAt;
  final String timezone;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'windowId': windowId,
        'startAt': startAt,
        'endAt': endAt,
        'timezone': timezone,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory DeploymentWindow.fromJson(Map<String, dynamic> json) {
    return DeploymentWindow(
      windowId: json['windowId'] as String,
      startAt: json['startAt'] as String,
      endAt: json['endAt'] as String,
      timezone: json['timezone'] as String? ?? 'UTC',
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'windowId': windowId,
        'startAt': startAt,
        'endAt': endAt,
        'timezone': timezone,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  DeploymentWindow copyWith({
    String? windowId,
    String? startAt,
    String? endAt,
    String? timezone,
    Map<String, String>? metadata,
  }) {
    return DeploymentWindow(
      windowId: windowId ?? this.windowId,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      timezone: timezone ?? this.timezone,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeploymentWindow &&
          windowId == other.windowId &&
          startAt == other.startAt &&
          endAt == other.endAt &&
          timezone == other.timezone &&
          cicdMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        windowId,
        startAt,
        endAt,
        timezone,
        Object.hashAll(metadata.entries),
      );
}

/// Deployment plan linking pipeline execution to targets.
class DeploymentPlan {
  const DeploymentPlan({
    required this.planId,
    required this.name,
    required this.strategy,
    this.targets = const [],
    this.approvals = const [],
    this.windows = const [],
    this.environmentId,
    this.pipelineExecutionId,
    this.fingerprint,
    this.metadata = const {},
    this.schemaVersion = currentSchemaVersion,
  });

  static const int currentSchemaVersion = 1;

  final String planId;
  final String name;
  final DeploymentStrategy strategy;
  final List<DeploymentTarget> targets;
  final List<DeploymentApproval> approvals;
  final List<DeploymentWindow> windows;
  final String? environmentId;
  final String? pipelineExecutionId;
  final String? fingerprint;
  final Map<String, String> metadata;
  final int schemaVersion;

  Map<String, dynamic> toJson() => {
        'planId': planId,
        'name': name,
        'strategy': strategy.wireName,
        if (targets.isNotEmpty)
          'targets': targets.map((e) => e.toJson()).toList(),
        if (approvals.isNotEmpty)
          'approvals': approvals.map((e) => e.toJson()).toList(),
        if (windows.isNotEmpty)
          'windows': windows.map((e) => e.toJson()).toList(),
        if (environmentId != null) 'environmentId': environmentId,
        if (pipelineExecutionId != null)
          'pipelineExecutionId': pipelineExecutionId,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (metadata.isNotEmpty) 'metadata': metadata,
        'schemaVersion': schemaVersion,
      };

  factory DeploymentPlan.fromJson(Map<String, dynamic> json) {
    return DeploymentPlan(
      planId: json['planId'] as String,
      name: json['name'] as String,
      strategy: DeploymentStrategyX.fromWireName(json['strategy'] as String),
      targets: List.unmodifiable(
        (json['targets'] as List<dynamic>? ?? [])
            .map((e) => DeploymentTarget.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      approvals: List.unmodifiable(
        (json['approvals'] as List<dynamic>? ?? [])
            .map((e) => DeploymentApproval.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      windows: List.unmodifiable(
        (json['windows'] as List<dynamic>? ?? [])
            .map((e) => DeploymentWindow.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      environmentId: json['environmentId'] as String?,
      pipelineExecutionId: json['pipelineExecutionId'] as String?,
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
        'planId': planId,
        'name': name,
        'strategy': strategy.wireName,
        if (targets.isNotEmpty)
          'targets': (targets.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) =>
                  (a['targetId'] as String).compareTo(b['targetId'] as String),
            )),
        if (approvals.isNotEmpty)
          'approvals': (approvals.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => (a['approvalId'] as String)
                  .compareTo(b['approvalId'] as String),
            )),
        if (windows.isNotEmpty)
          'windows': (windows.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) =>
                  (a['windowId'] as String).compareTo(b['windowId'] as String),
            )),
        if (environmentId != null) 'environmentId': environmentId,
        if (pipelineExecutionId != null)
          'pipelineExecutionId': pipelineExecutionId,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
        'schemaVersion': schemaVersion,
      };

  DeploymentPlan copyWith({
    String? planId,
    String? name,
    DeploymentStrategy? strategy,
    List<DeploymentTarget>? targets,
    List<DeploymentApproval>? approvals,
    List<DeploymentWindow>? windows,
    String? environmentId,
    String? pipelineExecutionId,
    String? fingerprint,
    Map<String, String>? metadata,
    int? schemaVersion,
  }) {
    return DeploymentPlan(
      planId: planId ?? this.planId,
      name: name ?? this.name,
      strategy: strategy ?? this.strategy,
      targets: targets ?? this.targets,
      approvals: approvals ?? this.approvals,
      windows: windows ?? this.windows,
      environmentId: environmentId ?? this.environmentId,
      pipelineExecutionId: pipelineExecutionId ?? this.pipelineExecutionId,
      fingerprint: fingerprint ?? this.fingerprint,
      metadata: metadata ?? this.metadata,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeploymentPlan &&
          planId == other.planId &&
          name == other.name &&
          strategy == other.strategy &&
          cicdListEquals(targets, other.targets) &&
          cicdListEquals(approvals, other.approvals) &&
          cicdListEquals(windows, other.windows) &&
          environmentId == other.environmentId &&
          pipelineExecutionId == other.pipelineExecutionId &&
          fingerprint == other.fingerprint &&
          cicdMapEquals(metadata, other.metadata) &&
          schemaVersion == other.schemaVersion;

  @override
  int get hashCode => Object.hash(
        planId,
        name,
        strategy,
        Object.hashAll(targets),
        Object.hashAll(approvals),
        Object.hashAll(windows),
        environmentId,
        pipelineExecutionId,
        fingerprint,
        Object.hashAll(metadata.entries),
        schemaVersion,
      );
}

/// Outcome of a deployment plan execution (domain descriptor).
class DeploymentResult {
  const DeploymentResult({
    required this.resultId,
    required this.planId,
    required this.status,
    required this.startedAt,
    this.completedAt,
    this.targetResults = const {},
    this.fingerprint,
    this.metadata = const {},
    this.schemaVersion = currentSchemaVersion,
  });

  static const int currentSchemaVersion = 1;

  final String resultId;
  final String planId;
  final DeploymentResultStatus status;
  final String startedAt;
  final String? completedAt;
  final Map<String, String> targetResults;
  final String? fingerprint;
  final Map<String, String> metadata;
  final int schemaVersion;

  Map<String, dynamic> toJson() => {
        'resultId': resultId,
        'planId': planId,
        'status': status.wireName,
        'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
        if (targetResults.isNotEmpty) 'targetResults': targetResults,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (metadata.isNotEmpty) 'metadata': metadata,
        'schemaVersion': schemaVersion,
      };

  factory DeploymentResult.fromJson(Map<String, dynamic> json) {
    return DeploymentResult(
      resultId: json['resultId'] as String,
      planId: json['planId'] as String,
      status: DeploymentResultStatusX.fromWireName(json['status'] as String),
      startedAt: json['startedAt'] as String,
      completedAt: json['completedAt'] as String?,
      targetResults: Map.unmodifiable(
        (json['targetResults'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
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
        'resultId': resultId,
        'planId': planId,
        'status': status.wireName,
        if (targetResults.isNotEmpty)
          'targetResults': Map.fromEntries(
            targetResults.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)),
          ),
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
        'schemaVersion': schemaVersion,
      };

  DeploymentResult copyWith({
    String? resultId,
    String? planId,
    DeploymentResultStatus? status,
    String? startedAt,
    String? completedAt,
    Map<String, String>? targetResults,
    String? fingerprint,
    Map<String, String>? metadata,
    int? schemaVersion,
  }) {
    return DeploymentResult(
      resultId: resultId ?? this.resultId,
      planId: planId ?? this.planId,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      targetResults: targetResults ?? this.targetResults,
      fingerprint: fingerprint ?? this.fingerprint,
      metadata: metadata ?? this.metadata,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeploymentResult &&
          resultId == other.resultId &&
          planId == other.planId &&
          status == other.status &&
          startedAt == other.startedAt &&
          completedAt == other.completedAt &&
          cicdMapEquals(targetResults, other.targetResults) &&
          fingerprint == other.fingerprint &&
          cicdMapEquals(metadata, other.metadata) &&
          schemaVersion == other.schemaVersion;

  @override
  int get hashCode => Object.hash(
        resultId,
        planId,
        status,
        startedAt,
        completedAt,
        Object.hashAll(targetResults.entries),
        fingerprint,
        Object.hashAll(metadata.entries),
        schemaVersion,
      );
}
