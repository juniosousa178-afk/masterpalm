import 'release_supply_chain_enums.dart';
import 'release_supply_chain_equality.dart';

/// Cryptographic or content hash for an SBOM component.
class SbomHash {
  const SbomHash({
    required this.algorithm,
    required this.value,
  });

  final ArtifactDigestAlgorithm algorithm;
  final String value;

  Map<String, dynamic> toJson() => {
        'algorithm': algorithm.wireName,
        'value': value,
      };

  factory SbomHash.fromJson(Map<String, dynamic> json) {
    return SbomHash(
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

  SbomHash copyWith({ArtifactDigestAlgorithm? algorithm, String? value}) {
    return SbomHash(
      algorithm: algorithm ?? this.algorithm,
      value: value ?? this.value,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SbomHash && algorithm == other.algorithm && value == other.value;

  @override
  int get hashCode => Object.hash(algorithm, value);
}

/// SPDX or other license reference for an SBOM component.
class SbomLicense {
  const SbomLicense({
    required this.licenseId,
    required this.spdxId,
    this.name,
    this.url,
  });

  final String licenseId;
  final String spdxId;
  final String? name;
  final String? url;

  Map<String, dynamic> toJson() => {
        'licenseId': licenseId,
        'spdxId': spdxId,
        if (name != null) 'name': name,
        if (url != null) 'url': url,
      };

  factory SbomLicense.fromJson(Map<String, dynamic> json) {
    return SbomLicense(
      licenseId: json['licenseId'] as String,
      spdxId: json['spdxId'] as String,
      name: json['name'] as String?,
      url: json['url'] as String?,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'licenseId': licenseId,
        'spdxId': spdxId,
        if (name != null) 'name': name,
        if (url != null) 'url': url,
      };

  SbomLicense copyWith({
    String? licenseId,
    String? spdxId,
    String? name,
    String? url,
  }) {
    return SbomLicense(
      licenseId: licenseId ?? this.licenseId,
      spdxId: spdxId ?? this.spdxId,
      name: name ?? this.name,
      url: url ?? this.url,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SbomLicense &&
          licenseId == other.licenseId &&
          spdxId == other.spdxId &&
          name == other.name &&
          url == other.url;

  @override
  int get hashCode => Object.hash(licenseId, spdxId, name, url);
}

/// Supplier metadata for an SBOM component.
class SbomSupplier {
  const SbomSupplier({
    required this.supplierId,
    required this.name,
    this.url,
    this.contact,
    this.metadata = const {},
  });

  final String supplierId;
  final String name;
  final String? url;
  final String? contact;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'supplierId': supplierId,
        'name': name,
        if (url != null) 'url': url,
        if (contact != null) 'contact': contact,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory SbomSupplier.fromJson(Map<String, dynamic> json) {
    return SbomSupplier(
      supplierId: json['supplierId'] as String,
      name: json['name'] as String,
      url: json['url'] as String?,
      contact: json['contact'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'supplierId': supplierId,
        'name': name,
        if (url != null) 'url': url,
        if (contact != null) 'contact': contact,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  SbomSupplier copyWith({
    String? supplierId,
    String? name,
    String? url,
    String? contact,
    Map<String, String>? metadata,
  }) {
    return SbomSupplier(
      supplierId: supplierId ?? this.supplierId,
      name: name ?? this.name,
      url: url ?? this.url,
      contact: contact ?? this.contact,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SbomSupplier &&
          supplierId == other.supplierId &&
          name == other.name &&
          url == other.url &&
          contact == other.contact &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        supplierId,
        name,
        url,
        contact,
        Object.hashAll(metadata.entries),
      );
}

/// Origin descriptor for an SBOM component.
class SbomOrigin {
  const SbomOrigin({
    required this.originId,
    required this.sourceType,
    this.uri,
    this.commitId,
    this.metadata = const {},
  });

  final String originId;
  final String sourceType;
  final String? uri;
  final String? commitId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'originId': originId,
        'sourceType': sourceType,
        if (uri != null) 'uri': uri,
        if (commitId != null) 'commitId': commitId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory SbomOrigin.fromJson(Map<String, dynamic> json) {
    return SbomOrigin(
      originId: json['originId'] as String,
      sourceType: json['sourceType'] as String,
      uri: json['uri'] as String?,
      commitId: json['commitId'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'originId': originId,
        'sourceType': sourceType,
        if (uri != null) 'uri': uri,
        if (commitId != null) 'commitId': commitId,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  SbomOrigin copyWith({
    String? originId,
    String? sourceType,
    String? uri,
    String? commitId,
    Map<String, String>? metadata,
  }) {
    return SbomOrigin(
      originId: originId ?? this.originId,
      sourceType: sourceType ?? this.sourceType,
      uri: uri ?? this.uri,
      commitId: commitId ?? this.commitId,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SbomOrigin &&
          originId == other.originId &&
          sourceType == other.sourceType &&
          uri == other.uri &&
          commitId == other.commitId &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        originId,
        sourceType,
        uri,
        commitId,
        Object.hashAll(metadata.entries),
      );
}

/// Package descriptor within an SBOM.
class SbomPackage {
  const SbomPackage({
    required this.packageId,
    required this.name,
    required this.version,
    this.purl,
    this.cpe,
    this.metadata = const {},
  });

  final String packageId;
  final String name;
  final String version;
  final String? purl;
  final String? cpe;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'packageId': packageId,
        'name': name,
        'version': version,
        if (purl != null) 'purl': purl,
        if (cpe != null) 'cpe': cpe,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory SbomPackage.fromJson(Map<String, dynamic> json) {
    return SbomPackage(
      packageId: json['packageId'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      purl: json['purl'] as String?,
      cpe: json['cpe'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'packageId': packageId,
        'name': name,
        'version': version,
        if (purl != null) 'purl': purl,
        if (cpe != null) 'cpe': cpe,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  SbomPackage copyWith({
    String? packageId,
    String? name,
    String? version,
    String? purl,
    String? cpe,
    Map<String, String>? metadata,
  }) {
    return SbomPackage(
      packageId: packageId ?? this.packageId,
      name: name ?? this.name,
      version: version ?? this.version,
      purl: purl ?? this.purl,
      cpe: cpe ?? this.cpe,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SbomPackage &&
          packageId == other.packageId &&
          name == other.name &&
          version == other.version &&
          purl == other.purl &&
          cpe == other.cpe &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        packageId,
        name,
        version,
        purl,
        cpe,
        Object.hashAll(metadata.entries),
      );
}

/// SBOM component with supplier, license and hash references.
class SbomComponent {
  const SbomComponent({
    required this.componentId,
    required this.componentType,
    required this.packageRef,
    required this.hashes,
    this.supplier,
    this.licenses = const [],
    this.origin,
    this.metadata = const {},
  });

  final String componentId;
  final SbomComponentType componentType;
  final SbomPackage packageRef;
  final List<SbomHash> hashes;
  final SbomSupplier? supplier;
  final List<SbomLicense> licenses;
  final SbomOrigin? origin;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'componentId': componentId,
        'componentType': componentType.wireName,
        'packageRef': packageRef.toJson(),
        'hashes': hashes.map((e) => e.toJson()).toList(),
        if (supplier != null) 'supplier': supplier!.toJson(),
        if (licenses.isNotEmpty)
          'licenses': licenses.map((e) => e.toJson()).toList(),
        if (origin != null) 'origin': origin!.toJson(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory SbomComponent.fromJson(Map<String, dynamic> json) {
    return SbomComponent(
      componentId: json['componentId'] as String,
      componentType: SbomComponentTypeX.fromWireName(
        json['componentType'] as String,
      ),
      packageRef: SbomPackage.fromJson(
        json['packageRef'] as Map<String, dynamic>,
      ),
      hashes: List.unmodifiable(
        (json['hashes'] as List<dynamic>)
            .map((e) => SbomHash.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      supplier: json['supplier'] == null
          ? null
          : SbomSupplier.fromJson(json['supplier'] as Map<String, dynamic>),
      licenses: List.unmodifiable(
        (json['licenses'] as List<dynamic>? ?? [])
            .map((e) => SbomLicense.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      origin: json['origin'] == null
          ? null
          : SbomOrigin.fromJson(json['origin'] as Map<String, dynamic>),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'componentId': componentId,
        'componentType': componentType.wireName,
        'packageRef': packageRef.toComparableJson(),
        'hashes': (hashes.map((e) => e.toComparableJson()).toList()
          ..sort((a, b) =>
              (a['value'] as String).compareTo(b['value'] as String))),
        if (supplier != null) 'supplier': supplier!.toComparableJson(),
        if (licenses.isNotEmpty)
          'licenses': (licenses.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => (a['licenseId'] as String)
                  .compareTo(b['licenseId'] as String),
            )),
        if (origin != null) 'origin': origin!.toComparableJson(),
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  SbomComponent copyWith({
    String? componentId,
    SbomComponentType? componentType,
    SbomPackage? packageRef,
    List<SbomHash>? hashes,
    SbomSupplier? supplier,
    List<SbomLicense>? licenses,
    SbomOrigin? origin,
    Map<String, String>? metadata,
  }) {
    return SbomComponent(
      componentId: componentId ?? this.componentId,
      componentType: componentType ?? this.componentType,
      packageRef: packageRef ?? this.packageRef,
      hashes: hashes ?? this.hashes,
      supplier: supplier ?? this.supplier,
      licenses: licenses ?? this.licenses,
      origin: origin ?? this.origin,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SbomComponent &&
          componentId == other.componentId &&
          componentType == other.componentType &&
          packageRef == other.packageRef &&
          rscListEquals(hashes, other.hashes) &&
          supplier == other.supplier &&
          rscListEquals(licenses, other.licenses) &&
          origin == other.origin &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        componentId,
        componentType,
        packageRef,
        Object.hashAll(hashes),
        supplier,
        Object.hashAll(licenses),
        origin,
        Object.hashAll(metadata.entries),
      );
}

/// Dependency edge between SBOM components.
class SbomDependencyEdge {
  const SbomDependencyEdge({
    required this.edgeId,
    required this.fromComponentId,
    required this.toComponentId,
    required this.scope,
  });

  final String edgeId;
  final String fromComponentId;
  final String toComponentId;
  final SbomDependencyScope scope;

  Map<String, dynamic> toJson() => {
        'edgeId': edgeId,
        'fromComponentId': fromComponentId,
        'toComponentId': toComponentId,
        'scope': scope.wireName,
      };

  factory SbomDependencyEdge.fromJson(Map<String, dynamic> json) {
    return SbomDependencyEdge(
      edgeId: json['edgeId'] as String,
      fromComponentId: json['fromComponentId'] as String,
      toComponentId: json['toComponentId'] as String,
      scope: SbomDependencyScopeX.fromWireName(json['scope'] as String),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'edgeId': edgeId,
        'fromComponentId': fromComponentId,
        'toComponentId': toComponentId,
        'scope': scope.wireName,
      };

  SbomDependencyEdge copyWith({
    String? edgeId,
    String? fromComponentId,
    String? toComponentId,
    SbomDependencyScope? scope,
  }) {
    return SbomDependencyEdge(
      edgeId: edgeId ?? this.edgeId,
      fromComponentId: fromComponentId ?? this.fromComponentId,
      toComponentId: toComponentId ?? this.toComponentId,
      scope: scope ?? this.scope,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SbomDependencyEdge &&
          edgeId == other.edgeId &&
          fromComponentId == other.fromComponentId &&
          toComponentId == other.toComponentId &&
          scope == other.scope;

  @override
  int get hashCode =>
      Object.hash(edgeId, fromComponentId, toComponentId, scope);
}

/// Dependency declaration within an SBOM.
class SbomDependency {
  const SbomDependency({
    required this.dependencyId,
    required this.componentId,
    required this.edges,
    this.direct = true,
  });

  final String dependencyId;
  final String componentId;
  final List<SbomDependencyEdge> edges;
  final bool direct;

  Map<String, dynamic> toJson() => {
        'dependencyId': dependencyId,
        'componentId': componentId,
        'edges': edges.map((e) => e.toJson()).toList(),
        'direct': direct,
      };

  factory SbomDependency.fromJson(Map<String, dynamic> json) {
    return SbomDependency(
      dependencyId: json['dependencyId'] as String,
      componentId: json['componentId'] as String,
      edges: List.unmodifiable(
        (json['edges'] as List<dynamic>)
            .map((e) => SbomDependencyEdge.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      direct: json['direct'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'dependencyId': dependencyId,
        'componentId': componentId,
        'edges': (edges.map((e) => e.toComparableJson()).toList()
          ..sort((a, b) =>
              (a['edgeId'] as String).compareTo(b['edgeId'] as String))),
        'direct': direct,
      };

  SbomDependency copyWith({
    String? dependencyId,
    String? componentId,
    List<SbomDependencyEdge>? edges,
    bool? direct,
  }) {
    return SbomDependency(
      dependencyId: dependencyId ?? this.dependencyId,
      componentId: componentId ?? this.componentId,
      edges: edges ?? this.edges,
      direct: direct ?? this.direct,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SbomDependency &&
          dependencyId == other.dependencyId &&
          componentId == other.componentId &&
          rscListEquals(edges, other.edges) &&
          direct == other.direct;

  @override
  int get hashCode =>
      Object.hash(dependencyId, componentId, Object.hashAll(edges), direct);
}

/// Metadata for a software bill of materials document.
class SbomMetadata {
  const SbomMetadata({
    required this.sbomId,
    required this.projectId,
    required this.schemaVersion,
    required this.canonicalizationVersion,
    required this.createdAt,
    required this.generatedAt,
    required this.status,
    required this.fingerprint,
    required this.componentCount,
    required this.dependencyCount,
    this.releaseId,
    this.commitId,
    this.serialNumber,
    this.limitations = const [],
  });

  static const int currentSchemaVersion = 1;
  static const int currentCanonicalizationVersion = 1;

  final String sbomId;
  final String projectId;
  final String? releaseId;
  final String? commitId;
  final String? serialNumber;
  final int schemaVersion;
  final int canonicalizationVersion;
  final String createdAt;
  final String generatedAt;
  final SbomStatus status;
  final String fingerprint;
  final int componentCount;
  final int dependencyCount;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'sbomId': sbomId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (serialNumber != null) 'serialNumber': serialNumber,
        'schemaVersion': schemaVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'createdAt': createdAt,
        'generatedAt': generatedAt,
        'status': status.wireName,
        'fingerprint': fingerprint,
        'componentCount': componentCount,
        'dependencyCount': dependencyCount,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory SbomMetadata.fromJson(Map<String, dynamic> json) {
    return SbomMetadata(
      sbomId: json['sbomId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      commitId: json['commitId'] as String?,
      serialNumber: json['serialNumber'] as String?,
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      canonicalizationVersion: json['canonicalizationVersion'] as int? ??
          currentCanonicalizationVersion,
      createdAt: json['createdAt'] as String,
      generatedAt: json['generatedAt'] as String,
      status: SbomStatusX.fromWireName(json['status'] as String),
      fingerprint: json['fingerprint'] as String,
      componentCount: json['componentCount'] as int,
      dependencyCount: json['dependencyCount'] as int,
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
        if (serialNumber != null) 'serialNumber': serialNumber,
        'schemaVersion': schemaVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'status': status.wireName,
        'componentCount': componentCount,
        'dependencyCount': dependencyCount,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  SbomMetadata copyWith({
    String? sbomId,
    String? projectId,
    String? releaseId,
    String? commitId,
    String? serialNumber,
    int? schemaVersion,
    int? canonicalizationVersion,
    String? createdAt,
    String? generatedAt,
    SbomStatus? status,
    String? fingerprint,
    int? componentCount,
    int? dependencyCount,
    List<String>? limitations,
  }) {
    return SbomMetadata(
      sbomId: sbomId ?? this.sbomId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      commitId: commitId ?? this.commitId,
      serialNumber: serialNumber ?? this.serialNumber,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      canonicalizationVersion:
          canonicalizationVersion ?? this.canonicalizationVersion,
      createdAt: createdAt ?? this.createdAt,
      generatedAt: generatedAt ?? this.generatedAt,
      status: status ?? this.status,
      fingerprint: fingerprint ?? this.fingerprint,
      componentCount: componentCount ?? this.componentCount,
      dependencyCount: dependencyCount ?? this.dependencyCount,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SbomMetadata &&
          sbomId == other.sbomId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          commitId == other.commitId &&
          serialNumber == other.serialNumber &&
          schemaVersion == other.schemaVersion &&
          canonicalizationVersion == other.canonicalizationVersion &&
          createdAt == other.createdAt &&
          generatedAt == other.generatedAt &&
          status == other.status &&
          fingerprint == other.fingerprint &&
          componentCount == other.componentCount &&
          dependencyCount == other.dependencyCount &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        sbomId,
        projectId,
        releaseId,
        commitId,
        serialNumber,
        schemaVersion,
        canonicalizationVersion,
        createdAt,
        generatedAt,
        status,
        fingerprint,
        componentCount,
        dependencyCount,
        Object.hashAll(limitations),
      );
}

/// Software bill of materials document (declarative, no automatic scan).
class SoftwareBillOfMaterials {
  const SoftwareBillOfMaterials({
    required this.metadata,
    required this.components,
    required this.dependencies,
    this.warnings = const [],
    this.limitations = const [],
  });

  final SbomMetadata metadata;
  final List<SbomComponent> components;
  final List<SbomDependency> dependencies;
  final List<String> warnings;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'components': components.map((e) => e.toJson()).toList(),
        'dependencies': dependencies.map((e) => e.toJson()).toList(),
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory SoftwareBillOfMaterials.fromJson(Map<String, dynamic> json) {
    return SoftwareBillOfMaterials(
      metadata: SbomMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
      components: List.unmodifiable(
        (json['components'] as List<dynamic>)
            .map((e) => SbomComponent.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      dependencies: List.unmodifiable(
        (json['dependencies'] as List<dynamic>)
            .map((e) => SbomDependency.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
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
        'components': (components.map((e) => e.toComparableJson()).toList()
          ..sort(
            (a, b) => (a['componentId'] as String)
                .compareTo(b['componentId'] as String),
          )),
        'dependencies': (dependencies.map((e) => e.toComparableJson()).toList()
          ..sort(
            (a, b) => (a['dependencyId'] as String)
                .compareTo(b['dependencyId'] as String),
          )),
        if (warnings.isNotEmpty)
          'warnings': List<String>.from(warnings)..sort(),
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  SoftwareBillOfMaterials copyWith({
    SbomMetadata? metadata,
    List<SbomComponent>? components,
    List<SbomDependency>? dependencies,
    List<String>? warnings,
    List<String>? limitations,
  }) {
    return SoftwareBillOfMaterials(
      metadata: metadata ?? this.metadata,
      components: components ?? this.components,
      dependencies: dependencies ?? this.dependencies,
      warnings: warnings ?? this.warnings,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SoftwareBillOfMaterials &&
          metadata == other.metadata &&
          rscListEquals(components, other.components) &&
          rscListEquals(dependencies, other.dependencies) &&
          rscListEquals(warnings, other.warnings) &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        metadata,
        Object.hashAll(components),
        Object.hashAll(dependencies),
        Object.hashAll(warnings),
        Object.hashAll(limitations),
      );
}
