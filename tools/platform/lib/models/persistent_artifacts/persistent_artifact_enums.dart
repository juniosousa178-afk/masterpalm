/// Persistent artifact kind descriptor.
enum PersistentArtifactType {
  releaseEvidence,
  releaseSupplyChain,
  cicdIntegrationSnapshot,
  cryptographicTrustSnapshot,
  report,
  manifest,
  attestation,
  verificationResult,
  dashboardSnapshot,
  historySnapshot,
  goldenArtifact,
  generic,
  unknown,
}

extension PersistentArtifactTypeX on PersistentArtifactType {
  String get wireName => name;

  static PersistentArtifactType fromWireName(String value) {
    return PersistentArtifactType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown PersistentArtifactType: $value'),
    );
  }
}

enum PersistentArtifactFormat {
  json,
  yaml,
  binary,
  text,
  archive,
  protobuf,
  custom,
  unknown,
}

extension PersistentArtifactFormatX on PersistentArtifactFormat {
  String get wireName => name;

  static PersistentArtifactFormat fromWireName(String value) {
    return PersistentArtifactFormat.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown PersistentArtifactFormat: $value'),
    );
  }
}

enum PersistentArtifactEncoding {
  utf8,
  base64,
  hex,
  none,
  unknown,
}

extension PersistentArtifactEncodingX on PersistentArtifactEncoding {
  String get wireName => name;

  static PersistentArtifactEncoding fromWireName(String value) {
    return PersistentArtifactEncoding.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown PersistentArtifactEncoding: $value'),
    );
  }
}

enum PersistentArtifactCompression {
  none,
  gzip,
  zstd,
  brotli,
  custom,
  unknown,
}

extension PersistentArtifactCompressionX on PersistentArtifactCompression {
  String get wireName => name;

  static PersistentArtifactCompression fromWireName(String value) {
    return PersistentArtifactCompression.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactCompression: $value',
      ),
    );
  }
}

enum PersistentArtifactStatus {
  draft,
  active,
  archived,
  invalidated,
  tombstoned,
  unknown,
}

extension PersistentArtifactStatusX on PersistentArtifactStatus {
  String get wireName => name;

  static PersistentArtifactStatus fromWireName(String value) {
    return PersistentArtifactStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown PersistentArtifactStatus: $value'),
    );
  }
}

enum PersistentArtifactLifecycleStatus {
  created,
  published,
  retained,
  expired,
  deletionRequested,
  deleted,
  tombstoned,
  unknown,
}

extension PersistentArtifactLifecycleStatusX
    on PersistentArtifactLifecycleStatus {
  String get wireName => name;

  static PersistentArtifactLifecycleStatus fromWireName(String value) {
    return PersistentArtifactLifecycleStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactLifecycleStatus: $value',
      ),
    );
  }
}

enum PersistentArtifactPublicationStatus {
  pending,
  partial,
  published,
  failed,
  unknown,
}

extension PersistentArtifactPublicationStatusX
    on PersistentArtifactPublicationStatus {
  String get wireName => name;

  static PersistentArtifactPublicationStatus fromWireName(String value) {
    return PersistentArtifactPublicationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactPublicationStatus: $value',
      ),
    );
  }
}

enum PersistentArtifactIntegrityStatus {
  pending,
  declared,
  verified,
  failed,
  unknown,
}

extension PersistentArtifactIntegrityStatusX
    on PersistentArtifactIntegrityStatus {
  String get wireName => name;

  static PersistentArtifactIntegrityStatus fromWireName(String value) {
    return PersistentArtifactIntegrityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactIntegrityStatus: $value',
      ),
    );
  }
}

enum PersistentArtifactAvailabilityStatus {
  available,
  partial,
  unavailable,
  unknown,
}

extension PersistentArtifactAvailabilityStatusX
    on PersistentArtifactAvailabilityStatus {
  String get wireName => name;

  static PersistentArtifactAvailabilityStatus fromWireName(String value) {
    return PersistentArtifactAvailabilityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactAvailabilityStatus: $value',
      ),
    );
  }
}

