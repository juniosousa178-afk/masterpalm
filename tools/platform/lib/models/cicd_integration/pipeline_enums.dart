/// Pipeline execution lifecycle status.
enum PipelineStatus {
  pending,
  queued,
  running,
  succeeded,
  failed,
  cancelled,
  skipped,
  timedOut,
  unknown,
}

extension PipelineStatusX on PipelineStatus {
  String get wireName => name;

  static PipelineStatus fromWireName(String value) {
    return PipelineStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown PipelineStatus: $value'),
    );
  }
}

/// Pipeline step kind.
enum PipelineStepType {
  build,
  test,
  lint,
  scan,
  deploy,
  verify,
  approval,
  publish,
  custom,
  unknown,
}

extension PipelineStepTypeX on PipelineStepType {
  String get wireName => name;

  static PipelineStepType fromWireName(String value) {
    return PipelineStepType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown PipelineStepType: $value'),
    );
  }
}

/// Pipeline stage composition kind.
enum PipelineStageType {
  sequential,
  parallel,
  gate,
  deployment,
  validation,
  custom,
  unknown,
}

extension PipelineStageTypeX on PipelineStageType {
  String get wireName => name;

  static PipelineStageType fromWireName(String value) {
    return PipelineStageType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown PipelineStageType: $value'),
    );
  }
}

/// Pipeline trigger kind (domain descriptor only — no execution).
enum PipelineTriggerType {
  manual,
  schedule,
  push,
  pullRequest,
  tag,
  release,
  api,
  unknown,
}

extension PipelineTriggerTypeX on PipelineTriggerType {
  String get wireName => name;

  static PipelineTriggerType fromWireName(String value) {
    return PipelineTriggerType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown PipelineTriggerType: $value'),
    );
  }
}

/// Pipeline artifact kind.
enum PipelineArtifactType {
  log,
  report,
  binary,
  image,
  metadata,
  testResult,
  coverage,
  sbom,
  unknown,
}

extension PipelineArtifactTypeX on PipelineArtifactType {
  String get wireName => name;

  static PipelineArtifactType fromWireName(String value) {
    return PipelineArtifactType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown PipelineArtifactType: $value'),
    );
  }
}

/// Target environment classification.
enum PipelineEnvironmentType {
  development,
  test,
  qa,
  staging,
  preProduction,
  production,
  preview,
  sandbox,
  unknown,
}

extension PipelineEnvironmentTypeX on PipelineEnvironmentType {
  String get wireName => name;

  static PipelineEnvironmentType fromWireName(String value) {
    return PipelineEnvironmentType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown PipelineEnvironmentType: $value'),
    );
  }
}

/// External CI/CD provider descriptor (domain only — no integration).
enum PipelineProviderType {
  githubActions,
  gitlabCi,
  jenkins,
  azureDevOps,
  bitbucketPipelines,
  circleCi,
  generic,
  unknown,
}

extension PipelineProviderTypeX on PipelineProviderType {
  String get wireName => name;

  static PipelineProviderType fromWireName(String value) {
    return PipelineProviderType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown PipelineProviderType: $value'),
    );
  }
}

/// Provider capability classification.
enum PipelineCapabilityType {
  build,
  test,
  deploy,
  artifactStorage,
  secretManagement,
  approvalGate,
  environmentPromotion,
  matrixBuild,
  unknown,
}

extension PipelineCapabilityTypeX on PipelineCapabilityType {
  String get wireName => name;

  static PipelineCapabilityType fromWireName(String value) {
    return PipelineCapabilityType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown PipelineCapabilityType: $value'),
    );
  }
}

/// Deployment rollout strategy.
enum DeploymentStrategy {
  rolling,
  blueGreen,
  canary,
  recreate,
  manual,
  unknown,
}

extension DeploymentStrategyX on DeploymentStrategy {
  String get wireName => name;

  static DeploymentStrategy fromWireName(String value) {
    return DeploymentStrategy.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown DeploymentStrategy: $value'),
    );
  }
}

/// Deployment approval lifecycle.
enum DeploymentApprovalStatus {
  pending,
  approved,
  rejected,
  expired,
  waived,
  unknown,
}

extension DeploymentApprovalStatusX on DeploymentApprovalStatus {
  String get wireName => name;

  static DeploymentApprovalStatus fromWireName(String value) {
    return DeploymentApprovalStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown DeploymentApprovalStatus: $value'),
    );
  }
}

/// Deployment outcome status.
enum DeploymentResultStatus {
  planned,
  inProgress,
  succeeded,
  failed,
  rolledBack,
  cancelled,
  partial,
  unknown,
}

extension DeploymentResultStatusX on DeploymentResultStatus {
  String get wireName => name;

  static DeploymentResultStatus fromWireName(String value) {
    return DeploymentResultStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown DeploymentResultStatus: $value'),
    );
  }
}

/// Deployment target classification.
enum DeploymentTargetType {
  kubernetes,
  vm,
  serverless,
  registry,
  staticHosting,
  artifactRepository,
  unknown,
}

extension DeploymentTargetTypeX on DeploymentTargetType {
  String get wireName => name;

  static DeploymentTargetType fromWireName(String value) {
    return DeploymentTargetType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown DeploymentTargetType: $value'),
    );
  }
}

/// Validation issue severity.
enum PipelineValidationSeverity {
  info,
  warning,
  error,
  critical,
}

extension PipelineValidationSeverityX on PipelineValidationSeverity {
  String get wireName => name;

  static PipelineValidationSeverity fromWireName(String value) {
    return PipelineValidationSeverity.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown PipelineValidationSeverity: $value'),
    );
  }
}

/// Terminal execution result classification.
enum PipelineExecutionOutcome {
  success,
  failure,
  cancelled,
  skipped,
  partial,
  unknown,
}

extension PipelineExecutionOutcomeX on PipelineExecutionOutcome {
  String get wireName => name;

  static PipelineExecutionOutcome fromWireName(String value) {
    return PipelineExecutionOutcome.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown PipelineExecutionOutcome: $value'),
    );
  }
}

/// Step execution status within a pipeline run.
enum PipelineStepStatus {
  pending,
  running,
  succeeded,
  failed,
  skipped,
  cancelled,
  unknown,
}

extension PipelineStepStatusX on PipelineStepStatus {
  String get wireName => name;

  static PipelineStepStatus fromWireName(String value) {
    return PipelineStepStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown PipelineStepStatus: $value'),
    );
  }
}
