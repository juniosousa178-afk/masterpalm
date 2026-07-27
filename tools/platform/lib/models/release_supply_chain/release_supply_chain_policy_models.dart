import 'compliance_models.dart';
import 'release_distribution_models.dart';
import 'release_supply_chain_operational_enums.dart';
import 'supply_chain_models.dart';

/// Operational metadata for a registered supply chain policy.
class RegisteredSupplyChainPolicyMetadata {
  const RegisteredSupplyChainPolicyMetadata({
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
  final ReleaseSupplyChainPolicyStatus status;
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

  factory RegisteredSupplyChainPolicyMetadata.fromJson(
    Map<String, dynamic> json,
  ) {
    return RegisteredSupplyChainPolicyMetadata(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      displayName: json['displayName'] as String,
      status: ReleaseSupplyChainPolicyStatusX.fromWireName(
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
}

/// Registered supply chain policy with operational metadata.
class RegisteredSupplyChainPolicy {
  const RegisteredSupplyChainPolicy({
    required this.metadata,
    required this.policy,
  });

  final RegisteredSupplyChainPolicyMetadata metadata;
  final SupplyChainPolicy policy;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'policy': policy.toJson(),
      };

  factory RegisteredSupplyChainPolicy.fromJson(Map<String, dynamic> json) {
    return RegisteredSupplyChainPolicy(
      metadata: RegisteredSupplyChainPolicyMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      policy: SupplyChainPolicy.fromJson(
        json['policy'] as Map<String, dynamic>,
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'metadata': metadata.toComparableJson(),
        'policy': policy.toComparableJson(),
      };
}

/// Operational metadata for a registered distribution policy.
class RegisteredDistributionPolicyMetadata {
  const RegisteredDistributionPolicyMetadata({
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
  final ReleaseSupplyChainPolicyStatus status;
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

  factory RegisteredDistributionPolicyMetadata.fromJson(
    Map<String, dynamic> json,
  ) {
    return RegisteredDistributionPolicyMetadata(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      displayName: json['displayName'] as String,
      status: ReleaseSupplyChainPolicyStatusX.fromWireName(
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
}

/// Registered distribution policy with operational metadata.
class RegisteredDistributionPolicy {
  const RegisteredDistributionPolicy({
    required this.metadata,
    required this.policy,
  });

  final RegisteredDistributionPolicyMetadata metadata;
  final DistributionPolicy policy;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'policy': policy.toJson(),
      };

  factory RegisteredDistributionPolicy.fromJson(Map<String, dynamic> json) {
    return RegisteredDistributionPolicy(
      metadata: RegisteredDistributionPolicyMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      policy: DistributionPolicy.fromJson(
        json['policy'] as Map<String, dynamic>,
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'metadata': metadata.toComparableJson(),
        'policy': policy.toComparableJson(),
      };
}

/// Operational metadata for a registered compliance policy.
class RegisteredCompliancePolicyMetadata {
  const RegisteredCompliancePolicyMetadata({
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
  final ReleaseSupplyChainPolicyStatus status;
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

  factory RegisteredCompliancePolicyMetadata.fromJson(
    Map<String, dynamic> json,
  ) {
    return RegisteredCompliancePolicyMetadata(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      displayName: json['displayName'] as String,
      status: ReleaseSupplyChainPolicyStatusX.fromWireName(
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
}

/// Registered compliance policy with operational metadata.
class RegisteredCompliancePolicy {
  const RegisteredCompliancePolicy({
    required this.metadata,
    required this.policy,
  });

  final RegisteredCompliancePolicyMetadata metadata;
  final CompliancePolicy policy;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'policy': policy.toJson(),
      };

  factory RegisteredCompliancePolicy.fromJson(Map<String, dynamic> json) {
    return RegisteredCompliancePolicy(
      metadata: RegisteredCompliancePolicyMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      policy: CompliancePolicy.fromJson(
        json['policy'] as Map<String, dynamic>,
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'metadata': metadata.toComparableJson(),
        'policy': policy.toComparableJson(),
      };
}

/// Reference to the supply chain policy used by a snapshot.
class ReleaseSupplyChainPolicyReference {
  const ReleaseSupplyChainPolicyReference({
    required this.supplyChainPolicyId,
    required this.supplyChainPolicyVersion,
    required this.distributionPolicyId,
    required this.distributionPolicyVersion,
    required this.compliancePolicyId,
    required this.compliancePolicyVersion,
    this.supplyChainPolicyFingerprint,
    this.distributionPolicyFingerprint,
    this.compliancePolicyFingerprint,
  });

  final String supplyChainPolicyId;
  final int supplyChainPolicyVersion;
  final String distributionPolicyId;
  final int distributionPolicyVersion;
  final String compliancePolicyId;
  final int compliancePolicyVersion;
  final String? supplyChainPolicyFingerprint;
  final String? distributionPolicyFingerprint;
  final String? compliancePolicyFingerprint;

  Map<String, dynamic> toJson() => {
        'supplyChainPolicyId': supplyChainPolicyId,
        'supplyChainPolicyVersion': supplyChainPolicyVersion,
        'distributionPolicyId': distributionPolicyId,
        'distributionPolicyVersion': distributionPolicyVersion,
        'compliancePolicyId': compliancePolicyId,
        'compliancePolicyVersion': compliancePolicyVersion,
        if (supplyChainPolicyFingerprint != null)
          'supplyChainPolicyFingerprint': supplyChainPolicyFingerprint,
        if (distributionPolicyFingerprint != null)
          'distributionPolicyFingerprint': distributionPolicyFingerprint,
        if (compliancePolicyFingerprint != null)
          'compliancePolicyFingerprint': compliancePolicyFingerprint,
      };

  factory ReleaseSupplyChainPolicyReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseSupplyChainPolicyReference(
      supplyChainPolicyId: json['supplyChainPolicyId'] as String,
      supplyChainPolicyVersion: json['supplyChainPolicyVersion'] as int,
      distributionPolicyId: json['distributionPolicyId'] as String,
      distributionPolicyVersion: json['distributionPolicyVersion'] as int,
      compliancePolicyId: json['compliancePolicyId'] as String,
      compliancePolicyVersion: json['compliancePolicyVersion'] as int,
      supplyChainPolicyFingerprint:
          json['supplyChainPolicyFingerprint'] as String?,
      distributionPolicyFingerprint:
          json['distributionPolicyFingerprint'] as String?,
      compliancePolicyFingerprint:
          json['compliancePolicyFingerprint'] as String?,
    );
  }
}
