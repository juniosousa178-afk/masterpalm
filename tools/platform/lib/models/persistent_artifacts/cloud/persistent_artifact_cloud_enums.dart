enum PersistentArtifactCloudProviderType {
  s3Compatible,
  googleCloudObjectStorage,
  azureBlobCompatible,
  genericObjectStorage,
  custom,
}

extension PersistentArtifactCloudProviderTypeX
    on PersistentArtifactCloudProviderType {
  String get wireName => name;

  static PersistentArtifactCloudProviderType fromWireName(String value) {
    return PersistentArtifactCloudProviderType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactCloudProviderType: $value',
      ),
    );
  }
}

enum CloudServiceType { objectStorage, metadataCatalog, keyManagement, custom }

extension CloudServiceTypeX on CloudServiceType {
  String get wireName => name;

  static CloudServiceType fromWireName(String value) {
    return CloudServiceType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown CloudServiceType: $value'),
    );
  }
}

enum CloudEndpointType {
  publicApi,
  privateApi,
  controlPlane,
  dataPlane,
  custom
}

extension CloudEndpointTypeX on CloudEndpointType {
  String get wireName => name;

  static CloudEndpointType fromWireName(String value) {
    return CloudEndpointType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown CloudEndpointType: $value'),
    );
  }
}

enum CloudAuthenticationType {
  apiKeyReference,
  oauthReference,
  serviceAccountReference,
  roleAssumptionReference,
  custom,
}

extension CloudAuthenticationTypeX on CloudAuthenticationType {
  String get wireName => name;

  static CloudAuthenticationType fromWireName(String value) {
    return CloudAuthenticationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CloudAuthenticationType: $value'),
    );
  }
}

enum CloudIdentityType {
  tenantScoped,
  workloadIdentity,
  servicePrincipal,
  machineIdentity,
  custom,
}

extension CloudIdentityTypeX on CloudIdentityType {
  String get wireName => name;

  static CloudIdentityType fromWireName(String value) {
    return CloudIdentityType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown CloudIdentityType: $value'),
    );
  }
}

enum CloudEncryptionMode {
  providerManaged,
  customerManaged,
  customerSupplied,
  envelope,
  none,
}

extension CloudEncryptionModeX on CloudEncryptionMode {
  String get wireName => name;

  static CloudEncryptionMode fromWireName(String value) {
    return CloudEncryptionMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CloudEncryptionMode: $value'),
    );
  }
}

enum CloudReplicationMode {
  none,
  singleRegion,
  multiRegion,
  crossRegionAsync,
  crossRegionSync,
  custom,
}

extension CloudReplicationModeX on CloudReplicationMode {
  String get wireName => name;

  static CloudReplicationMode fromWireName(String value) {
    return CloudReplicationMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CloudReplicationMode: $value'),
    );
  }
}

enum CloudConsistencyLevel {
  eventual,
  readAfterWrite,
  boundedStaleness,
  strong,
  custom
}

extension CloudConsistencyLevelX on CloudConsistencyLevel {
  String get wireName => name;

  static CloudConsistencyLevel fromWireName(String value) {
    return CloudConsistencyLevel.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CloudConsistencyLevel: $value'),
    );
  }
}

enum CloudObjectStatus {
  pending,
  available,
  replicated,
  archived,
  deleted,
  unknown,
}

extension CloudObjectStatusX on CloudObjectStatus {
  String get wireName => name;

  static CloudObjectStatus fromWireName(String value) {
    return CloudObjectStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown CloudObjectStatus: $value'),
    );
  }
}

enum CloudOperationType {
  putObject,
  getObject,
  headObject,
  listObjects,
  deleteObject,
  copyObject,
  beginMultipart,
  uploadPart,
  completeMultipart,
  abortMultipart,
}

extension CloudOperationTypeX on CloudOperationType {
  String get wireName => name;

  static CloudOperationType fromWireName(String value) {
    return CloudOperationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown CloudOperationType: $value'),
    );
  }
}

enum CloudOperationStatus { pending, succeeded, partial, failed, blocked }

extension CloudOperationStatusX on CloudOperationStatus {
  String get wireName => name;

  static CloudOperationStatus fromWireName(String value) {
    return CloudOperationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CloudOperationStatus: $value'),
    );
  }
}

enum CloudMultipartStatus {
  initiated,
  uploading,
  completed,
  aborted,
  failed,
}

extension CloudMultipartStatusX on CloudMultipartStatus {
  String get wireName => name;

  static CloudMultipartStatus fromWireName(String value) {
    return CloudMultipartStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CloudMultipartStatus: $value'),
    );
  }
}

enum CloudRetryClassification {
  transient,
  throttled,
  timeout,
  permanent,
  authorization,
  unknown,
}

extension CloudRetryClassificationX on CloudRetryClassification {
  String get wireName => name;

  static CloudRetryClassification fromWireName(String value) {
    return CloudRetryClassification.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CloudRetryClassification: $value',
      ),
    );
  }
}

enum CloudRegionStatus { healthy, degraded, unavailable, maintenance, unknown }

extension CloudRegionStatusX on CloudRegionStatus {
  String get wireName => name;

  static CloudRegionStatus fromWireName(String value) {
    return CloudRegionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown CloudRegionStatus: $value'),
    );
  }
}

enum CloudPromotionStatus { unknown, blocked, ready, approved, rejected }

extension CloudPromotionStatusX on CloudPromotionStatus {
  String get wireName => name;

  static CloudPromotionStatus fromWireName(String value) {
    return CloudPromotionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown CloudPromotionStatus: $value'),
    );
  }
}

enum CloudIssueSeverity { info, warning, critical }

extension CloudIssueSeverityX on CloudIssueSeverity {
  String get wireName => name;

  static CloudIssueSeverity fromWireName(String value) {
    return CloudIssueSeverity.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown CloudIssueSeverity: $value'),
    );
  }
}

enum RealCloudAdapterAdmissionStatus {
  notEvaluated,
  incomplete,
  blocked,
  eligibleForDesignReview,
  approvedForPrototype,
  rejected,
}

extension RealCloudAdapterAdmissionStatusX on RealCloudAdapterAdmissionStatus {
  String get wireName => name;

  static RealCloudAdapterAdmissionStatus fromWireName(String value) {
    return RealCloudAdapterAdmissionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown RealCloudAdapterAdmissionStatus: $value',
      ),
    );
  }
}
