import 'release_supply_chain_enums.dart';
import 'release_supply_chain_equality.dart';

/// Content digest for an artifact.
class ArtifactDigest {
  const ArtifactDigest({
    required this.algorithm,
    required this.value,
  });

  final ArtifactDigestAlgorithm algorithm;
  final String value;

  Map<String, dynamic> toJson() => {
        'algorithm': algorithm.wireName,
        'value': value,
      };

  factory ArtifactDigest.fromJson(Map<String, dynamic> json) {
    return ArtifactDigest(
      algorithm: ArtifactDigestAlgorithmX.fromWireName(
        json['algorithm'] as String,
      ),
      value: json['value'] as String,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'algorithm': algorithm.wireName,
        'value': value,
      };

  ArtifactDigest copyWith({ArtifactDigestAlgorithm? algorithm, String? value}) {
    return ArtifactDigest(
      algorithm: algorithm ?? this.algorithm,
      value: value ?? this.value,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtifactDigest &&
          algorithm == other.algorithm &&
          value == other.value;

  @override
  int get hashCode => Object.hash(algorithm, value);
}

/// Integrity descriptor for a registered artifact.
class ArtifactIntegrity {
  const ArtifactIntegrity({
    required this.digest,
    required this.verified,
    this.verificationMethod,
    this.limitations = const [],
  });

  final ArtifactDigest digest;
  final bool verified;
  final String? verificationMethod;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'digest': digest.toJson(),
        'verified': verified,
        if (verificationMethod != null)
          'verificationMethod': verificationMethod,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ArtifactIntegrity.fromJson(Map<String, dynamic> json) {
    return ArtifactIntegrity(
      digest: ArtifactDigest.fromJson(json['digest'] as Map<String, dynamic>),
      verified: json['verified'] as bool,
      verificationMethod: json['verificationMethod'] as String?,
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'digest': digest.toComparableJson(),
        'verified': verified,
        if (verificationMethod != null)
          'verificationMethod': verificationMethod,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  ArtifactIntegrity copyWith({
    ArtifactDigest? digest,
    bool? verified,
    String? verificationMethod,
    List<String>? limitations,
  }) {
    return ArtifactIntegrity(
      digest: digest ?? this.digest,
      verified: verified ?? this.verified,
      verificationMethod: verificationMethod ?? this.verificationMethod,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtifactIntegrity &&
          digest == other.digest &&
          verified == other.verified &&
          verificationMethod == other.verificationMethod &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        digest,
        verified,
        verificationMethod,
        Object.hashAll(limitations),
      );
}

/// Stable identifier for a registered artifact.
class ArtifactIdentifier {
  const ArtifactIdentifier({
    required this.artifactId,
    required this.name,
    required this.version,
    this.purl,
    this.uri,
    this.labels = const [],
  });

  final String artifactId;
  final String name;
  final String version;
  final String? purl;
  final String? uri;
  final List<String> labels;

  Map<String, dynamic> toJson() => {
        'artifactId': artifactId,
        'name': name,
        'version': version,
        if (purl != null) 'purl': purl,
        if (uri != null) 'uri': uri,
        if (labels.isNotEmpty) 'labels': labels,
      };

  factory ArtifactIdentifier.fromJson(Map<String, dynamic> json) {
    return ArtifactIdentifier(
      artifactId: json['artifactId'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      purl: json['purl'] as String?,
      uri: json['uri'] as String?,
      labels: List.unmodifiable(
        (json['labels'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'artifactId': artifactId,
        'name': name,
        'version': version,
        if (purl != null) 'purl': purl,
        if (uri != null) 'uri': uri,
        if (labels.isNotEmpty) 'labels': List<String>.from(labels)..sort(),
      };

  ArtifactIdentifier copyWith({
    String? artifactId,
    String? name,
    String? version,
    String? purl,
    String? uri,
    List<String>? labels,
  }) {
    return ArtifactIdentifier(
      artifactId: artifactId ?? this.artifactId,
      name: name ?? this.name,
      version: version ?? this.version,
      purl: purl ?? this.purl,
      uri: uri ?? this.uri,
      labels: labels ?? this.labels,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtifactIdentifier &&
          artifactId == other.artifactId &&
          name == other.name &&
          version == other.version &&
          purl == other.purl &&
          uri == other.uri &&
          rscListEquals(labels, other.labels);

  @override
  int get hashCode => Object.hash(
        artifactId,
        name,
        version,
        purl,
        uri,
        Object.hashAll(labels),
      );
}

/// Physical or logical location of a registered artifact.
class ArtifactLocation {
  const ArtifactLocation({
    required this.locationId,
    required this.locationType,
    required this.uri,
    this.region,
    this.metadata = const {},
  });

  final String locationId;
  final String locationType;
  final String uri;
  final String? region;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'locationId': locationId,
        'locationType': locationType,
        'uri': uri,
        if (region != null) 'region': region,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ArtifactLocation.fromJson(Map<String, dynamic> json) {
    return ArtifactLocation(
      locationId: json['locationId'] as String,
      locationType: json['locationType'] as String,
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
        'locationId': locationId,
        'locationType': locationType,
        'uri': uri,
        if (region != null) 'region': region,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  ArtifactLocation copyWith({
    String? locationId,
    String? locationType,
    String? uri,
    String? region,
    Map<String, String>? metadata,
  }) {
    return ArtifactLocation(
      locationId: locationId ?? this.locationId,
      locationType: locationType ?? this.locationType,
      uri: uri ?? this.uri,
      region: region ?? this.region,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtifactLocation &&
          locationId == other.locationId &&
          locationType == other.locationType &&
          uri == other.uri &&
          region == other.region &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        locationId,
        locationType,
        uri,
        region,
        Object.hashAll(metadata.entries),
      );
}

/// Metadata for a registered artifact.
class ArtifactMetadata {
  const ArtifactMetadata({
    required this.recordId,
    required this.projectId,
    required this.schemaVersion,
    required this.createdAt,
    required this.registeredAt,
    required this.status,
    required this.fingerprint,
    this.releaseId,
    this.commitId,
    this.mediaType,
    this.sizeBytes,
    this.limitations = const [],
  });

  static const int currentSchemaVersion = 1;

  final String recordId;
  final String projectId;
  final String? releaseId;
  final String? commitId;
  final String? mediaType;
  final int? sizeBytes;
  final int schemaVersion;
  final String createdAt;
  final String registeredAt;
  final ArtifactStatus status;
  final String fingerprint;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'recordId': recordId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (mediaType != null) 'mediaType': mediaType,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        'schemaVersion': schemaVersion,
        'createdAt': createdAt,
        'registeredAt': registeredAt,
        'status': status.wireName,
        'fingerprint': fingerprint,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ArtifactMetadata.fromJson(Map<String, dynamic> json) {
    return ArtifactMetadata(
      recordId: json['recordId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      commitId: json['commitId'] as String?,
      mediaType: json['mediaType'] as String?,
      sizeBytes: json['sizeBytes'] as int?,
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      createdAt: json['createdAt'] as String,
      registeredAt: json['registeredAt'] as String,
      status: ArtifactStatusX.fromWireName(json['status'] as String),
      fingerprint: json['fingerprint'] as String,
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
        if (mediaType != null) 'mediaType': mediaType,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        'schemaVersion': schemaVersion,
        'status': status.wireName,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  ArtifactMetadata copyWith({
    String? recordId,
    String? projectId,
    String? releaseId,
    String? commitId,
    String? mediaType,
    int? sizeBytes,
    int? schemaVersion,
    String? createdAt,
    String? registeredAt,
    ArtifactStatus? status,
    String? fingerprint,
    List<String>? limitations,
  }) {
    return ArtifactMetadata(
      recordId: recordId ?? this.recordId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      commitId: commitId ?? this.commitId,
      mediaType: mediaType ?? this.mediaType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAt: createdAt ?? this.createdAt,
      registeredAt: registeredAt ?? this.registeredAt,
      status: status ?? this.status,
      fingerprint: fingerprint ?? this.fingerprint,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtifactMetadata &&
          recordId == other.recordId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          commitId == other.commitId &&
          mediaType == other.mediaType &&
          sizeBytes == other.sizeBytes &&
          schemaVersion == other.schemaVersion &&
          createdAt == other.createdAt &&
          registeredAt == other.registeredAt &&
          status == other.status &&
          fingerprint == other.fingerprint &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        recordId,
        projectId,
        releaseId,
        commitId,
        mediaType,
        sizeBytes,
        schemaVersion,
        createdAt,
        registeredAt,
        status,
        fingerprint,
        Object.hashAll(limitations),
      );
}

/// Manifest listing artifact constituents.
class ArtifactManifest {
  const ArtifactManifest({
    required this.manifestId,
    required this.artifactIds,
    required this.fingerprint,
    this.description,
    this.metadata = const {},
  });

  final String manifestId;
  final List<String> artifactIds;
  final String fingerprint;
  final String? description;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'manifestId': manifestId,
        'artifactIds': artifactIds,
        'fingerprint': fingerprint,
        if (description != null) 'description': description,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ArtifactManifest.fromJson(Map<String, dynamic> json) {
    return ArtifactManifest(
      manifestId: json['manifestId'] as String,
      artifactIds: List.unmodifiable(
        (json['artifactIds'] as List<dynamic>)
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
        'artifactIds': List<String>.from(artifactIds)..sort(),
        'fingerprint': fingerprint,
        if (description != null) 'description': description,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  ArtifactManifest copyWith({
    String? manifestId,
    List<String>? artifactIds,
    String? fingerprint,
    String? description,
    Map<String, String>? metadata,
  }) {
    return ArtifactManifest(
      manifestId: manifestId ?? this.manifestId,
      artifactIds: artifactIds ?? this.artifactIds,
      fingerprint: fingerprint ?? this.fingerprint,
      description: description ?? this.description,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtifactManifest &&
          manifestId == other.manifestId &&
          rscListEquals(artifactIds, other.artifactIds) &&
          fingerprint == other.fingerprint &&
          description == other.description &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        manifestId,
        Object.hashAll(artifactIds),
        fingerprint,
        description,
        Object.hashAll(metadata.entries),
      );
}

/// Registered artifact record in the artifact registry domain.
class ArtifactRecord {
  const ArtifactRecord({
    required this.metadata,
    required this.identifier,
    required this.location,
    required this.integrity,
    this.manifest,
    this.provenanceRecordId,
    this.sbomId,
    this.warnings = const [],
    this.limitations = const [],
  });

  final ArtifactMetadata metadata;
  final ArtifactIdentifier identifier;
  final ArtifactLocation location;
  final ArtifactIntegrity integrity;
  final ArtifactManifest? manifest;
  final String? provenanceRecordId;
  final String? sbomId;
  final List<String> warnings;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'identifier': identifier.toJson(),
        'location': location.toJson(),
        'integrity': integrity.toJson(),
        if (manifest != null) 'manifest': manifest!.toJson(),
        if (provenanceRecordId != null)
          'provenanceRecordId': provenanceRecordId,
        if (sbomId != null) 'sbomId': sbomId,
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ArtifactRecord.fromJson(Map<String, dynamic> json) {
    return ArtifactRecord(
      metadata: ArtifactMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      identifier: ArtifactIdentifier.fromJson(
        json['identifier'] as Map<String, dynamic>,
      ),
      location: ArtifactLocation.fromJson(
        json['location'] as Map<String, dynamic>,
      ),
      integrity: ArtifactIntegrity.fromJson(
        json['integrity'] as Map<String, dynamic>,
      ),
      manifest: json['manifest'] == null
          ? null
          : ArtifactManifest.fromJson(json['manifest'] as Map<String, dynamic>),
      provenanceRecordId: json['provenanceRecordId'] as String?,
      sbomId: json['sbomId'] as String?,
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
        'metadata': metadata.toComparableJson(),
        'identifier': identifier.toComparableJson(),
        'location': location.toComparableJson(),
        'integrity': integrity.toComparableJson(),
        if (manifest != null) 'manifest': manifest!.toComparableJson(),
        if (provenanceRecordId != null)
          'provenanceRecordId': provenanceRecordId,
        if (sbomId != null) 'sbomId': sbomId,
        if (warnings.isNotEmpty)
          'warnings': List<String>.from(warnings)..sort(),
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  ArtifactRecord copyWith({
    ArtifactMetadata? metadata,
    ArtifactIdentifier? identifier,
    ArtifactLocation? location,
    ArtifactIntegrity? integrity,
    ArtifactManifest? manifest,
    String? provenanceRecordId,
    String? sbomId,
    List<String>? warnings,
    List<String>? limitations,
  }) {
    return ArtifactRecord(
      metadata: metadata ?? this.metadata,
      identifier: identifier ?? this.identifier,
      location: location ?? this.location,
      integrity: integrity ?? this.integrity,
      manifest: manifest ?? this.manifest,
      provenanceRecordId: provenanceRecordId ?? this.provenanceRecordId,
      sbomId: sbomId ?? this.sbomId,
      warnings: warnings ?? this.warnings,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtifactRecord &&
          metadata == other.metadata &&
          identifier == other.identifier &&
          location == other.location &&
          integrity == other.integrity &&
          manifest == other.manifest &&
          provenanceRecordId == other.provenanceRecordId &&
          sbomId == other.sbomId &&
          rscListEquals(warnings, other.warnings) &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        metadata,
        identifier,
        location,
        integrity,
        manifest,
        provenanceRecordId,
        sbomId,
        Object.hashAll(warnings),
        Object.hashAll(limitations),
      );
}
