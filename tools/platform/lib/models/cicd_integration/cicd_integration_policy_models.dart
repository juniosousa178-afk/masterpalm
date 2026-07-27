import 'cicd_integration_operational_enums.dart';
import 'pipeline_equality.dart';
import 'pipeline_enums.dart';

/// Pipeline integration policy rules (domain descriptor only).
class PipelineIntegrationPolicy {
  const PipelineIntegrationPolicy({
    required this.policyId,
    required this.policyVersion,
    required this.name,
    required this.requiredStageTypes,
    this.requireDefinitionFingerprint = true,
    this.limitations = const [],
  });

  final String policyId;
  final int policyVersion;
  final String name;
  final List<PipelineStageType> requiredStageTypes;
  final bool requireDefinitionFingerprint;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'name': name,
        'requiredStageTypes': requiredStageTypes.map((e) => e.wireName).toList()
          ..sort(),
        'requireDefinitionFingerprint': requireDefinitionFingerprint,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory PipelineIntegrationPolicy.fromJson(Map<String, dynamic> json) {
    return PipelineIntegrationPolicy(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      name: json['name'] as String,
      requiredStageTypes: List.unmodifiable(
        (json['requiredStageTypes'] as List<dynamic>)
            .map((e) => PipelineStageTypeX.fromWireName(e.toString()))
            .toList()
          ..sort((a, b) => a.wireName.compareTo(b.wireName)),
      ),
      requireDefinitionFingerprint:
          json['requireDefinitionFingerprint'] as bool? ?? true,
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
        'requireDefinitionFingerprint': requireDefinitionFingerprint,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  PipelineIntegrationPolicy copyWith({
    String? policyId,
    int? policyVersion,
    String? name,
    List<PipelineStageType>? requiredStageTypes,
    bool? requireDefinitionFingerprint,
    List<String>? limitations,
  }) {
    return PipelineIntegrationPolicy(
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      name: name ?? this.name,
      requiredStageTypes: requiredStageTypes ?? this.requiredStageTypes,
      requireDefinitionFingerprint:
          requireDefinitionFingerprint ?? this.requireDefinitionFingerprint,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineIntegrationPolicy &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          name == other.name &&
          cicdListEquals(requiredStageTypes, other.requiredStageTypes) &&
          requireDefinitionFingerprint == other.requireDefinitionFingerprint &&
          cicdListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        policyId,
        policyVersion,
        name,
        Object.hashAll(requiredStageTypes),
        requireDefinitionFingerprint,
        Object.hashAll(limitations),
      );
}

/// Pipeline execution policy rules (domain descriptor only).
class PipelineExecutionPolicy {
  const PipelineExecutionPolicy({
    required this.policyId,
    required this.policyVersion,
    required this.name,
    required this.requiredTerminalOutcomes,
    this.requireExecutionFingerprint = true,
    this.requireResultFingerprint = false,
    this.limitations = const [],
  });

  final String policyId;
  final int policyVersion;
  final String name;
  final List<PipelineExecutionOutcome> requiredTerminalOutcomes;
  final bool requireExecutionFingerprint;
  final bool requireResultFingerprint;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'name': name,
        'requiredTerminalOutcomes':
            requiredTerminalOutcomes.map((e) => e.wireName).toList()..sort(),
        'requireExecutionFingerprint': requireExecutionFingerprint,
        'requireResultFingerprint': requireResultFingerprint,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory PipelineExecutionPolicy.fromJson(Map<String, dynamic> json) {
    return PipelineExecutionPolicy(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      name: json['name'] as String,
      requiredTerminalOutcomes: List.unmodifiable(
        (json['requiredTerminalOutcomes'] as List<dynamic>)
            .map((e) => PipelineExecutionOutcomeX.fromWireName(e.toString()))
            .toList()
          ..sort((a, b) => a.wireName.compareTo(b.wireName)),
      ),
      requireExecutionFingerprint:
          json['requireExecutionFingerprint'] as bool? ?? true,
      requireResultFingerprint:
          json['requireResultFingerprint'] as bool? ?? false,
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
        'requiredTerminalOutcomes':
            requiredTerminalOutcomes.map((e) => e.wireName).toList()..sort(),
        'requireExecutionFingerprint': requireExecutionFingerprint,
        'requireResultFingerprint': requireResultFingerprint,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  PipelineExecutionPolicy copyWith({
    String? policyId,
    int? policyVersion,
    String? name,
    List<PipelineExecutionOutcome>? requiredTerminalOutcomes,
    bool? requireExecutionFingerprint,
    bool? requireResultFingerprint,
    List<String>? limitations,
  }) {
    return PipelineExecutionPolicy(
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      name: name ?? this.name,
      requiredTerminalOutcomes:
          requiredTerminalOutcomes ?? this.requiredTerminalOutcomes,
      requireExecutionFingerprint:
          requireExecutionFingerprint ?? this.requireExecutionFingerprint,
      requireResultFingerprint:
          requireResultFingerprint ?? this.requireResultFingerprint,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineExecutionPolicy &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          name == other.name &&
          cicdListEquals(
              requiredTerminalOutcomes, other.requiredTerminalOutcomes) &&
          requireExecutionFingerprint == other.requireExecutionFingerprint &&
          requireResultFingerprint == other.requireResultFingerprint &&
          cicdListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        policyId,
        policyVersion,
        name,
        Object.hashAll(requiredTerminalOutcomes),
        requireExecutionFingerprint,
        requireResultFingerprint,
        Object.hashAll(limitations),
      );
}

/// Deployment integration policy rules (domain descriptor only).
class DeploymentIntegrationPolicy {
  const DeploymentIntegrationPolicy({
    required this.policyId,
    required this.policyVersion,
    required this.name,
    required this.allowedStrategies,
    this.requireApproval = false,
    this.requireDeploymentFingerprint = true,
    this.limitations = const [],
  });

  final String policyId;
  final int policyVersion;
  final String name;
  final List<DeploymentStrategy> allowedStrategies;
  final bool requireApproval;
  final bool requireDeploymentFingerprint;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'name': name,
        'allowedStrategies': allowedStrategies.map((e) => e.wireName).toList()
          ..sort(),
        'requireApproval': requireApproval,
        'requireDeploymentFingerprint': requireDeploymentFingerprint,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory DeploymentIntegrationPolicy.fromJson(Map<String, dynamic> json) {
    return DeploymentIntegrationPolicy(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      name: json['name'] as String,
      allowedStrategies: List.unmodifiable(
        (json['allowedStrategies'] as List<dynamic>)
            .map((e) => DeploymentStrategyX.fromWireName(e.toString()))
            .toList()
          ..sort((a, b) => a.wireName.compareTo(b.wireName)),
      ),
      requireApproval: json['requireApproval'] as bool? ?? false,
      requireDeploymentFingerprint:
          json['requireDeploymentFingerprint'] as bool? ?? true,
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
        'allowedStrategies': allowedStrategies.map((e) => e.wireName).toList()
          ..sort(),
        'requireApproval': requireApproval,
        'requireDeploymentFingerprint': requireDeploymentFingerprint,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  DeploymentIntegrationPolicy copyWith({
    String? policyId,
    int? policyVersion,
    String? name,
    List<DeploymentStrategy>? allowedStrategies,
    bool? requireApproval,
    bool? requireDeploymentFingerprint,
    List<String>? limitations,
  }) {
    return DeploymentIntegrationPolicy(
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      name: name ?? this.name,
      allowedStrategies: allowedStrategies ?? this.allowedStrategies,
      requireApproval: requireApproval ?? this.requireApproval,
      requireDeploymentFingerprint:
          requireDeploymentFingerprint ?? this.requireDeploymentFingerprint,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeploymentIntegrationPolicy &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          name == other.name &&
          cicdListEquals(allowedStrategies, other.allowedStrategies) &&
          requireApproval == other.requireApproval &&
          requireDeploymentFingerprint == other.requireDeploymentFingerprint &&
          cicdListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        policyId,
        policyVersion,
        name,
        Object.hashAll(allowedStrategies),
        requireApproval,
        requireDeploymentFingerprint,
        Object.hashAll(limitations),
      );
}

/// Operational metadata for a registered pipeline integration policy.
class RegisteredPipelineIntegrationPolicyMetadata {
  const RegisteredPipelineIntegrationPolicyMetadata({
    required this.policyId,
    required this.policyVersion,
    required this.displayName,
    required this.status,
    this.fingerprint,
    this.limitations = const [],
  });

  final String policyId;
  final int policyVersion;
  final String displayName;
  final CicdIntegrationPolicyStatus status;
  final String? fingerprint;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'displayName': displayName,
        'status': status.wireName,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory RegisteredPipelineIntegrationPolicyMetadata.fromJson(
    Map<String, dynamic> json,
  ) {
    return RegisteredPipelineIntegrationPolicyMetadata(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      displayName: json['displayName'] as String,
      status: CicdIntegrationPolicyStatusX.fromWireName(
        json['status'] as String,
      ),
      fingerprint: json['fingerprint'] as String?,
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
        'displayName': displayName,
        'status': status.wireName,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  RegisteredPipelineIntegrationPolicyMetadata copyWith({
    String? policyId,
    int? policyVersion,
    String? displayName,
    CicdIntegrationPolicyStatus? status,
    String? fingerprint,
    List<String>? limitations,
  }) {
    return RegisteredPipelineIntegrationPolicyMetadata(
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      displayName: displayName ?? this.displayName,
      status: status ?? this.status,
      fingerprint: fingerprint ?? this.fingerprint,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegisteredPipelineIntegrationPolicyMetadata &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          displayName == other.displayName &&
          status == other.status &&
          fingerprint == other.fingerprint &&
          cicdListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        policyId,
        policyVersion,
        displayName,
        status,
        fingerprint,
        Object.hashAll(limitations),
      );
}

/// Registered pipeline integration policy with operational metadata.
class RegisteredPipelineIntegrationPolicy {
  const RegisteredPipelineIntegrationPolicy({
    required this.metadata,
    required this.policy,
  });

  final RegisteredPipelineIntegrationPolicyMetadata metadata;
  final PipelineIntegrationPolicy policy;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'policy': policy.toJson(),
      };

  factory RegisteredPipelineIntegrationPolicy.fromJson(
    Map<String, dynamic> json,
  ) {
    return RegisteredPipelineIntegrationPolicy(
      metadata: RegisteredPipelineIntegrationPolicyMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      policy: PipelineIntegrationPolicy.fromJson(
        json['policy'] as Map<String, dynamic>,
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'metadata': metadata.toComparableJson(),
        'policy': policy.toComparableJson(),
      };

  RegisteredPipelineIntegrationPolicy copyWith({
    RegisteredPipelineIntegrationPolicyMetadata? metadata,
    PipelineIntegrationPolicy? policy,
  }) {
    return RegisteredPipelineIntegrationPolicy(
      metadata: metadata ?? this.metadata,
      policy: policy ?? this.policy,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegisteredPipelineIntegrationPolicy &&
          metadata == other.metadata &&
          policy == other.policy;

  @override
  int get hashCode => Object.hash(metadata, policy);
}

/// Operational metadata for a registered pipeline execution policy.
class RegisteredPipelineExecutionPolicyMetadata {
  const RegisteredPipelineExecutionPolicyMetadata({
    required this.policyId,
    required this.policyVersion,
    required this.displayName,
    required this.status,
    this.fingerprint,
    this.limitations = const [],
  });

  final String policyId;
  final int policyVersion;
  final String displayName;
  final CicdIntegrationPolicyStatus status;
  final String? fingerprint;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'displayName': displayName,
        'status': status.wireName,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory RegisteredPipelineExecutionPolicyMetadata.fromJson(
    Map<String, dynamic> json,
  ) {
    return RegisteredPipelineExecutionPolicyMetadata(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      displayName: json['displayName'] as String,
      status: CicdIntegrationPolicyStatusX.fromWireName(
        json['status'] as String,
      ),
      fingerprint: json['fingerprint'] as String?,
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
        'displayName': displayName,
        'status': status.wireName,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  RegisteredPipelineExecutionPolicyMetadata copyWith({
    String? policyId,
    int? policyVersion,
    String? displayName,
    CicdIntegrationPolicyStatus? status,
    String? fingerprint,
    List<String>? limitations,
  }) {
    return RegisteredPipelineExecutionPolicyMetadata(
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      displayName: displayName ?? this.displayName,
      status: status ?? this.status,
      fingerprint: fingerprint ?? this.fingerprint,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegisteredPipelineExecutionPolicyMetadata &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          displayName == other.displayName &&
          status == other.status &&
          fingerprint == other.fingerprint &&
          cicdListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        policyId,
        policyVersion,
        displayName,
        status,
        fingerprint,
        Object.hashAll(limitations),
      );
}

/// Registered pipeline execution policy with operational metadata.
class RegisteredPipelineExecutionPolicy {
  const RegisteredPipelineExecutionPolicy({
    required this.metadata,
    required this.policy,
  });

  final RegisteredPipelineExecutionPolicyMetadata metadata;
  final PipelineExecutionPolicy policy;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'policy': policy.toJson(),
      };

  factory RegisteredPipelineExecutionPolicy.fromJson(
    Map<String, dynamic> json,
  ) {
    return RegisteredPipelineExecutionPolicy(
      metadata: RegisteredPipelineExecutionPolicyMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      policy: PipelineExecutionPolicy.fromJson(
        json['policy'] as Map<String, dynamic>,
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'metadata': metadata.toComparableJson(),
        'policy': policy.toComparableJson(),
      };

  RegisteredPipelineExecutionPolicy copyWith({
    RegisteredPipelineExecutionPolicyMetadata? metadata,
    PipelineExecutionPolicy? policy,
  }) {
    return RegisteredPipelineExecutionPolicy(
      metadata: metadata ?? this.metadata,
      policy: policy ?? this.policy,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegisteredPipelineExecutionPolicy &&
          metadata == other.metadata &&
          policy == other.policy;

  @override
  int get hashCode => Object.hash(metadata, policy);
}

/// Operational metadata for a registered deployment integration policy.
class RegisteredDeploymentIntegrationPolicyMetadata {
  const RegisteredDeploymentIntegrationPolicyMetadata({
    required this.policyId,
    required this.policyVersion,
    required this.displayName,
    required this.status,
    this.fingerprint,
    this.limitations = const [],
  });

  final String policyId;
  final int policyVersion;
  final String displayName;
  final CicdIntegrationPolicyStatus status;
  final String? fingerprint;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'displayName': displayName,
        'status': status.wireName,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory RegisteredDeploymentIntegrationPolicyMetadata.fromJson(
    Map<String, dynamic> json,
  ) {
    return RegisteredDeploymentIntegrationPolicyMetadata(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      displayName: json['displayName'] as String,
      status: CicdIntegrationPolicyStatusX.fromWireName(
        json['status'] as String,
      ),
      fingerprint: json['fingerprint'] as String?,
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
        'displayName': displayName,
        'status': status.wireName,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  RegisteredDeploymentIntegrationPolicyMetadata copyWith({
    String? policyId,
    int? policyVersion,
    String? displayName,
    CicdIntegrationPolicyStatus? status,
    String? fingerprint,
    List<String>? limitations,
  }) {
    return RegisteredDeploymentIntegrationPolicyMetadata(
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      displayName: displayName ?? this.displayName,
      status: status ?? this.status,
      fingerprint: fingerprint ?? this.fingerprint,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegisteredDeploymentIntegrationPolicyMetadata &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          displayName == other.displayName &&
          status == other.status &&
          fingerprint == other.fingerprint &&
          cicdListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        policyId,
        policyVersion,
        displayName,
        status,
        fingerprint,
        Object.hashAll(limitations),
      );
}

/// Registered deployment integration policy with operational metadata.
class RegisteredDeploymentIntegrationPolicy {
  const RegisteredDeploymentIntegrationPolicy({
    required this.metadata,
    required this.policy,
  });

  final RegisteredDeploymentIntegrationPolicyMetadata metadata;
  final DeploymentIntegrationPolicy policy;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'policy': policy.toJson(),
      };

  factory RegisteredDeploymentIntegrationPolicy.fromJson(
    Map<String, dynamic> json,
  ) {
    return RegisteredDeploymentIntegrationPolicy(
      metadata: RegisteredDeploymentIntegrationPolicyMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      policy: DeploymentIntegrationPolicy.fromJson(
        json['policy'] as Map<String, dynamic>,
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'metadata': metadata.toComparableJson(),
        'policy': policy.toComparableJson(),
      };

  RegisteredDeploymentIntegrationPolicy copyWith({
    RegisteredDeploymentIntegrationPolicyMetadata? metadata,
    DeploymentIntegrationPolicy? policy,
  }) {
    return RegisteredDeploymentIntegrationPolicy(
      metadata: metadata ?? this.metadata,
      policy: policy ?? this.policy,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegisteredDeploymentIntegrationPolicy &&
          metadata == other.metadata &&
          policy == other.policy;

  @override
  int get hashCode => Object.hash(metadata, policy);
}

/// Reference to the CI/CD integration policies used by a snapshot.
class CicdIntegrationPolicyReference {
  const CicdIntegrationPolicyReference({
    required this.pipelineIntegrationPolicyId,
    required this.pipelineIntegrationPolicyVersion,
    required this.pipelineExecutionPolicyId,
    required this.pipelineExecutionPolicyVersion,
    required this.deploymentIntegrationPolicyId,
    required this.deploymentIntegrationPolicyVersion,
    this.pipelineIntegrationPolicyFingerprint,
    this.pipelineExecutionPolicyFingerprint,
    this.deploymentIntegrationPolicyFingerprint,
  });

  final String pipelineIntegrationPolicyId;
  final int pipelineIntegrationPolicyVersion;
  final String pipelineExecutionPolicyId;
  final int pipelineExecutionPolicyVersion;
  final String deploymentIntegrationPolicyId;
  final int deploymentIntegrationPolicyVersion;
  final String? pipelineIntegrationPolicyFingerprint;
  final String? pipelineExecutionPolicyFingerprint;
  final String? deploymentIntegrationPolicyFingerprint;

  Map<String, dynamic> toJson() => {
        'pipelineIntegrationPolicyId': pipelineIntegrationPolicyId,
        'pipelineIntegrationPolicyVersion': pipelineIntegrationPolicyVersion,
        'pipelineExecutionPolicyId': pipelineExecutionPolicyId,
        'pipelineExecutionPolicyVersion': pipelineExecutionPolicyVersion,
        'deploymentIntegrationPolicyId': deploymentIntegrationPolicyId,
        'deploymentIntegrationPolicyVersion':
            deploymentIntegrationPolicyVersion,
        if (pipelineIntegrationPolicyFingerprint != null)
          'pipelineIntegrationPolicyFingerprint':
              pipelineIntegrationPolicyFingerprint,
        if (pipelineExecutionPolicyFingerprint != null)
          'pipelineExecutionPolicyFingerprint':
              pipelineExecutionPolicyFingerprint,
        if (deploymentIntegrationPolicyFingerprint != null)
          'deploymentIntegrationPolicyFingerprint':
              deploymentIntegrationPolicyFingerprint,
      };

  factory CicdIntegrationPolicyReference.fromJson(Map<String, dynamic> json) {
    return CicdIntegrationPolicyReference(
      pipelineIntegrationPolicyId:
          json['pipelineIntegrationPolicyId'] as String,
      pipelineIntegrationPolicyVersion:
          json['pipelineIntegrationPolicyVersion'] as int,
      pipelineExecutionPolicyId: json['pipelineExecutionPolicyId'] as String,
      pipelineExecutionPolicyVersion:
          json['pipelineExecutionPolicyVersion'] as int,
      deploymentIntegrationPolicyId:
          json['deploymentIntegrationPolicyId'] as String,
      deploymentIntegrationPolicyVersion:
          json['deploymentIntegrationPolicyVersion'] as int,
      pipelineIntegrationPolicyFingerprint:
          json['pipelineIntegrationPolicyFingerprint'] as String?,
      pipelineExecutionPolicyFingerprint:
          json['pipelineExecutionPolicyFingerprint'] as String?,
      deploymentIntegrationPolicyFingerprint:
          json['deploymentIntegrationPolicyFingerprint'] as String?,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'pipelineIntegrationPolicyId': pipelineIntegrationPolicyId,
        'pipelineIntegrationPolicyVersion': pipelineIntegrationPolicyVersion,
        'pipelineExecutionPolicyId': pipelineExecutionPolicyId,
        'pipelineExecutionPolicyVersion': pipelineExecutionPolicyVersion,
        'deploymentIntegrationPolicyId': deploymentIntegrationPolicyId,
        'deploymentIntegrationPolicyVersion':
            deploymentIntegrationPolicyVersion,
        if (pipelineIntegrationPolicyFingerprint != null)
          'pipelineIntegrationPolicyFingerprint':
              pipelineIntegrationPolicyFingerprint,
        if (pipelineExecutionPolicyFingerprint != null)
          'pipelineExecutionPolicyFingerprint':
              pipelineExecutionPolicyFingerprint,
        if (deploymentIntegrationPolicyFingerprint != null)
          'deploymentIntegrationPolicyFingerprint':
              deploymentIntegrationPolicyFingerprint,
      };

  CicdIntegrationPolicyReference copyWith({
    String? pipelineIntegrationPolicyId,
    int? pipelineIntegrationPolicyVersion,
    String? pipelineExecutionPolicyId,
    int? pipelineExecutionPolicyVersion,
    String? deploymentIntegrationPolicyId,
    int? deploymentIntegrationPolicyVersion,
    String? pipelineIntegrationPolicyFingerprint,
    String? pipelineExecutionPolicyFingerprint,
    String? deploymentIntegrationPolicyFingerprint,
  }) {
    return CicdIntegrationPolicyReference(
      pipelineIntegrationPolicyId:
          pipelineIntegrationPolicyId ?? this.pipelineIntegrationPolicyId,
      pipelineIntegrationPolicyVersion: pipelineIntegrationPolicyVersion ??
          this.pipelineIntegrationPolicyVersion,
      pipelineExecutionPolicyId:
          pipelineExecutionPolicyId ?? this.pipelineExecutionPolicyId,
      pipelineExecutionPolicyVersion:
          pipelineExecutionPolicyVersion ?? this.pipelineExecutionPolicyVersion,
      deploymentIntegrationPolicyId:
          deploymentIntegrationPolicyId ?? this.deploymentIntegrationPolicyId,
      deploymentIntegrationPolicyVersion: deploymentIntegrationPolicyVersion ??
          this.deploymentIntegrationPolicyVersion,
      pipelineIntegrationPolicyFingerprint:
          pipelineIntegrationPolicyFingerprint ??
              this.pipelineIntegrationPolicyFingerprint,
      pipelineExecutionPolicyFingerprint: pipelineExecutionPolicyFingerprint ??
          this.pipelineExecutionPolicyFingerprint,
      deploymentIntegrationPolicyFingerprint:
          deploymentIntegrationPolicyFingerprint ??
              this.deploymentIntegrationPolicyFingerprint,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CicdIntegrationPolicyReference &&
          pipelineIntegrationPolicyId == other.pipelineIntegrationPolicyId &&
          pipelineIntegrationPolicyVersion ==
              other.pipelineIntegrationPolicyVersion &&
          pipelineExecutionPolicyId == other.pipelineExecutionPolicyId &&
          pipelineExecutionPolicyVersion ==
              other.pipelineExecutionPolicyVersion &&
          deploymentIntegrationPolicyId ==
              other.deploymentIntegrationPolicyId &&
          deploymentIntegrationPolicyVersion ==
              other.deploymentIntegrationPolicyVersion &&
          pipelineIntegrationPolicyFingerprint ==
              other.pipelineIntegrationPolicyFingerprint &&
          pipelineExecutionPolicyFingerprint ==
              other.pipelineExecutionPolicyFingerprint &&
          deploymentIntegrationPolicyFingerprint ==
              other.deploymentIntegrationPolicyFingerprint;

  @override
  int get hashCode => Object.hash(
        pipelineIntegrationPolicyId,
        pipelineIntegrationPolicyVersion,
        pipelineExecutionPolicyId,
        pipelineExecutionPolicyVersion,
        deploymentIntegrationPolicyId,
        deploymentIntegrationPolicyVersion,
        pipelineIntegrationPolicyFingerprint,
        pipelineExecutionPolicyFingerprint,
        deploymentIntegrationPolicyFingerprint,
      );
}
