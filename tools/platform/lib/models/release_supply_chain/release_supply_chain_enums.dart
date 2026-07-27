/// Release provenance lifecycle status.
enum ReleaseProvenanceStatus {
  draft,
  pending,
  complete,
  partial,
  invalid,
  expired,
  superseded,
  unavailable,
  unknown,
}

extension ReleaseProvenanceStatusX on ReleaseProvenanceStatus {
  String get wireName => name;

  static ReleaseProvenanceStatus fromWireName(String value) {
    return ReleaseProvenanceStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseProvenanceStatus: $value'),
    );
  }
}

/// Supply chain record lifecycle status.
enum SupplyChainStatus {
  draft,
  active,
  incomplete,
  blocked,
  verified,
  invalid,
  expired,
  retired,
  unknown,
}

extension SupplyChainStatusX on SupplyChainStatus {
  String get wireName => name;

  static SupplyChainStatus fromWireName(String value) {
    return SupplyChainStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown SupplyChainStatus: $value'),
    );
  }
}

/// SBOM lifecycle status.
enum SbomStatus {
  draft,
  complete,
  partial,
  invalid,
  stale,
  superseded,
  unavailable,
  unknown,
}

extension SbomStatusX on SbomStatus {
  String get wireName => name;

  static SbomStatus fromWireName(String value) {
    return SbomStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown SbomStatus: $value'),
    );
  }
}

/// Artifact registry lifecycle status.
enum ArtifactStatus {
  pending,
  available,
  unavailable,
  invalid,
  corrupted,
  expired,
  revoked,
  unknown,
}

extension ArtifactStatusX on ArtifactStatus {
  String get wireName => name;

  static ArtifactStatus fromWireName(String value) {
    return ArtifactStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown ArtifactStatus: $value'),
    );
  }
}

/// Release distribution lifecycle status.
enum DistributionStatus {
  draft,
  scheduled,
  inProgress,
  published,
  failed,
  rolledBack,
  retired,
  unknown,
}

extension DistributionStatusX on DistributionStatus {
  String get wireName => name;

  static DistributionStatus fromWireName(String value) {
    return DistributionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown DistributionStatus: $value'),
    );
  }
}

/// Compliance evaluation status.
enum ComplianceStatus {
  compliant,
  nonCompliant,
  partial,
  pending,
  notApplicable,
  error,
  unknown,
}

extension ComplianceStatusX on ComplianceStatus {
  String get wireName => name;

  static ComplianceStatus fromWireName(String value) {
    return ComplianceStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown ComplianceStatus: $value'),
    );
  }
}

/// Provenance subject taxonomy.
enum ReleaseProvenanceSubjectType {
  release,
  artifact,
  bundle,
  component,
  distribution,
  external,
  unknown,
}

extension ReleaseProvenanceSubjectTypeX on ReleaseProvenanceSubjectType {
  String get wireName => name;

  static ReleaseProvenanceSubjectType fromWireName(String value) {
    return ReleaseProvenanceSubjectType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseProvenanceSubjectType: $value'),
    );
  }
}

/// Provenance artifact taxonomy.
enum ReleaseProvenanceArtifactType {
  qualityGateSnapshot,
  releaseDecisionSnapshot,
  releaseEvidenceBundle,
  sbom,
  artifact,
  build,
  test,
  deployment,
  external,
  unknown,
}

extension ReleaseProvenanceArtifactTypeX on ReleaseProvenanceArtifactType {
  String get wireName => name;

  static ReleaseProvenanceArtifactType fromWireName(String value) {
    return ReleaseProvenanceArtifactType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseProvenanceArtifactType: $value',
      ),
    );
  }
}

/// Provenance relation taxonomy.
enum ReleaseProvenanceRelationType {
  derivedFrom,
  builtFrom,
  testedBy,
  deployedTo,
  attestedBy,
  verifiedBy,
  distributedTo,
  supersedes,
  relatedTo,
  unknown,
}

extension ReleaseProvenanceRelationTypeX on ReleaseProvenanceRelationType {
  String get wireName => name;

