import 'pipeline_equality.dart';
import 'pipeline_enums.dart';

/// External reference to a CI/CD provider resource (domain descriptor only).
class PipelineReference {
  const PipelineReference({
    required this.referenceId,
    required this.providerType,
    required this.externalId,
    this.uri,
    this.projectId,
    this.repository,
    this.branch,
    this.metadata = const {},
  });

  final String referenceId;
  final PipelineProviderType providerType;
  final String externalId;
  final String? uri;
  final String? projectId;
  final String? repository;
  final String? branch;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'referenceId': referenceId,
        'providerType': providerType.wireName,
        'externalId': externalId,
        if (uri != null) 'uri': uri,
        if (projectId != null) 'projectId': projectId,
        if (repository != null) 'repository': repository,
        if (branch != null) 'branch': branch,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PipelineReference.fromJson(Map<String, dynamic> json) {
    return PipelineReference(
      referenceId: json['referenceId'] as String,
      providerType:
          PipelineProviderTypeX.fromWireName(json['providerType'] as String),
      externalId: json['externalId'] as String,
      uri: json['uri'] as String?,
      projectId: json['projectId'] as String?,
      repository: json['repository'] as String?,
      branch: json['branch'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'referenceId': referenceId,
        'providerType': providerType.wireName,
        'externalId': externalId,
        if (uri != null) 'uri': uri,
        if (projectId != null) 'projectId': projectId,
        if (repository != null) 'repository': repository,
        if (branch != null) 'branch': branch,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  PipelineReference copyWith({
    String? referenceId,
    PipelineProviderType? providerType,
    String? externalId,
    String? uri,
    String? projectId,
    String? repository,
    String? branch,
    Map<String, String>? metadata,
  }) {
    return PipelineReference(
      referenceId: referenceId ?? this.referenceId,
      providerType: providerType ?? this.providerType,
      externalId: externalId ?? this.externalId,
      uri: uri ?? this.uri,
      projectId: projectId ?? this.projectId,
      repository: repository ?? this.repository,
      branch: branch ?? this.branch,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineReference &&
          referenceId == other.referenceId &&
          providerType == other.providerType &&
          externalId == other.externalId &&
          uri == other.uri &&
          projectId == other.projectId &&
          repository == other.repository &&
          branch == other.branch &&
          cicdMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        referenceId,
        providerType,
        externalId,
        uri,
        projectId,
        repository,
        branch,
        Object.hashAll(metadata.entries),
      );
}

/// Provider capability descriptor.
class PipelineCapability {
  const PipelineCapability({
    required this.capabilityId,
    required this.capabilityType,
    required this.name,
    this.supported = true,
    this.limitations = const [],
    this.metadata = const {},
  });

  final String capabilityId;
  final PipelineCapabilityType capabilityType;
  final String name;
  final bool supported;
  final List<String> limitations;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'capabilityId': capabilityId,
        'capabilityType': capabilityType.wireName,
        'name': name,
        'supported': supported,
        if (limitations.isNotEmpty) 'limitations': limitations,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PipelineCapability.fromJson(Map<String, dynamic> json) {
    return PipelineCapability(
      capabilityId: json['capabilityId'] as String,
      capabilityType: PipelineCapabilityTypeX.fromWireName(
        json['capabilityType'] as String,
      ),
      name: json['name'] as String,
      supported: json['supported'] as bool? ?? true,
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
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
        'capabilityId': capabilityId,
        'capabilityType': capabilityType.wireName,
        'name': name,
        'supported': supported,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  PipelineCapability copyWith({
    String? capabilityId,
    PipelineCapabilityType? capabilityType,
    String? name,
    bool? supported,
    List<String>? limitations,
    Map<String, String>? metadata,
  }) {
    return PipelineCapability(
      capabilityId: capabilityId ?? this.capabilityId,
      capabilityType: capabilityType ?? this.capabilityType,
      name: name ?? this.name,
      supported: supported ?? this.supported,
      limitations: limitations ?? this.limitations,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineCapability &&
          capabilityId == other.capabilityId &&
          capabilityType == other.capabilityType &&
          name == other.name &&
          supported == other.supported &&
          cicdListEquals(limitations, other.limitations) &&
          cicdMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        capabilityId,
        capabilityType,
        name,
        supported,
        Object.hashAll(limitations),
        Object.hashAll(metadata.entries),
      );
}

/// Integration metadata for pipeline definitions and references.
class PipelineMetadata {
  const PipelineMetadata({
    required this.metadataId,
    required this.schemaVersion,
    required this.canonicalizationVersion,
    required this.createdAt,
    this.updatedAt,
    this.owner,
    this.tags = const [],
    this.limitations = const [],
    this.fingerprint,
    this.extra = const {},
  });

  final String metadataId;
  final int schemaVersion;
  final int canonicalizationVersion;
  final String createdAt;
  final String? updatedAt;
  final String? owner;
  final List<String> tags;
  final List<String> limitations;
  final String? fingerprint;
  final Map<String, String> extra;

  Map<String, dynamic> toJson() => {
        'metadataId': metadataId,
        'schemaVersion': schemaVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (owner != null) 'owner': owner,
        if (tags.isNotEmpty) 'tags': tags,
        if (limitations.isNotEmpty) 'limitations': limitations,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (extra.isNotEmpty) 'extra': extra,
      };

  factory PipelineMetadata.fromJson(Map<String, dynamic> json) {
    return PipelineMetadata(
      metadataId: json['metadataId'] as String,
      schemaVersion: json['schemaVersion'] as int,
      canonicalizationVersion: json['canonicalizationVersion'] as int,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String?,
      owner: json['owner'] as String?,
      tags: List.unmodifiable(
        (json['tags'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      fingerprint: json['fingerprint'] as String?,
      extra: Map.unmodifiable(
        (json['extra'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'metadataId': metadataId,
        'schemaVersion': schemaVersion,
        'canonicalizationVersion': canonicalizationVersion,
        if (owner != null) 'owner': owner,
        if (tags.isNotEmpty) 'tags': List<String>.from(tags)..sort(),
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (extra.isNotEmpty)
          'extra': Map.fromEntries(
            extra.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  PipelineMetadata copyWith({
    String? metadataId,
    int? schemaVersion,
    int? canonicalizationVersion,
    String? createdAt,
    String? updatedAt,
    String? owner,
    List<String>? tags,
    List<String>? limitations,
    String? fingerprint,
    Map<String, String>? extra,
  }) {
    return PipelineMetadata(
      metadataId: metadataId ?? this.metadataId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      canonicalizationVersion:
          canonicalizationVersion ?? this.canonicalizationVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      owner: owner ?? this.owner,
      tags: tags ?? this.tags,
      limitations: limitations ?? this.limitations,
      fingerprint: fingerprint ?? this.fingerprint,
      extra: extra ?? this.extra,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineMetadata &&
          metadataId == other.metadataId &&
          schemaVersion == other.schemaVersion &&
          canonicalizationVersion == other.canonicalizationVersion &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          owner == other.owner &&
          cicdListEquals(tags, other.tags) &&
          cicdListEquals(limitations, other.limitations) &&
          fingerprint == other.fingerprint &&
          cicdMapEquals(extra, other.extra);

  @override
  int get hashCode => Object.hash(
        metadataId,
        schemaVersion,
        canonicalizationVersion,
        createdAt,
        updatedAt,
        owner,
        Object.hashAll(tags),
        Object.hashAll(limitations),
        fingerprint,
        Object.hashAll(extra.entries),
      );
}
