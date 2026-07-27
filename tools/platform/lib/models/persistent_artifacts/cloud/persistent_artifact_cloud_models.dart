import '../persistent_artifact_equality.dart';
import 'persistent_artifact_cloud_enums.dart';

class PersistentArtifactCloudEndpointReference {
  const PersistentArtifactCloudEndpointReference({
    required this.endpointId,
    required this.serviceType,
    required this.endpointType,
    required this.regionId,
    required this.hostnameReference,
    this.pathPrefix,
    this.metadata = const {},
  });

  final String endpointId;
  final CloudServiceType serviceType;
  final CloudEndpointType endpointType;
  final String regionId;
  final String hostnameReference;
  final String? pathPrefix;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'endpointId': endpointId,
        'serviceType': serviceType.wireName,
        'endpointType': endpointType.wireName,
        'regionId': regionId,
        'hostnameReference': hostnameReference,
        if (pathPrefix != null) 'pathPrefix': pathPrefix,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudEndpointReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudEndpointReference(
      endpointId: json['endpointId'] as String,
      serviceType:
          CloudServiceTypeX.fromWireName(json['serviceType'] as String),
      endpointType:
          CloudEndpointTypeX.fromWireName(json['endpointType'] as String),
      regionId: json['regionId'] as String,
      hostnameReference: json['hostnameReference'] as String,
      pathPrefix: json['pathPrefix'] as String?,
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'endpointId': endpointId,
        'serviceType': serviceType.wireName,
        'endpointType': endpointType.wireName,
        'regionId': regionId,
        'hostnameReference': hostnameReference,
        if (pathPrefix != null) 'pathPrefix': pathPrefix,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudEndpointReference copyWith({
    String? endpointId,
    CloudServiceType? serviceType,
    CloudEndpointType? endpointType,
    String? regionId,
    String? hostnameReference,
    String? pathPrefix,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudEndpointReference(
      endpointId: endpointId ?? this.endpointId,
      serviceType: serviceType ?? this.serviceType,
      endpointType: endpointType ?? this.endpointType,
      regionId: regionId ?? this.regionId,
      hostnameReference: hostnameReference ?? this.hostnameReference,
      pathPrefix: pathPrefix ?? this.pathPrefix,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudEndpointReference &&
          endpointId == other.endpointId &&
          serviceType == other.serviceType &&
          endpointType == other.endpointType &&
          regionId == other.regionId &&
          hostnameReference == other.hostnameReference &&
          pathPrefix == other.pathPrefix &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        endpointId,
        serviceType,
        endpointType,
        regionId,
        hostnameReference,
        pathPrefix,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudRegionReference {
  const PersistentArtifactCloudRegionReference({
    required this.regionId,
    required this.providerRegionReference,
    required this.status,
    this.zones = const [],
    this.metadata = const {},
  });

  final String regionId;
  final String providerRegionReference;
  final CloudRegionStatus status;
  final List<String> zones;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'regionId': regionId,
        'providerRegionReference': providerRegionReference,
        'status': status.wireName,
        if (zones.isNotEmpty) 'zones': zones,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudRegionReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudRegionReference(
      regionId: json['regionId'] as String,
      providerRegionReference: json['providerRegionReference'] as String,
      status: CloudRegionStatusX.fromWireName(json['status'] as String),
      zones: _stringList(json['zones']),
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'regionId': regionId,
        'providerRegionReference': providerRegionReference,
        'status': status.wireName,
        if (zones.isNotEmpty) 'zones': List<String>.from(zones)..sort(),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudRegionReference copyWith({
    String? regionId,
    String? providerRegionReference,
    CloudRegionStatus? status,
    List<String>? zones,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudRegionReference(
      regionId: regionId ?? this.regionId,
      providerRegionReference:
          providerRegionReference ?? this.providerRegionReference,
      status: status ?? this.status,
      zones: zones ?? this.zones,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudRegionReference &&
          regionId == other.regionId &&
          providerRegionReference == other.providerRegionReference &&
          status == other.status &&
          paListEquals(zones, other.zones) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        regionId,
        providerRegionReference,
        status,
        Object.hashAll(zones),
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudFailureDomainReference {
  const PersistentArtifactCloudFailureDomainReference({
    required this.failureDomainId,
    required this.regionId,
    this.rackHints = const [],
    this.metadata = const {},
  });

  final String failureDomainId;
  final String regionId;
  final List<String> rackHints;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'failureDomainId': failureDomainId,
        'regionId': regionId,
        if (rackHints.isNotEmpty) 'rackHints': rackHints,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudFailureDomainReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudFailureDomainReference(
      failureDomainId: json['failureDomainId'] as String,
      regionId: json['regionId'] as String,
      rackHints: _stringList(json['rackHints']),
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'failureDomainId': failureDomainId,
        'regionId': regionId,
        if (rackHints.isNotEmpty)
          'rackHints': List<String>.from(rackHints)..sort(),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudFailureDomainReference copyWith({
    String? failureDomainId,
    String? regionId,
    List<String>? rackHints,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudFailureDomainReference(
      failureDomainId: failureDomainId ?? this.failureDomainId,
      regionId: regionId ?? this.regionId,
      rackHints: rackHints ?? this.rackHints,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudFailureDomainReference &&
          failureDomainId == other.failureDomainId &&
          regionId == other.regionId &&
          paListEquals(rackHints, other.rackHints) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        failureDomainId,
        regionId,
        Object.hashAll(rackHints),
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudContainerReference {
  const PersistentArtifactCloudContainerReference({
    required this.containerId,
    required this.providerType,
    required this.namespaceReference,
    required this.regionId,
    this.metadata = const {},
  });

  final String containerId;
  final PersistentArtifactCloudProviderType providerType;
  final String namespaceReference;
  final String regionId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'containerId': containerId,
        'providerType': providerType.wireName,
        'namespaceReference': namespaceReference,
        'regionId': regionId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudContainerReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudContainerReference(
      containerId: json['containerId'] as String,
      providerType: PersistentArtifactCloudProviderTypeX.fromWireName(
        json['providerType'] as String,
      ),
      namespaceReference: json['namespaceReference'] as String,
      regionId: json['regionId'] as String,
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'containerId': containerId,
        'providerType': providerType.wireName,
        'namespaceReference': namespaceReference,
        'regionId': regionId,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudContainerReference copyWith({
    String? containerId,
    PersistentArtifactCloudProviderType? providerType,
    String? namespaceReference,
    String? regionId,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudContainerReference(
      containerId: containerId ?? this.containerId,
      providerType: providerType ?? this.providerType,
      namespaceReference: namespaceReference ?? this.namespaceReference,
      regionId: regionId ?? this.regionId,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudContainerReference &&
          containerId == other.containerId &&
          providerType == other.providerType &&
          namespaceReference == other.namespaceReference &&
          regionId == other.regionId &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        containerId,
        providerType,
        namespaceReference,
        regionId,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudObjectReference {
  const PersistentArtifactCloudObjectReference({
    required this.objectId,
    required this.containerId,
    required this.objectKey,
    required this.status,
    required this.sizeBytes,
    this.etag,
    this.checksums = const {},
    this.metadata = const {},
  });

  final String objectId;
  final String containerId;
  final String objectKey;
  final CloudObjectStatus status;
  final int sizeBytes;
  final String? etag;
  final Map<String, String> checksums;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'objectId': objectId,
        'containerId': containerId,
        'objectKey': objectKey,
        'status': status.wireName,
        'sizeBytes': sizeBytes,
        if (etag != null) 'etag': etag,
        if (checksums.isNotEmpty) 'checksums': checksums,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudObjectReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudObjectReference(
      objectId: json['objectId'] as String,
      containerId: json['containerId'] as String,
      objectKey: json['objectKey'] as String,
      status: CloudObjectStatusX.fromWireName(json['status'] as String),
      sizeBytes: json['sizeBytes'] as int,
      etag: json['etag'] as String?,
      checksums: _stringMap(json['checksums']),
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'objectId': objectId,
        'containerId': containerId,
        'objectKey': objectKey,
        'status': status.wireName,
        'sizeBytes': sizeBytes,
        if (etag != null) 'etag': etag,
        if (checksums.isNotEmpty) 'checksums': paSortedStringMap(checksums),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudObjectReference copyWith({
    String? objectId,
    String? containerId,
    String? objectKey,
    CloudObjectStatus? status,
    int? sizeBytes,
    String? etag,
    Map<String, String>? checksums,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudObjectReference(
      objectId: objectId ?? this.objectId,
      containerId: containerId ?? this.containerId,
      objectKey: objectKey ?? this.objectKey,
      status: status ?? this.status,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      etag: etag ?? this.etag,
      checksums: checksums ?? this.checksums,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudObjectReference &&
          objectId == other.objectId &&
          containerId == other.containerId &&
          objectKey == other.objectKey &&
          status == other.status &&
          sizeBytes == other.sizeBytes &&
          etag == other.etag &&
          paMapEquals(checksums, other.checksums) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        objectId,
        containerId,
        objectKey,
        status,
        sizeBytes,
        etag,
        Object.hashAll(checksums.entries),
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudObjectVersionReference {
  const PersistentArtifactCloudObjectVersionReference({
    required this.versionId,
    required this.objectId,
    required this.providerVersionReference,
    required this.versionIndex,
    this.metadata = const {},
  });

  final String versionId;
  final String objectId;
  final String providerVersionReference;
  final int versionIndex;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'versionId': versionId,
        'objectId': objectId,
        'providerVersionReference': providerVersionReference,
        'versionIndex': versionIndex,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudObjectVersionReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudObjectVersionReference(
      versionId: json['versionId'] as String,
      objectId: json['objectId'] as String,
      providerVersionReference: json['providerVersionReference'] as String,
      versionIndex: json['versionIndex'] as int,
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'versionId': versionId,
        'objectId': objectId,
        'providerVersionReference': providerVersionReference,
        'versionIndex': versionIndex,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudObjectVersionReference copyWith({
    String? versionId,
    String? objectId,
    String? providerVersionReference,
    int? versionIndex,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudObjectVersionReference(
      versionId: versionId ?? this.versionId,
      objectId: objectId ?? this.objectId,
      providerVersionReference:
          providerVersionReference ?? this.providerVersionReference,
      versionIndex: versionIndex ?? this.versionIndex,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudObjectVersionReference &&
          versionId == other.versionId &&
          objectId == other.objectId &&
          providerVersionReference == other.providerVersionReference &&
          versionIndex == other.versionIndex &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        versionId,
        objectId,
        providerVersionReference,
        versionIndex,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudAuthenticationReference {
  const PersistentArtifactCloudAuthenticationReference({
    required this.authenticationId,
    required this.authenticationType,
    required this.identityId,
    required this.credentialReference,
    this.scope = const [],
    this.metadata = const {},
  });

  final String authenticationId;
  final CloudAuthenticationType authenticationType;
  final String identityId;
  final String credentialReference;
  final List<String> scope;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'authenticationId': authenticationId,
        'authenticationType': authenticationType.wireName,
        'identityId': identityId,
        'credentialReference': credentialReference,
        if (scope.isNotEmpty) 'scope': scope,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudAuthenticationReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudAuthenticationReference(
      authenticationId: json['authenticationId'] as String,
      authenticationType: CloudAuthenticationTypeX.fromWireName(
        json['authenticationType'] as String,
      ),
      identityId: json['identityId'] as String,
      credentialReference: json['credentialReference'] as String,
      scope: _stringList(json['scope']),
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'authenticationId': authenticationId,
        'authenticationType': authenticationType.wireName,
        'identityId': identityId,
        'credentialReference': credentialReference,
        if (scope.isNotEmpty) 'scope': List<String>.from(scope)..sort(),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudAuthenticationReference copyWith({
    String? authenticationId,
    CloudAuthenticationType? authenticationType,
    String? identityId,
    String? credentialReference,
    List<String>? scope,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudAuthenticationReference(
      authenticationId: authenticationId ?? this.authenticationId,
      authenticationType: authenticationType ?? this.authenticationType,
      identityId: identityId ?? this.identityId,
      credentialReference: credentialReference ?? this.credentialReference,
      scope: scope ?? this.scope,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudAuthenticationReference &&
          authenticationId == other.authenticationId &&
          authenticationType == other.authenticationType &&
          identityId == other.identityId &&
          credentialReference == other.credentialReference &&
          paListEquals(scope, other.scope) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        authenticationId,
        authenticationType,
        identityId,
        credentialReference,
        Object.hashAll(scope),
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudIdentityReference {
  const PersistentArtifactCloudIdentityReference({
    required this.identityId,
    required this.identityType,
    required this.subjectReference,
    required this.tenantId,
    this.metadata = const {},
  });

  final String identityId;
  final CloudIdentityType identityType;
  final String subjectReference;
  final String tenantId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'identityId': identityId,
        'identityType': identityType.wireName,
        'subjectReference': subjectReference,
        'tenantId': tenantId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudIdentityReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudIdentityReference(
      identityId: json['identityId'] as String,
      identityType:
          CloudIdentityTypeX.fromWireName(json['identityType'] as String),
      subjectReference: json['subjectReference'] as String,
      tenantId: json['tenantId'] as String,
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'identityId': identityId,
        'identityType': identityType.wireName,
        'subjectReference': subjectReference,
        'tenantId': tenantId,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudIdentityReference copyWith({
    String? identityId,
    CloudIdentityType? identityType,
    String? subjectReference,
    String? tenantId,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudIdentityReference(
      identityId: identityId ?? this.identityId,
      identityType: identityType ?? this.identityType,
      subjectReference: subjectReference ?? this.subjectReference,
      tenantId: tenantId ?? this.tenantId,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudIdentityReference &&
          identityId == other.identityId &&
          identityType == other.identityType &&
          subjectReference == other.subjectReference &&
          tenantId == other.tenantId &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        identityId,
        identityType,
        subjectReference,
        tenantId,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudEncryptionCapability {
  const PersistentArtifactCloudEncryptionCapability({
    required this.mode,
    required this.atRest,
    required this.inTransit,
    this.keyRotationDays,
    this.metadata = const {},
  });

  final CloudEncryptionMode mode;
  final bool atRest;
  final bool inTransit;
  final int? keyRotationDays;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'mode': mode.wireName,
        'atRest': atRest,
        'inTransit': inTransit,
        if (keyRotationDays != null) 'keyRotationDays': keyRotationDays,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudEncryptionCapability.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudEncryptionCapability(
      mode: CloudEncryptionModeX.fromWireName(json['mode'] as String),
      atRest: json['atRest'] as bool? ?? true,
      inTransit: json['inTransit'] as bool? ?? true,
      keyRotationDays: json['keyRotationDays'] as int?,
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'mode': mode.wireName,
        'atRest': atRest,
        'inTransit': inTransit,
        if (keyRotationDays != null) 'keyRotationDays': keyRotationDays,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudEncryptionCapability copyWith({
    CloudEncryptionMode? mode,
    bool? atRest,
    bool? inTransit,
    int? keyRotationDays,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudEncryptionCapability(
      mode: mode ?? this.mode,
      atRest: atRest ?? this.atRest,
      inTransit: inTransit ?? this.inTransit,
      keyRotationDays: keyRotationDays ?? this.keyRotationDays,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudEncryptionCapability &&
          mode == other.mode &&
          atRest == other.atRest &&
          inTransit == other.inTransit &&
          keyRotationDays == other.keyRotationDays &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        mode,
        atRest,
        inTransit,
        keyRotationDays,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudDurabilityDescriptor {
  const PersistentArtifactCloudDurabilityDescriptor({
    required this.minimumReplicas,
    required this.failureDomainDiversity,
    required this.expectedAvailabilityPercent,
    this.metadata = const {},
  });

  final int minimumReplicas;
  final int failureDomainDiversity;
  final double expectedAvailabilityPercent;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'minimumReplicas': minimumReplicas,
        'failureDomainDiversity': failureDomainDiversity,
        'expectedAvailabilityPercent': expectedAvailabilityPercent,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudDurabilityDescriptor.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudDurabilityDescriptor(
      minimumReplicas: json['minimumReplicas'] as int,
      failureDomainDiversity: json['failureDomainDiversity'] as int,
      expectedAvailabilityPercent:
          (json['expectedAvailabilityPercent'] as num).toDouble(),
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'minimumReplicas': minimumReplicas,
        'failureDomainDiversity': failureDomainDiversity,
        'expectedAvailabilityPercent': expectedAvailabilityPercent,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudDurabilityDescriptor copyWith({
    int? minimumReplicas,
    int? failureDomainDiversity,
    double? expectedAvailabilityPercent,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudDurabilityDescriptor(
      minimumReplicas: minimumReplicas ?? this.minimumReplicas,
      failureDomainDiversity:
          failureDomainDiversity ?? this.failureDomainDiversity,
      expectedAvailabilityPercent:
          expectedAvailabilityPercent ?? this.expectedAvailabilityPercent,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudDurabilityDescriptor &&
          minimumReplicas == other.minimumReplicas &&
          failureDomainDiversity == other.failureDomainDiversity &&
          expectedAvailabilityPercent == other.expectedAvailabilityPercent &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        minimumReplicas,
        failureDomainDiversity,
        expectedAvailabilityPercent,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudReplicationDescriptor {
  const PersistentArtifactCloudReplicationDescriptor({
    required this.mode,
    required this.sourceRegionId,
    this.targetRegionIds = const [],
    this.maxLagSeconds,
    this.metadata = const {},
  });

  final CloudReplicationMode mode;
  final String sourceRegionId;
  final List<String> targetRegionIds;
  final int? maxLagSeconds;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'mode': mode.wireName,
        'sourceRegionId': sourceRegionId,
        if (targetRegionIds.isNotEmpty) 'targetRegionIds': targetRegionIds,
        if (maxLagSeconds != null) 'maxLagSeconds': maxLagSeconds,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudReplicationDescriptor.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudReplicationDescriptor(
      mode: CloudReplicationModeX.fromWireName(json['mode'] as String),
      sourceRegionId: json['sourceRegionId'] as String,
      targetRegionIds: _stringList(json['targetRegionIds']),
      maxLagSeconds: json['maxLagSeconds'] as int?,
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'mode': mode.wireName,
        'sourceRegionId': sourceRegionId,
        if (targetRegionIds.isNotEmpty)
          'targetRegionIds': List<String>.from(targetRegionIds)..sort(),
        if (maxLagSeconds != null) 'maxLagSeconds': maxLagSeconds,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudReplicationDescriptor copyWith({
    CloudReplicationMode? mode,
    String? sourceRegionId,
    List<String>? targetRegionIds,
    int? maxLagSeconds,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudReplicationDescriptor(
      mode: mode ?? this.mode,
      sourceRegionId: sourceRegionId ?? this.sourceRegionId,
      targetRegionIds: targetRegionIds ?? this.targetRegionIds,
      maxLagSeconds: maxLagSeconds ?? this.maxLagSeconds,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudReplicationDescriptor &&
          mode == other.mode &&
          sourceRegionId == other.sourceRegionId &&
          paListEquals(targetRegionIds, other.targetRegionIds) &&
          maxLagSeconds == other.maxLagSeconds &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        mode,
        sourceRegionId,
        Object.hashAll(targetRegionIds),
        maxLagSeconds,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudConsistencyCapability {
  const PersistentArtifactCloudConsistencyCapability({
    required this.readConsistency,
    required this.writeConsistency,
    required this.supportsConditionalWrites,
    this.metadata = const {},
  });

  final CloudConsistencyLevel readConsistency;
  final CloudConsistencyLevel writeConsistency;
  final bool supportsConditionalWrites;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'readConsistency': readConsistency.wireName,
        'writeConsistency': writeConsistency.wireName,
        'supportsConditionalWrites': supportsConditionalWrites,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudConsistencyCapability.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudConsistencyCapability(
      readConsistency: CloudConsistencyLevelX.fromWireName(
          json['readConsistency'] as String),
      writeConsistency: CloudConsistencyLevelX.fromWireName(
        json['writeConsistency'] as String,
      ),
      supportsConditionalWrites:
          json['supportsConditionalWrites'] as bool? ?? true,
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'readConsistency': readConsistency.wireName,
        'writeConsistency': writeConsistency.wireName,
        'supportsConditionalWrites': supportsConditionalWrites,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudConsistencyCapability copyWith({
    CloudConsistencyLevel? readConsistency,
    CloudConsistencyLevel? writeConsistency,
    bool? supportsConditionalWrites,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudConsistencyCapability(
      readConsistency: readConsistency ?? this.readConsistency,
      writeConsistency: writeConsistency ?? this.writeConsistency,
      supportsConditionalWrites:
          supportsConditionalWrites ?? this.supportsConditionalWrites,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudConsistencyCapability &&
          readConsistency == other.readConsistency &&
          writeConsistency == other.writeConsistency &&
          supportsConditionalWrites == other.supportsConditionalWrites &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        readConsistency,
        writeConsistency,
        supportsConditionalWrites,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudMultipartUpload {
  const PersistentArtifactCloudMultipartUpload({
    required this.multipartId,
    required this.objectId,
    required this.status,
    required this.partSizeBytes,
    this.uploadedPartNumbers = const [],
    this.metadata = const {},
  });

  final String multipartId;
  final String objectId;
  final CloudMultipartStatus status;
  final int partSizeBytes;
  final List<int> uploadedPartNumbers;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'multipartId': multipartId,
        'objectId': objectId,
        'status': status.wireName,
        'partSizeBytes': partSizeBytes,
        if (uploadedPartNumbers.isNotEmpty)
          'uploadedPartNumbers': uploadedPartNumbers,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudMultipartUpload.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudMultipartUpload(
      multipartId: json['multipartId'] as String,
      objectId: json['objectId'] as String,
      status: CloudMultipartStatusX.fromWireName(json['status'] as String),
      partSizeBytes: json['partSizeBytes'] as int,
      uploadedPartNumbers: List.unmodifiable(
        (json['uploadedPartNumbers'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toInt()),
      ),
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'multipartId': multipartId,
        'objectId': objectId,
        'status': status.wireName,
        'partSizeBytes': partSizeBytes,
        if (uploadedPartNumbers.isNotEmpty)
          'uploadedPartNumbers': List<int>.from(uploadedPartNumbers)..sort(),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudMultipartUpload copyWith({
    String? multipartId,
    String? objectId,
    CloudMultipartStatus? status,
    int? partSizeBytes,
    List<int>? uploadedPartNumbers,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudMultipartUpload(
      multipartId: multipartId ?? this.multipartId,
      objectId: objectId ?? this.objectId,
      status: status ?? this.status,
      partSizeBytes: partSizeBytes ?? this.partSizeBytes,
      uploadedPartNumbers: uploadedPartNumbers ?? this.uploadedPartNumbers,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudMultipartUpload &&
          multipartId == other.multipartId &&
          objectId == other.objectId &&
          status == other.status &&
          partSizeBytes == other.partSizeBytes &&
          paListEquals(uploadedPartNumbers, other.uploadedPartNumbers) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        multipartId,
        objectId,
        status,
        partSizeBytes,
        Object.hashAll(uploadedPartNumbers),
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudMultipartPart {
  const PersistentArtifactCloudMultipartPart({
    required this.partNumber,
    required this.sizeBytes,
    required this.etag,
    this.checksum,
    this.metadata = const {},
  });

  final int partNumber;
  final int sizeBytes;
  final String etag;
  final String? checksum;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'partNumber': partNumber,
        'sizeBytes': sizeBytes,
        'etag': etag,
        if (checksum != null) 'checksum': checksum,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudMultipartPart.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudMultipartPart(
      partNumber: json['partNumber'] as int,
      sizeBytes: json['sizeBytes'] as int,
      etag: json['etag'] as String,
      checksum: json['checksum'] as String?,
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'partNumber': partNumber,
        'sizeBytes': sizeBytes,
        'etag': etag,
        if (checksum != null) 'checksum': checksum,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudMultipartPart copyWith({
    int? partNumber,
    int? sizeBytes,
    String? etag,
    String? checksum,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudMultipartPart(
      partNumber: partNumber ?? this.partNumber,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      etag: etag ?? this.etag,
      checksum: checksum ?? this.checksum,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudMultipartPart &&
          partNumber == other.partNumber &&
          sizeBytes == other.sizeBytes &&
          etag == other.etag &&
          checksum == other.checksum &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        partNumber,
        sizeBytes,
        etag,
        checksum,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudRetryPolicy {
  const PersistentArtifactCloudRetryPolicy({
    required this.maxAttempts,
    required this.baseDelayMs,
    required this.maxDelayMs,
    required this.retryableClassifications,
    this.metadata = const {},
  });

  final int maxAttempts;
  final int baseDelayMs;
  final int maxDelayMs;
  final List<CloudRetryClassification> retryableClassifications;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'maxAttempts': maxAttempts,
        'baseDelayMs': baseDelayMs,
        'maxDelayMs': maxDelayMs,
        'retryableClassifications':
            retryableClassifications.map((e) => e.wireName).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudRetryPolicy.fromJson(
      Map<String, dynamic> json) {
    return PersistentArtifactCloudRetryPolicy(
      maxAttempts: json['maxAttempts'] as int,
      baseDelayMs: json['baseDelayMs'] as int,
      maxDelayMs: json['maxDelayMs'] as int,
      retryableClassifications: List.unmodifiable(
        (json['retryableClassifications'] as List<dynamic>? ?? [])
            .map((e) => CloudRetryClassificationX.fromWireName(e.toString())),
      ),
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'maxAttempts': maxAttempts,
        'baseDelayMs': baseDelayMs,
        'maxDelayMs': maxDelayMs,
        'retryableClassifications':
            retryableClassifications.map((e) => e.wireName).toList()..sort(),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudRetryPolicy copyWith({
    int? maxAttempts,
    int? baseDelayMs,
    int? maxDelayMs,
    List<CloudRetryClassification>? retryableClassifications,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudRetryPolicy(
      maxAttempts: maxAttempts ?? this.maxAttempts,
      baseDelayMs: baseDelayMs ?? this.baseDelayMs,
      maxDelayMs: maxDelayMs ?? this.maxDelayMs,
      retryableClassifications:
          retryableClassifications ?? this.retryableClassifications,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudRetryPolicy &&
          maxAttempts == other.maxAttempts &&
          baseDelayMs == other.baseDelayMs &&
          maxDelayMs == other.maxDelayMs &&
          paListEquals(
              retryableClassifications, other.retryableClassifications) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        maxAttempts,
        baseDelayMs,
        maxDelayMs,
        Object.hashAll(retryableClassifications),
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudTimeoutPolicy {
  const PersistentArtifactCloudTimeoutPolicy({
    required this.connectTimeoutMs,
    required this.readTimeoutMs,
    required this.writeTimeoutMs,
    this.metadata = const {},
  });

  final int connectTimeoutMs;
  final int readTimeoutMs;
  final int writeTimeoutMs;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'connectTimeoutMs': connectTimeoutMs,
        'readTimeoutMs': readTimeoutMs,
        'writeTimeoutMs': writeTimeoutMs,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudTimeoutPolicy.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudTimeoutPolicy(
      connectTimeoutMs: json['connectTimeoutMs'] as int,
      readTimeoutMs: json['readTimeoutMs'] as int,
      writeTimeoutMs: json['writeTimeoutMs'] as int,
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'connectTimeoutMs': connectTimeoutMs,
        'readTimeoutMs': readTimeoutMs,
        'writeTimeoutMs': writeTimeoutMs,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudTimeoutPolicy copyWith({
    int? connectTimeoutMs,
    int? readTimeoutMs,
    int? writeTimeoutMs,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudTimeoutPolicy(
      connectTimeoutMs: connectTimeoutMs ?? this.connectTimeoutMs,
      readTimeoutMs: readTimeoutMs ?? this.readTimeoutMs,
      writeTimeoutMs: writeTimeoutMs ?? this.writeTimeoutMs,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudTimeoutPolicy &&
          connectTimeoutMs == other.connectTimeoutMs &&
          readTimeoutMs == other.readTimeoutMs &&
          writeTimeoutMs == other.writeTimeoutMs &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        connectTimeoutMs,
        readTimeoutMs,
        writeTimeoutMs,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudOperationRequest {
  const PersistentArtifactCloudOperationRequest({
    required this.requestId,
    required this.backendId,
    required this.operationType,
    this.objectReference,
    this.destinationObjectReference,
    this.expectedVersionReference,
    this.multipartUpload,
    this.retryPolicy,
    this.timeoutPolicy,
    this.metadata = const {},
  });

  final String requestId;
  final String backendId;
  final CloudOperationType operationType;
  final PersistentArtifactCloudObjectReference? objectReference;
  final PersistentArtifactCloudObjectReference? destinationObjectReference;
  final PersistentArtifactCloudObjectVersionReference? expectedVersionReference;
  final PersistentArtifactCloudMultipartUpload? multipartUpload;
  final PersistentArtifactCloudRetryPolicy? retryPolicy;
  final PersistentArtifactCloudTimeoutPolicy? timeoutPolicy;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'backendId': backendId,
        'operationType': operationType.wireName,
        if (objectReference != null)
          'objectReference': objectReference!.toJson(),
        if (destinationObjectReference != null)
          'destinationObjectReference': destinationObjectReference!.toJson(),
        if (expectedVersionReference != null)
          'expectedVersionReference': expectedVersionReference!.toJson(),
        if (multipartUpload != null)
          'multipartUpload': multipartUpload!.toJson(),
        if (retryPolicy != null) 'retryPolicy': retryPolicy!.toJson(),
        if (timeoutPolicy != null) 'timeoutPolicy': timeoutPolicy!.toJson(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudOperationRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudOperationRequest(
      requestId: json['requestId'] as String,
      backendId: json['backendId'] as String,
      operationType: CloudOperationTypeX.fromWireName(
        json['operationType'] as String,
      ),
      objectReference: json['objectReference'] == null
          ? null
          : PersistentArtifactCloudObjectReference.fromJson(
              json['objectReference'] as Map<String, dynamic>,
            ),
      destinationObjectReference: json['destinationObjectReference'] == null
          ? null
          : PersistentArtifactCloudObjectReference.fromJson(
              json['destinationObjectReference'] as Map<String, dynamic>,
            ),
      expectedVersionReference: json['expectedVersionReference'] == null
          ? null
          : PersistentArtifactCloudObjectVersionReference.fromJson(
              json['expectedVersionReference'] as Map<String, dynamic>,
            ),
      multipartUpload: json['multipartUpload'] == null
          ? null
          : PersistentArtifactCloudMultipartUpload.fromJson(
              json['multipartUpload'] as Map<String, dynamic>,
            ),
      retryPolicy: json['retryPolicy'] == null
          ? null
          : PersistentArtifactCloudRetryPolicy.fromJson(
              json['retryPolicy'] as Map<String, dynamic>,
            ),
      timeoutPolicy: json['timeoutPolicy'] == null
          ? null
          : PersistentArtifactCloudTimeoutPolicy.fromJson(
              json['timeoutPolicy'] as Map<String, dynamic>,
            ),
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'requestId': requestId,
        'backendId': backendId,
        'operationType': operationType.wireName,
        if (objectReference != null)
          'objectReference': objectReference!.toComparableJson(),
        if (destinationObjectReference != null)
          'destinationObjectReference':
              destinationObjectReference!.toComparableJson(),
        if (expectedVersionReference != null)
          'expectedVersionReference':
              expectedVersionReference!.toComparableJson(),
        if (multipartUpload != null)
          'multipartUpload': multipartUpload!.toComparableJson(),
        if (retryPolicy != null) 'retryPolicy': retryPolicy!.toComparableJson(),
        if (timeoutPolicy != null)
          'timeoutPolicy': timeoutPolicy!.toComparableJson(),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudOperationRequest copyWith({
    String? requestId,
    String? backendId,
    CloudOperationType? operationType,
    PersistentArtifactCloudObjectReference? objectReference,
    PersistentArtifactCloudObjectReference? destinationObjectReference,
    PersistentArtifactCloudObjectVersionReference? expectedVersionReference,
    PersistentArtifactCloudMultipartUpload? multipartUpload,
    PersistentArtifactCloudRetryPolicy? retryPolicy,
    PersistentArtifactCloudTimeoutPolicy? timeoutPolicy,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudOperationRequest(
      requestId: requestId ?? this.requestId,
      backendId: backendId ?? this.backendId,
      operationType: operationType ?? this.operationType,
      objectReference: objectReference ?? this.objectReference,
      destinationObjectReference:
          destinationObjectReference ?? this.destinationObjectReference,
      expectedVersionReference:
          expectedVersionReference ?? this.expectedVersionReference,
      multipartUpload: multipartUpload ?? this.multipartUpload,
      retryPolicy: retryPolicy ?? this.retryPolicy,
      timeoutPolicy: timeoutPolicy ?? this.timeoutPolicy,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudOperationRequest &&
          requestId == other.requestId &&
          backendId == other.backendId &&
          operationType == other.operationType &&
          objectReference == other.objectReference &&
          destinationObjectReference == other.destinationObjectReference &&
          expectedVersionReference == other.expectedVersionReference &&
          multipartUpload == other.multipartUpload &&
          retryPolicy == other.retryPolicy &&
          timeoutPolicy == other.timeoutPolicy &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        requestId,
        backendId,
        operationType,
        objectReference,
        destinationObjectReference,
        expectedVersionReference,
        multipartUpload,
        retryPolicy,
        timeoutPolicy,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudIssue {
  const PersistentArtifactCloudIssue({
    required this.code,
    required this.message,
    required this.severity,
    this.path,
    this.metadata = const {},
  });

  final String code;
  final String message;
  final CloudIssueSeverity severity;
  final String? path;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        'severity': severity.wireName,
        if (path != null) 'path': path,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudIssue.fromJson(Map<String, dynamic> json) {
    return PersistentArtifactCloudIssue(
      code: json['code'] as String,
      message: json['message'] as String,
      severity: CloudIssueSeverityX.fromWireName(json['severity'] as String),
      path: json['path'] as String?,
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'code': code,
        'message': message,
        'severity': severity.wireName,
        if (path != null) 'path': path,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudIssue copyWith({
    String? code,
    String? message,
    CloudIssueSeverity? severity,
    String? path,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudIssue(
      code: code ?? this.code,
      message: message ?? this.message,
      severity: severity ?? this.severity,
      path: path ?? this.path,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudIssue &&
          code == other.code &&
          message == other.message &&
          severity == other.severity &&
          path == other.path &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        code,
        message,
        severity,
        path,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudOperationResult {
  const PersistentArtifactCloudOperationResult({
    required this.requestId,
    required this.operationType,
    required this.status,
    this.objectReference,
    this.versionReference,
    this.multipartStatus,
    this.issues = const [],
    this.metadata = const {},
  });

  final String requestId;
  final CloudOperationType operationType;
  final CloudOperationStatus status;
  final PersistentArtifactCloudObjectReference? objectReference;
  final PersistentArtifactCloudObjectVersionReference? versionReference;
  final CloudMultipartStatus? multipartStatus;
  final List<PersistentArtifactCloudIssue> issues;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'operationType': operationType.wireName,
        'status': status.wireName,
        if (objectReference != null)
          'objectReference': objectReference!.toJson(),
        if (versionReference != null)
          'versionReference': versionReference!.toJson(),
        if (multipartStatus != null)
          'multipartStatus': multipartStatus!.wireName,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudOperationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudOperationResult(
      requestId: json['requestId'] as String,
      operationType: CloudOperationTypeX.fromWireName(
        json['operationType'] as String,
      ),
      status: CloudOperationStatusX.fromWireName(json['status'] as String),
      objectReference: json['objectReference'] == null
          ? null
          : PersistentArtifactCloudObjectReference.fromJson(
              json['objectReference'] as Map<String, dynamic>,
            ),
      versionReference: json['versionReference'] == null
          ? null
          : PersistentArtifactCloudObjectVersionReference.fromJson(
              json['versionReference'] as Map<String, dynamic>,
            ),
      multipartStatus: json['multipartStatus'] == null
          ? null
          : CloudMultipartStatusX.fromWireName(
              json['multipartStatus'] as String),
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map((e) => PersistentArtifactCloudIssue.fromJson(
                  e as Map<String, dynamic>,
                ))
            .toList(),
      ),
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'requestId': requestId,
        'operationType': operationType.wireName,
        'status': status.wireName,
        if (objectReference != null)
          'objectReference': objectReference!.toComparableJson(),
        if (versionReference != null)
          'versionReference': versionReference!.toComparableJson(),
        if (multipartStatus != null)
          'multipartStatus': multipartStatus!.wireName,
        if (issues.isNotEmpty)
          'issues': paSortedComparableList(
            issues.map((e) => e.toComparableJson()),
            'code',
          ),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudOperationResult copyWith({
    String? requestId,
    CloudOperationType? operationType,
    CloudOperationStatus? status,
    PersistentArtifactCloudObjectReference? objectReference,
    PersistentArtifactCloudObjectVersionReference? versionReference,
    CloudMultipartStatus? multipartStatus,
    List<PersistentArtifactCloudIssue>? issues,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudOperationResult(
      requestId: requestId ?? this.requestId,
      operationType: operationType ?? this.operationType,
      status: status ?? this.status,
      objectReference: objectReference ?? this.objectReference,
      versionReference: versionReference ?? this.versionReference,
      multipartStatus: multipartStatus ?? this.multipartStatus,
      issues: issues ?? this.issues,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudOperationResult &&
          requestId == other.requestId &&
          operationType == other.operationType &&
          status == other.status &&
          objectReference == other.objectReference &&
          versionReference == other.versionReference &&
          multipartStatus == other.multipartStatus &&
          paListEquals(issues, other.issues) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        requestId,
        operationType,
        status,
        objectReference,
        versionReference,
        multipartStatus,
        Object.hashAll(issues),
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudBackendDescriptor {
  const PersistentArtifactCloudBackendDescriptor({
    required this.backendId,
    required this.providerType,
    required this.serviceType,
    required this.endpoint,
    required this.region,
    required this.container,
    required this.encryption,
    required this.replication,
    required this.consistency,
    required this.retryPolicy,
    required this.timeoutPolicy,
    this.failureDomain,
    this.authentication,
    this.identity,
    this.productionEligible = false,
    this.stagingEligible = false,
    this.metadata = const {},
  });

  final String backendId;
  final PersistentArtifactCloudProviderType providerType;
  final CloudServiceType serviceType;
  final PersistentArtifactCloudEndpointReference endpoint;
  final PersistentArtifactCloudRegionReference region;
  final PersistentArtifactCloudContainerReference container;
  final PersistentArtifactCloudEncryptionCapability encryption;
  final PersistentArtifactCloudReplicationDescriptor replication;
  final PersistentArtifactCloudConsistencyCapability consistency;
  final PersistentArtifactCloudRetryPolicy retryPolicy;
  final PersistentArtifactCloudTimeoutPolicy timeoutPolicy;
  final PersistentArtifactCloudFailureDomainReference? failureDomain;
  final PersistentArtifactCloudAuthenticationReference? authentication;
  final PersistentArtifactCloudIdentityReference? identity;
  final bool productionEligible;
  final bool stagingEligible;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'backendId': backendId,
        'providerType': providerType.wireName,
        'serviceType': serviceType.wireName,
        'endpoint': endpoint.toJson(),
        'region': region.toJson(),
        'container': container.toJson(),
        'encryption': encryption.toJson(),
        'replication': replication.toJson(),
        'consistency': consistency.toJson(),
        'retryPolicy': retryPolicy.toJson(),
        'timeoutPolicy': timeoutPolicy.toJson(),
        if (failureDomain != null) 'failureDomain': failureDomain!.toJson(),
        if (authentication != null) 'authentication': authentication!.toJson(),
        if (identity != null) 'identity': identity!.toJson(),
        'productionEligible': productionEligible,
        'stagingEligible': stagingEligible,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudBackendDescriptor.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudBackendDescriptor(
      backendId: json['backendId'] as String,
      providerType: PersistentArtifactCloudProviderTypeX.fromWireName(
        json['providerType'] as String,
      ),
      serviceType:
          CloudServiceTypeX.fromWireName(json['serviceType'] as String),
      endpoint: PersistentArtifactCloudEndpointReference.fromJson(
        json['endpoint'] as Map<String, dynamic>,
      ),
      region: PersistentArtifactCloudRegionReference.fromJson(
        json['region'] as Map<String, dynamic>,
      ),
      container: PersistentArtifactCloudContainerReference.fromJson(
        json['container'] as Map<String, dynamic>,
      ),
      encryption: PersistentArtifactCloudEncryptionCapability.fromJson(
        json['encryption'] as Map<String, dynamic>,
      ),
      replication: PersistentArtifactCloudReplicationDescriptor.fromJson(
        json['replication'] as Map<String, dynamic>,
      ),
      consistency: PersistentArtifactCloudConsistencyCapability.fromJson(
        json['consistency'] as Map<String, dynamic>,
      ),
      retryPolicy: PersistentArtifactCloudRetryPolicy.fromJson(
        json['retryPolicy'] as Map<String, dynamic>,
      ),
      timeoutPolicy: PersistentArtifactCloudTimeoutPolicy.fromJson(
        json['timeoutPolicy'] as Map<String, dynamic>,
      ),
      failureDomain: json['failureDomain'] == null
          ? null
          : PersistentArtifactCloudFailureDomainReference.fromJson(
              json['failureDomain'] as Map<String, dynamic>,
            ),
      authentication: json['authentication'] == null
          ? null
          : PersistentArtifactCloudAuthenticationReference.fromJson(
              json['authentication'] as Map<String, dynamic>,
            ),
      identity: json['identity'] == null
          ? null
          : PersistentArtifactCloudIdentityReference.fromJson(
              json['identity'] as Map<String, dynamic>,
            ),
      productionEligible: json['productionEligible'] as bool? ?? false,
      stagingEligible: json['stagingEligible'] as bool? ?? false,
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'backendId': backendId,
        'providerType': providerType.wireName,
        'serviceType': serviceType.wireName,
        'endpoint': endpoint.toComparableJson(),
        'region': region.toComparableJson(),
        'container': container.toComparableJson(),
        'encryption': encryption.toComparableJson(),
        'replication': replication.toComparableJson(),
        'consistency': consistency.toComparableJson(),
        'retryPolicy': retryPolicy.toComparableJson(),
        'timeoutPolicy': timeoutPolicy.toComparableJson(),
        if (failureDomain != null)
          'failureDomain': failureDomain!.toComparableJson(),
        if (authentication != null)
          'authentication': authentication!.toComparableJson(),
        if (identity != null) 'identity': identity!.toComparableJson(),
        'productionEligible': productionEligible,
        'stagingEligible': stagingEligible,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudBackendDescriptor copyWith({
    String? backendId,
    PersistentArtifactCloudProviderType? providerType,
    CloudServiceType? serviceType,
    PersistentArtifactCloudEndpointReference? endpoint,
    PersistentArtifactCloudRegionReference? region,
    PersistentArtifactCloudContainerReference? container,
    PersistentArtifactCloudEncryptionCapability? encryption,
    PersistentArtifactCloudReplicationDescriptor? replication,
    PersistentArtifactCloudConsistencyCapability? consistency,
    PersistentArtifactCloudRetryPolicy? retryPolicy,
    PersistentArtifactCloudTimeoutPolicy? timeoutPolicy,
    PersistentArtifactCloudFailureDomainReference? failureDomain,
    PersistentArtifactCloudAuthenticationReference? authentication,
    PersistentArtifactCloudIdentityReference? identity,
    bool? productionEligible,
    bool? stagingEligible,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudBackendDescriptor(
      backendId: backendId ?? this.backendId,
      providerType: providerType ?? this.providerType,
      serviceType: serviceType ?? this.serviceType,
      endpoint: endpoint ?? this.endpoint,
      region: region ?? this.region,
      container: container ?? this.container,
      encryption: encryption ?? this.encryption,
      replication: replication ?? this.replication,
      consistency: consistency ?? this.consistency,
      retryPolicy: retryPolicy ?? this.retryPolicy,
      timeoutPolicy: timeoutPolicy ?? this.timeoutPolicy,
      failureDomain: failureDomain ?? this.failureDomain,
      authentication: authentication ?? this.authentication,
      identity: identity ?? this.identity,
      productionEligible: productionEligible ?? this.productionEligible,
      stagingEligible: stagingEligible ?? this.stagingEligible,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudBackendDescriptor &&
          backendId == other.backendId &&
          providerType == other.providerType &&
          serviceType == other.serviceType &&
          endpoint == other.endpoint &&
          region == other.region &&
          container == other.container &&
          encryption == other.encryption &&
          replication == other.replication &&
          consistency == other.consistency &&
          retryPolicy == other.retryPolicy &&
          timeoutPolicy == other.timeoutPolicy &&
          failureDomain == other.failureDomain &&
          authentication == other.authentication &&
          identity == other.identity &&
          productionEligible == other.productionEligible &&
          stagingEligible == other.stagingEligible &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        backendId,
        providerType,
        serviceType,
        endpoint,
        region,
        container,
        encryption,
        replication,
        consistency,
        retryPolicy,
        timeoutPolicy,
        failureDomain,
        authentication,
        identity,
        productionEligible,
        stagingEligible,
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudStagingPromotionCriteria {
  const PersistentArtifactCloudStagingPromotionCriteria({
    required this.criteriaId,
    required this.minimumDurability,
    required this.requiredReplicationMode,
    required this.requiredReadConsistency,
    required this.requireEncryptionAtRest,
    required this.requireEncryptionInTransit,
    this.maxAllowedIssues = 0,
    this.requiredMetadataKeys = const [],
    this.metadata = const {},
  });

  final String criteriaId;
  final PersistentArtifactCloudDurabilityDescriptor minimumDurability;
  final CloudReplicationMode requiredReplicationMode;
  final CloudConsistencyLevel requiredReadConsistency;
  final bool requireEncryptionAtRest;
  final bool requireEncryptionInTransit;
  final int maxAllowedIssues;
  final List<String> requiredMetadataKeys;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'criteriaId': criteriaId,
        'minimumDurability': minimumDurability.toJson(),
        'requiredReplicationMode': requiredReplicationMode.wireName,
        'requiredReadConsistency': requiredReadConsistency.wireName,
        'requireEncryptionAtRest': requireEncryptionAtRest,
        'requireEncryptionInTransit': requireEncryptionInTransit,
        'maxAllowedIssues': maxAllowedIssues,
        if (requiredMetadataKeys.isNotEmpty)
          'requiredMetadataKeys': requiredMetadataKeys,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudStagingPromotionCriteria.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudStagingPromotionCriteria(
      criteriaId: json['criteriaId'] as String,
      minimumDurability: PersistentArtifactCloudDurabilityDescriptor.fromJson(
        json['minimumDurability'] as Map<String, dynamic>,
      ),
      requiredReplicationMode: CloudReplicationModeX.fromWireName(
        json['requiredReplicationMode'] as String,
      ),
      requiredReadConsistency: CloudConsistencyLevelX.fromWireName(
        json['requiredReadConsistency'] as String,
      ),
      requireEncryptionAtRest: json['requireEncryptionAtRest'] as bool,
      requireEncryptionInTransit: json['requireEncryptionInTransit'] as bool,
      maxAllowedIssues: json['maxAllowedIssues'] as int? ?? 0,
      requiredMetadataKeys: _stringList(json['requiredMetadataKeys']),
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'criteriaId': criteriaId,
        'minimumDurability': minimumDurability.toComparableJson(),
        'requiredReplicationMode': requiredReplicationMode.wireName,
        'requiredReadConsistency': requiredReadConsistency.wireName,
        'requireEncryptionAtRest': requireEncryptionAtRest,
        'requireEncryptionInTransit': requireEncryptionInTransit,
        'maxAllowedIssues': maxAllowedIssues,
        if (requiredMetadataKeys.isNotEmpty)
          'requiredMetadataKeys': List<String>.from(requiredMetadataKeys)
            ..sort(),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudStagingPromotionCriteria copyWith({
    String? criteriaId,
    PersistentArtifactCloudDurabilityDescriptor? minimumDurability,
    CloudReplicationMode? requiredReplicationMode,
    CloudConsistencyLevel? requiredReadConsistency,
    bool? requireEncryptionAtRest,
    bool? requireEncryptionInTransit,
    int? maxAllowedIssues,
    List<String>? requiredMetadataKeys,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudStagingPromotionCriteria(
      criteriaId: criteriaId ?? this.criteriaId,
      minimumDurability: minimumDurability ?? this.minimumDurability,
      requiredReplicationMode:
          requiredReplicationMode ?? this.requiredReplicationMode,
      requiredReadConsistency:
          requiredReadConsistency ?? this.requiredReadConsistency,
      requireEncryptionAtRest:
          requireEncryptionAtRest ?? this.requireEncryptionAtRest,
      requireEncryptionInTransit:
          requireEncryptionInTransit ?? this.requireEncryptionInTransit,
      maxAllowedIssues: maxAllowedIssues ?? this.maxAllowedIssues,
      requiredMetadataKeys: requiredMetadataKeys ?? this.requiredMetadataKeys,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudStagingPromotionCriteria &&
          criteriaId == other.criteriaId &&
          minimumDurability == other.minimumDurability &&
          requiredReplicationMode == other.requiredReplicationMode &&
          requiredReadConsistency == other.requiredReadConsistency &&
          requireEncryptionAtRest == other.requireEncryptionAtRest &&
          requireEncryptionInTransit == other.requireEncryptionInTransit &&
          maxAllowedIssues == other.maxAllowedIssues &&
          paListEquals(requiredMetadataKeys, other.requiredMetadataKeys) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        criteriaId,
        minimumDurability,
        requiredReplicationMode,
        requiredReadConsistency,
        requireEncryptionAtRest,
        requireEncryptionInTransit,
        maxAllowedIssues,
        Object.hashAll(requiredMetadataKeys),
        Object.hashAll(metadata.entries),
      );
}

class PersistentArtifactCloudStagingReadinessDecision {
  const PersistentArtifactCloudStagingReadinessDecision({
    required this.backendId,
    required this.criteriaId,
    required this.status,
    required this.stagingEligible,
    required this.productionEligible,
    required this.approved,
    this.issues = const [],
    this.metadata = const {},
  });

  final String backendId;
  final String criteriaId;
  final CloudPromotionStatus status;
  final bool stagingEligible;
  final bool productionEligible;
  final bool approved;
  final List<PersistentArtifactCloudIssue> issues;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'backendId': backendId,
        'criteriaId': criteriaId,
        'status': status.wireName,
        'stagingEligible': stagingEligible,
        'productionEligible': productionEligible,
        'approved': approved,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactCloudStagingReadinessDecision.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactCloudStagingReadinessDecision(
      backendId: json['backendId'] as String,
      criteriaId: json['criteriaId'] as String,
      status: CloudPromotionStatusX.fromWireName(json['status'] as String),
      stagingEligible: json['stagingEligible'] as bool? ?? false,
      productionEligible: json['productionEligible'] as bool? ?? false,
      approved: json['approved'] as bool? ?? false,
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map((e) => PersistentArtifactCloudIssue.fromJson(
                  e as Map<String, dynamic>,
                ))
            .toList(),
      ),
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'backendId': backendId,
        'criteriaId': criteriaId,
        'status': status.wireName,
        'stagingEligible': stagingEligible,
        'productionEligible': productionEligible,
        'approved': approved,
        if (issues.isNotEmpty)
          'issues': paSortedComparableList(
            issues.map((e) => e.toComparableJson()),
            'code',
          ),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactCloudStagingReadinessDecision copyWith({
    String? backendId,
    String? criteriaId,
    CloudPromotionStatus? status,
    bool? stagingEligible,
    bool? productionEligible,
    bool? approved,
    List<PersistentArtifactCloudIssue>? issues,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactCloudStagingReadinessDecision(
      backendId: backendId ?? this.backendId,
      criteriaId: criteriaId ?? this.criteriaId,
      status: status ?? this.status,
      stagingEligible: stagingEligible ?? this.stagingEligible,
      productionEligible: productionEligible ?? this.productionEligible,
      approved: approved ?? this.approved,
      issues: issues ?? this.issues,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactCloudStagingReadinessDecision &&
          backendId == other.backendId &&
          criteriaId == other.criteriaId &&
          status == other.status &&
          stagingEligible == other.stagingEligible &&
          productionEligible == other.productionEligible &&
          approved == other.approved &&
          paListEquals(issues, other.issues) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        backendId,
        criteriaId,
        status,
        stagingEligible,
        productionEligible,
        approved,
        Object.hashAll(issues),
        Object.hashAll(metadata.entries),
      );
}

Map<String, String> _stringMap(dynamic value) {
  return Map.unmodifiable(
    (value as Map<String, dynamic>? ?? {}).map(
      (key, dynamic value) => MapEntry(key, value.toString()),
    ),
  );
}

List<String> _stringList(dynamic value) {
  return List.unmodifiable(
    (value as List<dynamic>? ?? []).map((e) => e.toString()),
  );
}
