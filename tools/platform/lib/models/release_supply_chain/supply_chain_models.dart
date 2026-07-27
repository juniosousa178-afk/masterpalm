import 'release_supply_chain_enums.dart';
import 'release_supply_chain_equality.dart';

/// Actor participating in a supply chain stage.
class SupplyChainActor {
  const SupplyChainActor({
    required this.actorId,
    required this.actorType,
    required this.name,
    this.uri,
    this.metadata = const {},
  });

  final String actorId;
  final SupplyChainActorType actorType;
  final String name;
  final String? uri;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'actorId': actorId,
        'actorType': actorType.wireName,
        'name': name,
        if (uri != null) 'uri': uri,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory SupplyChainActor.fromJson(Map<String, dynamic> json) {
    return SupplyChainActor(
      actorId: json['actorId'] as String,
      actorType:
          SupplyChainActorTypeX.fromWireName(json['actorType'] as String),
      name: json['name'] as String,
      uri: json['uri'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'actorId': actorId,
        'actorType': actorType.wireName,
        'name': name,
        if (uri != null) 'uri': uri,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  SupplyChainActor copyWith({
    String? actorId,
    SupplyChainActorType? actorType,
    String? name,
    String? uri,
    Map<String, String>? metadata,
  }) {
    return SupplyChainActor(
      actorId: actorId ?? this.actorId,
      actorType: actorType ?? this.actorType,
      name: name ?? this.name,
      uri: uri ?? this.uri,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupplyChainActor &&
          actorId == other.actorId &&
          actorType == other.actorType &&
          name == other.name &&
          uri == other.uri &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
      actorId, actorType, name, uri, Object.hashAll(metadata.entries));
}

/// Stage within a supply chain graph.
class SupplyChainStage {
  const SupplyChainStage({
    required this.stageId,
    required this.stageType,
    required this.name,
    required this.actorId,
    this.startedAt,
    this.completedAt,
    this.inputArtifactIds = const [],
    this.outputArtifactIds = const [],
    this.metadata = const {},
  });

  final String stageId;
  final SupplyChainStageType stageType;
  final String name;
  final String actorId;
  final String? startedAt;
  final String? completedAt;
  final List<String> inputArtifactIds;
  final List<String> outputArtifactIds;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'stageId': stageId,
        'stageType': stageType.wireName,
        'name': name,
        'actorId': actorId,
        if (startedAt != null) 'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
        if (inputArtifactIds.isNotEmpty) 'inputArtifactIds': inputArtifactIds,
        if (outputArtifactIds.isNotEmpty)
          'outputArtifactIds': outputArtifactIds,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory SupplyChainStage.fromJson(Map<String, dynamic> json) {
    return SupplyChainStage(
      stageId: json['stageId'] as String,
      stageType:
          SupplyChainStageTypeX.fromWireName(json['stageType'] as String),
      name: json['name'] as String,
      actorId: json['actorId'] as String,
      startedAt: json['startedAt'] as String?,
      completedAt: json['completedAt'] as String?,
      inputArtifactIds: List.unmodifiable(
        (json['inputArtifactIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      outputArtifactIds: List.unmodifiable(
        (json['outputArtifactIds'] as List<dynamic>? ?? [])
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
        'stageType': stageType.wireName,
        'name': name,
        'actorId': actorId,
        if (startedAt != null) 'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
        'inputArtifactIds': List<String>.from(inputArtifactIds)..sort(),
        'outputArtifactIds': List<String>.from(outputArtifactIds)..sort(),
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  SupplyChainStage copyWith({
    String? stageId,
    SupplyChainStageType? stageType,
    String? name,
    String? actorId,
    String? startedAt,
    String? completedAt,
    List<String>? inputArtifactIds,
    List<String>? outputArtifactIds,
    Map<String, String>? metadata,
  }) {
    return SupplyChainStage(
      stageId: stageId ?? this.stageId,
      stageType: stageType ?? this.stageType,
      name: name ?? this.name,
      actorId: actorId ?? this.actorId,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      inputArtifactIds: inputArtifactIds ?? this.inputArtifactIds,
      outputArtifactIds: outputArtifactIds ?? this.outputArtifactIds,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupplyChainStage &&
          stageId == other.stageId &&
          stageType == other.stageType &&
          name == other.name &&
          actorId == other.actorId &&
          startedAt == other.startedAt &&
          completedAt == other.completedAt &&
          rscListEquals(inputArtifactIds, other.inputArtifactIds) &&
          rscListEquals(outputArtifactIds, other.outputArtifactIds) &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        stageId,
        stageType,
        name,
        actorId,
        startedAt,
        completedAt,
        Object.hashAll(inputArtifactIds),
        Object.hashAll(outputArtifactIds),
        Object.hashAll(metadata.entries),
      );
}

/// Node in a supply chain graph.
class SupplyChainNode {
  const SupplyChainNode({
    required this.nodeId,
    required this.stageId,
    required this.artifactId,
    required this.fingerprint,
    this.label,
    this.metadata = const {},
  });

  final String nodeId;
  final String stageId;
  final String artifactId;
  final String fingerprint;
  final String? label;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'stageId': stageId,
        'artifactId': artifactId,
        'fingerprint': fingerprint,
        if (label != null) 'label': label,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory SupplyChainNode.fromJson(Map<String, dynamic> json) {
    return SupplyChainNode(
      nodeId: json['nodeId'] as String,
      stageId: json['stageId'] as String,
      artifactId: json['artifactId'] as String,
      fingerprint: json['fingerprint'] as String,
      label: json['label'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'nodeId': nodeId,
        'stageId': stageId,
        'artifactId': artifactId,
        'fingerprint': fingerprint,
        if (label != null) 'label': label,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  SupplyChainNode copyWith({
    String? nodeId,
    String? stageId,
    String? artifactId,
    String? fingerprint,
    String? label,
    Map<String, String>? metadata,
  }) {
    return SupplyChainNode(
      nodeId: nodeId ?? this.nodeId,
      stageId: stageId ?? this.stageId,
      artifactId: artifactId ?? this.artifactId,
      fingerprint: fingerprint ?? this.fingerprint,
      label: label ?? this.label,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupplyChainNode &&
          nodeId == other.nodeId &&
          stageId == other.stageId &&
          artifactId == other.artifactId &&
          fingerprint == other.fingerprint &&
          label == other.label &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        nodeId,
        stageId,
        artifactId,
        fingerprint,
        label,
        Object.hashAll(metadata.entries),
      );
}

/// Directed edge in a supply chain graph.
class SupplyChainEdge {
  const SupplyChainEdge({
    required this.edgeId,
    required this.fromNodeId,
    required this.toNodeId,
    this.relationType,
    this.metadata = const {},
  });

  final String edgeId;
  final String fromNodeId;
  final String toNodeId;
  final String? relationType;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'edgeId': edgeId,
        'fromNodeId': fromNodeId,
        'toNodeId': toNodeId,
        if (relationType != null) 'relationType': relationType,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory SupplyChainEdge.fromJson(Map<String, dynamic> json) {
    return SupplyChainEdge(
      edgeId: json['edgeId'] as String,
      fromNodeId: json['fromNodeId'] as String,
      toNodeId: json['toNodeId'] as String,
      relationType: json['relationType'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'edgeId': edgeId,
        'fromNodeId': fromNodeId,
        'toNodeId': toNodeId,
        if (relationType != null) 'relationType': relationType,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  SupplyChainEdge copyWith({
    String? edgeId,
    String? fromNodeId,
    String? toNodeId,
    String? relationType,
    Map<String, String>? metadata,
  }) {
    return SupplyChainEdge(
      edgeId: edgeId ?? this.edgeId,
      fromNodeId: fromNodeId ?? this.fromNodeId,
      toNodeId: toNodeId ?? this.toNodeId,
      relationType: relationType ?? this.relationType,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupplyChainEdge &&
          edgeId == other.edgeId &&
          fromNodeId == other.fromNodeId &&
          toNodeId == other.toNodeId &&
          relationType == other.relationType &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        edgeId,
        fromNodeId,
        toNodeId,
        relationType,
        Object.hashAll(metadata.entries),
      );
}

/// Evidence reference attached to a supply chain record.
class SupplyChainEvidence {
  const SupplyChainEvidence({
    required this.evidenceId,
    required this.artifactId,
    required this.fingerprint,
    required this.evidenceType,
    this.snapshotId,
    this.description,
    this.metadata = const {},
  });

  final String evidenceId;
  final String artifactId;
  final String fingerprint;
  final String evidenceType;
  final String? snapshotId;
  final String? description;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'evidenceId': evidenceId,
        'artifactId': artifactId,
        'fingerprint': fingerprint,
        'evidenceType': evidenceType,
        if (snapshotId != null) 'snapshotId': snapshotId,
        if (description != null) 'description': description,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory SupplyChainEvidence.fromJson(Map<String, dynamic> json) {
    return SupplyChainEvidence(
      evidenceId: json['evidenceId'] as String,
      artifactId: json['artifactId'] as String,
      fingerprint: json['fingerprint'] as String,
      evidenceType: json['evidenceType'] as String,
      snapshotId: json['snapshotId'] as String?,
      description: json['description'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'evidenceId': evidenceId,
        'artifactId': artifactId,
        'fingerprint': fingerprint,
        'evidenceType': evidenceType,
        if (snapshotId != null) 'snapshotId': snapshotId,
        if (description != null) 'description': description,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  SupplyChainEvidence copyWith({
    String? evidenceId,
    String? artifactId,
    String? fingerprint,
    String? evidenceType,
    String? snapshotId,
    String? description,
    Map<String, String>? metadata,
  }) {
    return SupplyChainEvidence(
      evidenceId: evidenceId ?? this.evidenceId,
      artifactId: artifactId ?? this.artifactId,
      fingerprint: fingerprint ?? this.fingerprint,
      evidenceType: evidenceType ?? this.evidenceType,
      snapshotId: snapshotId ?? this.snapshotId,
      description: description ?? this.description,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupplyChainEvidence &&
          evidenceId == other.evidenceId &&
          artifactId == other.artifactId &&
          fingerprint == other.fingerprint &&
          evidenceType == other.evidenceType &&
          snapshotId == other.snapshotId &&
          description == other.description &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        evidenceId,
        artifactId,
        fingerprint,
        evidenceType,
        snapshotId,
        description,
        Object.hashAll(metadata.entries),
      );
}

/// Policy governing supply chain record requirements.
class SupplyChainPolicy {
  const SupplyChainPolicy({
    required this.policyId,
    required this.policyVersion,
    required this.name,
    required this.requiredStageTypes,
    this.minimumEvidenceCount = 0,
    this.limitations = const [],
  });

  final String policyId;
  final int policyVersion;
  final String name;
  final List<SupplyChainStageType> requiredStageTypes;
  final int minimumEvidenceCount;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'name': name,
        'requiredStageTypes': requiredStageTypes.map((e) => e.wireName).toList()
          ..sort(),
        'minimumEvidenceCount': minimumEvidenceCount,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory SupplyChainPolicy.fromJson(Map<String, dynamic> json) {
    return SupplyChainPolicy(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      name: json['name'] as String,
      requiredStageTypes: List.unmodifiable(
        (json['requiredStageTypes'] as List<dynamic>)
            .map(
              (e) => SupplyChainStageTypeX.fromWireName(e.toString()),
            )
            .toList()
          ..sort((a, b) => a.wireName.compareTo(b.wireName)),
      ),
      minimumEvidenceCount: json['minimumEvidenceCount'] as int? ?? 0,
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'name': name,
        'requiredStageTypes': requiredStageTypes.map((e) => e.wireName).toList()
          ..sort(),
        'minimumEvidenceCount': minimumEvidenceCount,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  SupplyChainPolicy copyWith({
    String? policyId,
    int? policyVersion,
    String? name,
    List<SupplyChainStageType>? requiredStageTypes,
    int? minimumEvidenceCount,
    List<String>? limitations,
  }) {
    return SupplyChainPolicy(
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      name: name ?? this.name,
      requiredStageTypes: requiredStageTypes ?? this.requiredStageTypes,
      minimumEvidenceCount: minimumEvidenceCount ?? this.minimumEvidenceCount,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupplyChainPolicy &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          name == other.name &&
          rscListEquals(requiredStageTypes, other.requiredStageTypes) &&
          minimumEvidenceCount == other.minimumEvidenceCount &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        policyId,
        policyVersion,
        name,
        Object.hashAll(requiredStageTypes),
        minimumEvidenceCount,
        Object.hashAll(limitations),
      );
}

/// Immutable supply chain record aggregating stages, nodes and evidence.
class SupplyChainRecord {
  const SupplyChainRecord({
    required this.recordId,
    required this.projectId,
    required this.status,
    required this.fingerprint,
    required this.policy,
    required this.actors,
    required this.stages,
    required this.nodes,
    required this.edges,
    required this.evidence,
    required this.schemaVersion,
    required this.createdAt,
    required this.recordedAt,
    this.releaseId,
    this.commitId,
    this.provenanceRecordId,
    this.releaseEvidenceBundleId,
    this.warnings = const [],
    this.limitations = const [],
  });

  static const int currentSchemaVersion = 1;

  final String recordId;
  final String projectId;
  final String? releaseId;
  final String? commitId;
  final String? provenanceRecordId;
  final String? releaseEvidenceBundleId;
  final SupplyChainStatus status;
  final String fingerprint;
  final SupplyChainPolicy policy;
  final List<SupplyChainActor> actors;
  final List<SupplyChainStage> stages;
  final List<SupplyChainNode> nodes;
  final List<SupplyChainEdge> edges;
  final List<SupplyChainEvidence> evidence;
  final int schemaVersion;
  final String createdAt;
  final String recordedAt;
  final List<String> warnings;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'recordId': recordId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (provenanceRecordId != null)
          'provenanceRecordId': provenanceRecordId,
        if (releaseEvidenceBundleId != null)
          'releaseEvidenceBundleId': releaseEvidenceBundleId,
        'status': status.wireName,
        'fingerprint': fingerprint,
        'policy': policy.toJson(),
        'actors': actors.map((e) => e.toJson()).toList(),
        'stages': stages.map((e) => e.toJson()).toList(),
        'nodes': nodes.map((e) => e.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'schemaVersion': schemaVersion,
        'createdAt': createdAt,
        'recordedAt': recordedAt,
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory SupplyChainRecord.fromJson(Map<String, dynamic> json) {
    return SupplyChainRecord(
      recordId: json['recordId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      commitId: json['commitId'] as String?,
      provenanceRecordId: json['provenanceRecordId'] as String?,
      releaseEvidenceBundleId: json['releaseEvidenceBundleId'] as String?,
      status: SupplyChainStatusX.fromWireName(json['status'] as String),
      fingerprint: json['fingerprint'] as String,
      policy:
          SupplyChainPolicy.fromJson(json['policy'] as Map<String, dynamic>),
      actors: List.unmodifiable(
        (json['actors'] as List<dynamic>)
            .map((e) => SupplyChainActor.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      stages: List.unmodifiable(
        (json['stages'] as List<dynamic>)
            .map((e) => SupplyChainStage.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      nodes: List.unmodifiable(
        (json['nodes'] as List<dynamic>)
            .map((e) => SupplyChainNode.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      edges: List.unmodifiable(
        (json['edges'] as List<dynamic>)
            .map((e) => SupplyChainEdge.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      evidence: List.unmodifiable(
        (json['evidence'] as List<dynamic>)
            .map(
              (e) => SupplyChainEvidence.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      createdAt: json['createdAt'] as String,
      recordedAt: json['recordedAt'] as String,
      warnings: List.unmodifiable(
        (json['warnings'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() {
    return {
      'projectId': projectId,
      if (releaseId != null) 'releaseId': releaseId,
      if (commitId != null) 'commitId': commitId,
      if (provenanceRecordId != null) 'provenanceRecordId': provenanceRecordId,
      if (releaseEvidenceBundleId != null)
        'releaseEvidenceBundleId': releaseEvidenceBundleId,
      'status': status.wireName,
      'policy': policy.toComparableJson(),
      'actors': (actors.map((e) => e.toComparableJson()).toList()
        ..sort((a, b) =>
            (a['actorId'] as String).compareTo(b['actorId'] as String))),
      'stages': (stages.map((e) => e.toComparableJson()).toList()
        ..sort((a, b) =>
            (a['stageId'] as String).compareTo(b['stageId'] as String))),
      'nodes': (nodes.map((e) => e.toComparableJson()).toList()
        ..sort((a, b) =>
            (a['nodeId'] as String).compareTo(b['nodeId'] as String))),
      'edges': (edges.map((e) => e.toComparableJson()).toList()
        ..sort((a, b) =>
            (a['edgeId'] as String).compareTo(b['edgeId'] as String))),
      'evidence': (evidence.map((e) => e.toComparableJson()).toList()
        ..sort(
          (a, b) =>
              (a['evidenceId'] as String).compareTo(b['evidenceId'] as String),
        )),
      'schemaVersion': schemaVersion,
      if (warnings.isNotEmpty) 'warnings': List<String>.from(warnings)..sort(),
      if (limitations.isNotEmpty)
        'limitations': List<String>.from(limitations)..sort(),
    };
  }

  SupplyChainRecord copyWith({
    String? recordId,
    String? projectId,
    String? releaseId,
    String? commitId,
    String? provenanceRecordId,
    String? releaseEvidenceBundleId,
    SupplyChainStatus? status,
    String? fingerprint,
    SupplyChainPolicy? policy,
    List<SupplyChainActor>? actors,
    List<SupplyChainStage>? stages,
    List<SupplyChainNode>? nodes,
    List<SupplyChainEdge>? edges,
    List<SupplyChainEvidence>? evidence,
    int? schemaVersion,
    String? createdAt,
    String? recordedAt,
    List<String>? warnings,
    List<String>? limitations,
  }) {
    return SupplyChainRecord(
      recordId: recordId ?? this.recordId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      commitId: commitId ?? this.commitId,
      provenanceRecordId: provenanceRecordId ?? this.provenanceRecordId,
      releaseEvidenceBundleId:
          releaseEvidenceBundleId ?? this.releaseEvidenceBundleId,
      status: status ?? this.status,
      fingerprint: fingerprint ?? this.fingerprint,
      policy: policy ?? this.policy,
      actors: actors ?? this.actors,
      stages: stages ?? this.stages,
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      evidence: evidence ?? this.evidence,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAt: createdAt ?? this.createdAt,
      recordedAt: recordedAt ?? this.recordedAt,
      warnings: warnings ?? this.warnings,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupplyChainRecord &&
          recordId == other.recordId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          commitId == other.commitId &&
          provenanceRecordId == other.provenanceRecordId &&
          releaseEvidenceBundleId == other.releaseEvidenceBundleId &&
          status == other.status &&
          fingerprint == other.fingerprint &&
          policy == other.policy &&
          rscListEquals(actors, other.actors) &&
          rscListEquals(stages, other.stages) &&
          rscListEquals(nodes, other.nodes) &&
          rscListEquals(edges, other.edges) &&
          rscListEquals(evidence, other.evidence) &&
          schemaVersion == other.schemaVersion &&
          createdAt == other.createdAt &&
          recordedAt == other.recordedAt &&
          rscListEquals(warnings, other.warnings) &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        recordId,
        projectId,
        releaseId,
        commitId,
        provenanceRecordId,
        releaseEvidenceBundleId,
        status,
        fingerprint,
        policy,
        Object.hashAll(actors),
        Object.hashAll(stages),
        Object.hashAll(nodes),
        Object.hashAll(edges),
        Object.hashAll(evidence),
        schemaVersion,
        createdAt,
        recordedAt,
        Object.hashAll(warnings),
        Object.hashAll(limitations),
      );
}