enum PersistentArtifactStorageClass {
  standard,
  infrequentAccess,
  archive,
  coldArchive,
  custom,
  unknown,
}

extension PersistentArtifactStorageClassX on PersistentArtifactStorageClass {
  String get wireName => name;

  static PersistentArtifactStorageClass fromWireName(String value) {
    return PersistentArtifactStorageClass.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactStorageClass: $value',
      ),
    );
  }
}

enum PersistentArtifactLocationType {
  logicalNamespace,
  objectStore,
  database,
  filesystem,
  archive,
  custom,
  unknown,
}

extension PersistentArtifactLocationTypeX on PersistentArtifactLocationType {
  String get wireName => name;

  static PersistentArtifactLocationType fromWireName(String value) {
    return PersistentArtifactLocationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactLocationType: $value',
      ),
    );
  }
}

enum PersistentArtifactVersionStatus {
  draft,
  active,
  superseded,
  invalidated,
  unknown,
}

extension PersistentArtifactVersionStatusX on PersistentArtifactVersionStatus {
  String get wireName => name;

  static PersistentArtifactVersionStatus fromWireName(String value) {
    return PersistentArtifactVersionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactVersionStatus: $value',
      ),
    );
  }
}

enum PersistentArtifactRetentionAction {
  retain,
  archive,
  delete,
  tombstone,
  unknown,
}

extension PersistentArtifactRetentionActionX
    on PersistentArtifactRetentionAction {
  String get wireName => name;

  static PersistentArtifactRetentionAction fromWireName(String value) {
    return PersistentArtifactRetentionAction.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactRetentionAction: $value',
      ),
    );
  }
}

enum PersistentArtifactDeletionStatus {
  requested,
  blocked,
  completed,
  failed,
  unknown,
}

extension PersistentArtifactDeletionStatusX
    on PersistentArtifactDeletionStatus {
  String get wireName => name;

  static PersistentArtifactDeletionStatus fromWireName(String value) {
    return PersistentArtifactDeletionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactDeletionStatus: $value',
      ),
    );
  }
}

enum PersistentArtifactReplicationStatus {
  pending,
  declared,
  verified,
  failed,
  unknown,
}

extension PersistentArtifactReplicationStatusX
    on PersistentArtifactReplicationStatus {
  String get wireName => name;

  static PersistentArtifactReplicationStatus fromWireName(String value) {
    return PersistentArtifactReplicationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactReplicationStatus: $value',
      ),
    );
  }
}

enum PersistentArtifactDurabilityLevel {
  standard,
  enhanced,
  critical,
  custom,
  unknown,
}

extension PersistentArtifactDurabilityLevelX
    on PersistentArtifactDurabilityLevel {
  String get wireName => name;

  static PersistentArtifactDurabilityLevel fromWireName(String value) {
    return PersistentArtifactDurabilityLevel.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactDurabilityLevel: $value',
      ),
    );
  }
}

enum PersistentArtifactConsistencyModel {
  eventual,
  strong,
  readAfterWrite,
  custom,
  unknown,
}

extension PersistentArtifactConsistencyModelX
    on PersistentArtifactConsistencyModel {
  String get wireName => name;

  static PersistentArtifactConsistencyModel fromWireName(String value) {
    return PersistentArtifactConsistencyModel.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactConsistencyModel: $value',
      ),
    );
  }
}

enum PersistentArtifactPolicyStatus {
  candidate,
  active,
  deprecated,
  retired,
  unknown,
}

extension PersistentArtifactPolicyStatusX on PersistentArtifactPolicyStatus {
  String get wireName => name;

  static PersistentArtifactPolicyStatus fromWireName(String value) {
    return PersistentArtifactPolicyStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactPolicyStatus: $value',
      ),
    );
  }
}

enum PersistentArtifactRequirementType {
  storage,
  retention,
  integrity,
  replication,
  encryption,
  availability,
  custom,
  unknown,
}

extension PersistentArtifactRequirementTypeX
    on PersistentArtifactRequirementType {
  String get wireName => name;

  static PersistentArtifactRequirementType fromWireName(String value) {
    return PersistentArtifactRequirementType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactRequirementType: $value',
      ),
    );
  }
}