  static ReleaseProvenanceRelationType fromWireName(String value) {
    return ReleaseProvenanceRelationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseProvenanceRelationType: $value',
      ),
    );
  }
}

/// Supply chain stage taxonomy.
enum SupplyChainStageType {
  source,
  build,
  test,
  package,
  sign,
  attest,
  verify,
  publish,
  distribute,
  deploy,
  unknown,
}

extension SupplyChainStageTypeX on SupplyChainStageType {
  String get wireName => name;

  static SupplyChainStageType fromWireName(String value) {
    return SupplyChainStageType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown SupplyChainStageType: $value'),
    );
  }
}

/// Supply chain actor taxonomy.
enum SupplyChainActorType {
  system,
  service,
  pipeline,
  human,
  external,
  unknown,
}

extension SupplyChainActorTypeX on SupplyChainActorType {
  String get wireName => name;

  static SupplyChainActorType fromWireName(String value) {
    return SupplyChainActorType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown SupplyChainActorType: $value'),
    );
  }
}

/// SBOM component taxonomy.
enum SbomComponentType {
  application,
  library,
  framework,
  operatingSystem,
  container,
  firmware,
  device,
  file,
  unknown,
}

extension SbomComponentTypeX on SbomComponentType {
  String get wireName => name;

  static SbomComponentType fromWireName(String value) {
    return SbomComponentType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown SbomComponentType: $value'),
    );
  }
}

/// SBOM dependency scope.
enum SbomDependencyScope {
  required,
  optional,
  provided,
  runtime,
  development,
  test,
  unknown,
}

extension SbomDependencyScopeX on SbomDependencyScope {
  String get wireName => name;

  static SbomDependencyScope fromWireName(String value) {
    return SbomDependencyScope.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown SbomDependencyScope: $value'),
    );
  }
}

/// Artifact digest algorithm.
enum ArtifactDigestAlgorithm {
  sha256,
  sha384,
  sha512,
  md5,
  unknown,
}

extension ArtifactDigestAlgorithmX on ArtifactDigestAlgorithm {
  String get wireName => name;

  static ArtifactDigestAlgorithm fromWireName(String value) {
    return ArtifactDigestAlgorithm.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ArtifactDigestAlgorithm: $value'),
    );
  }
}

/// Release distribution channel taxonomy.
enum ReleaseChannelType {
  internal,
  staging,
  beta,
  production,
  canary,
  custom,
  unknown,
}

extension ReleaseChannelTypeX on ReleaseChannelType {
  String get wireName => name;

  static ReleaseChannelType fromWireName(String value) {
    return ReleaseChannelType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown ReleaseChannelType: $value'),
    );
  }
}

/// Distribution target taxonomy.
enum DistributionTargetType {
  registry,
  repository,
  bucket,
  cdn,
  device,
  environment,
  external,
  unknown,
}

extension DistributionTargetTypeX on DistributionTargetType {
  String get wireName => name;

  static DistributionTargetType fromWireName(String value) {
    return DistributionTargetType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown DistributionTargetType: $value'),
    );
  }
}

/// Compliance rule severity.
enum ComplianceRuleSeverity {
  info,
  low,
  medium,
  high,
  critical,
  unknown,
}

extension ComplianceRuleSeverityX on ComplianceRuleSeverity {
  String get wireName => name;

  static ComplianceRuleSeverity fromWireName(String value) {
    return ComplianceRuleSeverity.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ComplianceRuleSeverity: $value'),
    );
  }
}

/// Validation issue severity for release supply chain domain.
enum ReleaseSupplyChainValidationSeverity {
  info,
  warning,
  error,
  critical,
}

extension ReleaseSupplyChainValidationSeverityX
    on ReleaseSupplyChainValidationSeverity {
  String get wireName => name;

  static ReleaseSupplyChainValidationSeverity fromWireName(String value) {
    return ReleaseSupplyChainValidationSeverity.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseSupplyChainValidationSeverity: $value',
      ),
    );
  }
}
