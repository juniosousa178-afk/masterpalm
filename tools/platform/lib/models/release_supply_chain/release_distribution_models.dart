import 'release_supply_chain_enums.dart';
import 'release_supply_chain_equality.dart';

/// Release distribution channel descriptor.
class ReleaseChannel {
  const ReleaseChannel({
    required this.channelId,
    required this.channelType,
    required this.name,
    this.description,
    this.metadata = const {},
  });

  final String channelId;
  final ReleaseChannelType channelType;
  final String name;
  final String? description;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'channelId': channelId,
        'channelType': channelType.wireName,
        'name': name,
        if (description != null) 'description': description,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseChannel.fromJson(Map<String, dynamic> json) {
    return ReleaseChannel(
      channelId: json['channelId'] as String,
      channelType:
          ReleaseChannelTypeX.fromWireName(json['channelType'] as String),
      name: json['name'] as String,
      description: json['description'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'channelId': channelId,
        'channelType': channelType.wireName,
        'name': name,
        if (description != null) 'description': description,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  ReleaseChannel copyWith({
    String? channelId,
    ReleaseChannelType? channelType,
    String? name,
    String? description,
    Map<String, String>? metadata,
  }) {
    return ReleaseChannel(
      channelId: channelId ?? this.channelId,
      channelType: channelType ?? this.channelType,
      name: name ?? this.name,
      description: description ?? this.description,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseChannel &&
          channelId == other.channelId &&
          channelType == other.channelType &&
          name == other.name &&
          description == other.description &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        channelId,
        channelType,
        name,
        description,
        Object.hashAll(metadata.entries),
      );
}

/// Distribution target for a release artifact.
class DistributionTarget {
  const DistributionTarget({
    required this.targetId,
    required this.targetType,
    required this.uri,
    this.region,
    this.metadata = const {},
  });

  final String targetId;
  final DistributionTargetType targetType;
  final String uri;
  final String? region;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'targetId': targetId,
        'targetType': targetType.wireName,
        'uri': uri,
        if (region != null) 'region': region,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory DistributionTarget.fromJson(Map<String, dynamic> json) {
    return DistributionTarget(
      targetId: json['targetId'] as String,
      targetType: DistributionTargetTypeX.fromWireName(
        json['targetType'] as String,
      ),
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
        'targetType': targetType.wireName,
        'uri': uri,
        if (region != null) 'region': region,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  DistributionTarget copyWith({
    String? targetId,
    DistributionTargetType? targetType,
    String? uri,
    String? region,
    Map<String, String>? metadata,
  }) {
    return DistributionTarget(
      targetId: targetId ?? this.targetId,
      targetType: targetType ?? this.targetType,
      uri: uri ?? this.uri,
      region: region ?? this.region,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DistributionTarget &&
          targetId == other.targetId &&
          targetType == other.targetType &&
          uri == other.uri &&
          region == other.region &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
      targetId, targetType, uri, region, Object.hashAll(metadata.entries));
}

/// Policy governing release distribution requirements.
class DistributionPolicy {
  const DistributionPolicy({
    required this.policyId,
    required this.policyVersion,
    required this.name,
    required this.allowedChannelTypes,
    this.requiredTargetCount = 1,
    this.limitations = const [],
  });

  final String policyId;
  final int policyVersion;
  final String name;
  final List<ReleaseChannelType> allowedChannelTypes;
  final int requiredTargetCount;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'name': name,
        'allowedChannelTypes':
            allowedChannelTypes.map((e) => e.wireName).toList()..sort(),
        'requiredTargetCount': requiredTargetCount,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory DistributionPolicy.fromJson(Map<String, dynamic> json) {
    return DistributionPolicy(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      name: json['name'] as String,
      allowedChannelTypes: List.unmodifiable(
        (json['allowedChannelTypes'] as List<dynamic>)
            .map((e) => ReleaseChannelTypeX.fromWireName(e.toString()))
            .toList()
          ..sort((a, b) => a.wireName.compareTo(b.wireName)),
      ),
      requiredTargetCount: json['requiredTargetCount'] as int? ?? 1,
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
        'allowedChannelTypes':
            allowedChannelTypes.map((e) => e.wireName).toList()..sort(),
        'requiredTargetCount': requiredTargetCount,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  DistributionPolicy copyWith({
    String? policyId,
    int? policyVersion,
    String? name,
    List<ReleaseChannelType>? allowedChannelTypes,
    int? requiredTargetCount,
    List<String>? limitations,
  }) {
    return DistributionPolicy(
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      name: name ?? this.name,
      allowedChannelTypes: allowedChannelTypes ?? this.allowedChannelTypes,
      requiredTargetCount: requiredTargetCount ?? this.requiredTargetCount,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DistributionPolicy &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          name == other.name &&
          rscListEquals(allowedChannelTypes, other.allowedChannelTypes) &&
          requiredTargetCount == other.requiredTargetCount &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        policyId,
        policyVersion,
        name,
        Object.hashAll(allowedChannelTypes),
        requiredTargetCount,
        Object.hashAll(limitations),
      );
}

/// Manifest of artifacts included in a distribution.
class DistributionManifest {
  const DistributionManifest({
    required this.manifestId,
    required this.artifactRecordIds,
    required this.fingerprint,
    this.description,
    this.metadata = const {},
  });

  final String manifestId;
  final List<String> artifactRecordIds;
  final String fingerprint;
  final String? description;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'manifestId': manifestId,
        'artifactRecordIds': artifactRecordIds,
        'fingerprint': fingerprint,
        if (description != null) 'description': description,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory DistributionManifest.fromJson(Map<String, dynamic> json) {
    return DistributionManifest(
      manifestId: json['manifestId'] as String,
      artifactRecordIds: List.unmodifiable(
        (json['artifactRecordIds'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
      ),
      fingerprint: json['fingerprint'] as String,
      description: json['description'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'manifestId': manifestId,
        'artifactRecordIds': List<String>.from(artifactRecordIds)..sort(),
        'fingerprint': fingerprint,
        if (description != null) 'description': description,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  DistributionManifest copyWith({
    String? manifestId,
    List<String>? artifactRecordIds,
    String? fingerprint,
    String? description,
    Map<String, String>? metadata,
  }) {
    return DistributionManifest(
      manifestId: manifestId ?? this.manifestId,
      artifactRecordIds: artifactRecordIds ?? this.artifactRecordIds,
      fingerprint: fingerprint ?? this.fingerprint,
      description: description ?? this.description,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DistributionManifest &&
          manifestId == other.manifestId &&
          rscListEquals(artifactRecordIds, other.artifactRecordIds) &&
          fingerprint == other.fingerprint &&
          description == other.description &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        manifestId,
        Object.hashAll(artifactRecordIds),
        fingerprint,
        description,
        Object.hashAll(metadata.entries),
      );
}

/// Release distribution record referencing published artifacts.
class ReleaseDistribution {
  const ReleaseDistribution({
    required this.distributionId,
    required this.projectId,
    required this.status,
    required this.fingerprint,
    required this.channel,
    required this.policy,
    required this.targets,
    required this.manifest,
    required this.schemaVersion,
    required this.createdAt,
    required this.distributedAt,
    this.releaseId,
    this.commitId,
    this.provenanceRecordId,
    this.supplyChainRecordId,
    this.releaseEvidenceBundleId,
    this.warnings = const [],
    this.limitations = const [],
  });

  static const int currentSchemaVersion = 1;

  final String distributionId;
  final String projectId;
  final String? releaseId;
  final String? commitId;
  final String? provenanceRecordId;
  final String? supplyChainRecordId;
  final String? releaseEvidenceBundleId;
  final DistributionStatus status;
  final String fingerprint;
  final ReleaseChannel channel;
  final DistributionPolicy policy;
  final List<DistributionTarget> targets;
  final DistributionManifest manifest;
  final int schemaVersion;
  final String createdAt;
  final String distributedAt;
  final List<String> warnings;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'distributionId': distributionId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (provenanceRecordId != null)
          'provenanceRecordId': provenanceRecordId,
        if (supplyChainRecordId != null)
          'supplyChainRecordId': supplyChainRecordId,
        if (releaseEvidenceBundleId != null)
          'releaseEvidenceBundleId': releaseEvidenceBundleId,
        'status': status.wireName,
        'fingerprint': fingerprint,
        'channel': channel.toJson(),
        'policy': policy.toJson(),
        'targets': targets.map((e) => e.toJson()).toList(),
        'manifest': manifest.toJson(),
        'schemaVersion': schemaVersion,
        'createdAt': createdAt,
        'distributedAt': distributedAt,
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseDistribution.fromJson(Map<String, dynamic> json) {
    return ReleaseDistribution(
      distributionId: json['distributionId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      commitId: json['commitId'] as String?,
      provenanceRecordId: json['provenanceRecordId'] as String?,
      supplyChainRecordId: json['supplyChainRecordId'] as String?,
      releaseEvidenceBundleId: json['releaseEvidenceBundleId'] as String?,
      status: DistributionStatusX.fromWireName(json['status'] as String),
      fingerprint: json['fingerprint'] as String,
      channel: ReleaseChannel.fromJson(json['channel'] as Map<String, dynamic>),
      policy:
          DistributionPolicy.fromJson(json['policy'] as Map<String, dynamic>),
      targets: List.unmodifiable(
        (json['targets'] as List<dynamic>)
            .map((e) => DistributionTarget.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      manifest: DistributionManifest.fromJson(
        json['manifest'] as Map<String, dynamic>,
      ),
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      createdAt: json['createdAt'] as String,
      distributedAt: json['distributedAt'] as String,
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

  Map<String, dynamic> toComparableJson() => {
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (provenanceRecordId != null)
          'provenanceRecordId': provenanceRecordId,
        if (supplyChainRecordId != null)
          'supplyChainRecordId': supplyChainRecordId,
        if (releaseEvidenceBundleId != null)
          'releaseEvidenceBundleId': releaseEvidenceBundleId,
        'status': status.wireName,
        'channel': channel.toComparableJson(),
        'policy': policy.toComparableJson(),
        'targets': (targets.map((e) => e.toComparableJson()).toList()
          ..sort((a, b) =>
              (a['targetId'] as String).compareTo(b['targetId'] as String))),
        'manifest': manifest.toComparableJson(),
        'schemaVersion': schemaVersion,
        if (warnings.isNotEmpty)
          'warnings': List<String>.from(warnings)..sort(),
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  ReleaseDistribution copyWith({
    String? distributionId,
    String? projectId,
    String? releaseId,
    String? commitId,
    String? provenanceRecordId,
    String? supplyChainRecordId,
    String? releaseEvidenceBundleId,
    DistributionStatus? status,
    String? fingerprint,
    ReleaseChannel? channel,
    DistributionPolicy? policy,
    List<DistributionTarget>? targets,
    DistributionManifest? manifest,
    int? schemaVersion,
    String? createdAt,
    String? distributedAt,
    List<String>? warnings,
    List<String>? limitations,
  }) {
    return ReleaseDistribution(
      distributionId: distributionId ?? this.distributionId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      commitId: commitId ?? this.commitId,
      provenanceRecordId: provenanceRecordId ?? this.provenanceRecordId,
      supplyChainRecordId: supplyChainRecordId ?? this.supplyChainRecordId,
      releaseEvidenceBundleId:
          releaseEvidenceBundleId ?? this.releaseEvidenceBundleId,
      status: status ?? this.status,
      fingerprint: fingerprint ?? this.fingerprint,
      channel: channel ?? this.channel,
      policy: policy ?? this.policy,
      targets: targets ?? this.targets,
      manifest: manifest ?? this.manifest,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAt: createdAt ?? this.createdAt,
      distributedAt: distributedAt ?? this.distributedAt,
      warnings: warnings ?? this.warnings,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseDistribution &&
          distributionId == other.distributionId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          commitId == other.commitId &&
          provenanceRecordId == other.provenanceRecordId &&
          supplyChainRecordId == other.supplyChainRecordId &&
          releaseEvidenceBundleId == other.releaseEvidenceBundleId &&
          status == other.status &&
          fingerprint == other.fingerprint &&
          channel == other.channel &&
          policy == other.policy &&
          rscListEquals(targets, other.targets) &&
          manifest == other.manifest &&
          schemaVersion == other.schemaVersion &&
          createdAt == other.createdAt &&
          distributedAt == other.distributedAt &&
          rscListEquals(warnings, other.warnings) &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        distributionId,
        projectId,
        releaseId,
        commitId,
        provenanceRecordId,
        supplyChainRecordId,
        releaseEvidenceBundleId,
        status,
        fingerprint,
        channel,
        policy,
        Object.hashAll(targets),
        manifest,
        schemaVersion,
        createdAt,
        distributedAt,
        Object.hashAll(warnings),
        Object.hashAll(limitations),
      );
}
