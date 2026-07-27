import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_policy.dart';
import 'release_governance_exceptions.dart';
import 'release_governance_policy_validator.dart';

/// Registry of release governance policies.
class ReleaseGovernancePolicyRegistry {
  ReleaseGovernancePolicyRegistry({ReleaseGovernancePolicyValidator? validator})
      : _validator = validator ?? const ReleaseGovernancePolicyValidator();

  final ReleaseGovernancePolicyValidator _validator;
  final Map<String, ReleaseGovernancePolicy> _policies = {};
  bool _frozen = false;

  bool get isFrozen => _frozen;

  List<ReleaseGovernancePolicy> list() => _policies.values.toList()
    ..sort((a, b) {
      final idCmp = a.metadata.policyId.compareTo(b.metadata.policyId);
      if (idCmp != 0) return idCmp;
      return a.metadata.policyVersion.compareTo(b.metadata.policyVersion);
    });

  void register(ReleaseGovernancePolicy policy) {
    if (_frozen) {
      throw ReleaseGovernanceRegistryFrozenException(
        'ReleaseGovernancePolicyRegistry',
      );
    }
    final validation = _validator.validate(policy);
    if (!validation.isValid) {
      throw ReleaseGovernancePolicyInvalidException(
        'Invalid policy ${policy.metadata.policyId}',
        policyId: policy.metadata.policyId,
      );
    }
    final key = _key(policy.metadata.policyId, policy.metadata.policyVersion);
    if (_policies.containsKey(key)) {
      throw ReleaseGovernancePolicyInvalidException(
        'Duplicate policy: ${policy.metadata.policyId} v${policy.metadata.policyVersion}',
        policyId: policy.metadata.policyId,
      );
    }
    _policies[key] = policy;
  }

  void registerAll(Iterable<ReleaseGovernancePolicy> policies) {
    for (final policy in policies) {
      register(policy);
    }
  }

  void freeze() => _frozen = true;

  bool contains(String policyId, int policyVersion) {
    return _policies.containsKey(_key(policyId, policyVersion));
  }

  ReleaseGovernancePolicy? get(String policyId, int policyVersion) {
    return _policies[_key(policyId, policyVersion)];
  }

  ReleaseGovernancePolicy? getLatestVersion(String policyId) {
    final matches = _policies.values
        .where((p) => p.metadata.policyId == policyId)
        .toList()
      ..sort(
        (a, b) => b.metadata.policyVersion.compareTo(a.metadata.policyVersion),
      );
    return matches.isEmpty ? null : matches.first;
  }

  ReleaseGovernancePolicy? getActive(String policyId) {
    final active = _policies.values
        .where(
          (p) =>
              p.metadata.policyId == policyId &&
              p.metadata.status == ReleaseGovernancePolicyStatus.active,
        )
        .toList()
      ..sort(
        (a, b) => b.metadata.policyVersion.compareTo(a.metadata.policyVersion),
      );
    return active.isEmpty ? null : active.first;
  }

  ReleaseGovernancePolicy? resolve({
    required String policyId,
    int? policyVersion,
    bool allowCandidate = true,
    bool historicalEvaluation = false,
  }) {
    final policy = policyVersion == null
        ? getLatestVersion(policyId)
        : get(policyId, policyVersion);
    if (policy == null) return null;
    if (policy.metadata.status == ReleaseGovernancePolicyStatus.retired &&
        !historicalEvaluation) {
      return null;
    }
    if (policy.metadata.status == ReleaseGovernancePolicyStatus.candidate &&
        !allowCandidate &&
        getActive(policyId) != null) {
      return getActive(policyId);
    }
    return policy;
  }

  String _key(String policyId, int version) => '$policyId:v$version';
}