enum PersistentArtifactIssueSeverity {
  info,
  warning,
  critical,
}

extension PersistentArtifactIssueSeverityX on PersistentArtifactIssueSeverity {
  String get wireName => name;

  static PersistentArtifactIssueSeverity fromWireName(String value) {
    return PersistentArtifactIssueSeverity.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactIssueSeverity: $value',
      ),
    );
  }
}

enum PersistentArtifactSourceType {
  releaseEvidence,
  releaseSupplyChain,
  cicdIntegration,
  cryptographicTrust,
  history,
  report,
  dashboard,
  goldenArtifact,
  external,
  unknown,
}

extension PersistentArtifactSourceTypeX on PersistentArtifactSourceType {
  String get wireName => name;

  static PersistentArtifactSourceType fromWireName(String value) {
    return PersistentArtifactSourceType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown PersistentArtifactSourceType: $value'),
    );
  }
}

enum PersistentArtifactOperationType {
  persist,
  publish,
  replicate,
  verifyIntegrity,
  evaluateRetention,
  requestDeletion,
  invalidate,
  snapshot,
  custom,
  unknown,
}

extension PersistentArtifactOperationTypeX on PersistentArtifactOperationType {
  String get wireName => name;

  static PersistentArtifactOperationType fromWireName(String value) {
    return PersistentArtifactOperationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactOperationType: $value',
      ),
    );
  }
}

enum PersistentArtifactEncryptionStatus {
  none,
  declared,
  encrypted,
  failed,
  unknown,
}

extension PersistentArtifactEncryptionStatusX
    on PersistentArtifactEncryptionStatus {
  String get wireName => name;

  static PersistentArtifactEncryptionStatus fromWireName(String value) {
    return PersistentArtifactEncryptionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactEncryptionStatus: $value',
      ),
    );
  }
}

enum PersistentArtifactAccessScope {
  private,
  project,
  release,
  organization,
  public,
  custom,
  unknown,
}

extension PersistentArtifactAccessScopeX on PersistentArtifactAccessScope {
  String get wireName => name;

  static PersistentArtifactAccessScope fromWireName(String value) {
    return PersistentArtifactAccessScope.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactAccessScope: $value',
      ),
    );
  }
}

enum PersistentArtifactOperationStatus {
  pending,
  succeeded,
  partial,
  failed,
  blocked,
  unknown,
}

extension PersistentArtifactOperationStatusX
    on PersistentArtifactOperationStatus {
  String get wireName => name;

  static PersistentArtifactOperationStatus fromWireName(String value) {
    return PersistentArtifactOperationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactOperationStatus: $value',
      ),
    );
  }
}

enum PersistentArtifactRetentionRecordStatus {
  active,
  expired,
  legalHold,
  immutable,
  unknown,
}

extension PersistentArtifactRetentionRecordStatusX
    on PersistentArtifactRetentionRecordStatus {
  String get wireName => name;

  static PersistentArtifactRetentionRecordStatus fromWireName(String value) {
    return PersistentArtifactRetentionRecordStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactRetentionRecordStatus: $value',
      ),
    );
  }
}

enum PersistentArtifactInfrastructureStatus {
  draft,
  evaluated,
  published,
  invalidated,
  unknown,
}

extension PersistentArtifactInfrastructureStatusX
    on PersistentArtifactInfrastructureStatus {
  String get wireName => name;

  static PersistentArtifactInfrastructureStatus fromWireName(String value) {
    return PersistentArtifactInfrastructureStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactInfrastructureStatus: $value',
      ),
    );
  }
}

enum PersistentArtifactPolicyType {
  storage,
  retention,
  integrity,
  replication,
  custom,
  unknown,
}

extension PersistentArtifactPolicyTypeX on PersistentArtifactPolicyType {
  String get wireName => name;

  static PersistentArtifactPolicyType fromWireName(String value) {
    return PersistentArtifactPolicyType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown PersistentArtifactPolicyType: $value'),
    );
  }
}
