import '../models/release_supply_chain/release_supply_chain_operational_enums.dart';
import '../models/release_supply_chain/release_supply_chain_policy_models.dart';
import '../models/release_supply_chain/release_supply_chain_validation_result.dart';
import 'compliance_policy_validator.dart';
import 'distribution_policy_validator.dart';
import 'release_supply_chain_exceptions.dart';
import 'supply_chain_policy_validator.dart';

typedef _PolicyStatusGetter<T> = ReleaseSupplyChainPolicyStatus Function(
    T policy);
typedef _PolicyIdGetter<T> = String Function(T policy);
typedef _PolicyVersionGetter<T> = int Function(T policy);
typedef _PolicyValidator<T> = ReleaseSupplyChainValidationResult Function(
  T policy,
);

class _ReleaseSupplyChainPolicyRegistryCore<T> {
  _ReleaseSupplyChainPolicyRegistryCore({
    required String registryName,
    required _PolicyIdGetter<T> policyIdOf,
    required _PolicyVersionGetter<T> policyVersionOf,
    required _PolicyStatusGetter<T> statusOf,
    required _PolicyValidator<T> validator,
  })  : _registryName = registryName,
        _policyIdOf = policyIdOf,
        _policyVersionOf = policyVersionOf,
        _statusOf = statusOf,
        _validator = validator;

  final String _registryName;
  final _PolicyIdGetter<T> _policyIdOf;
  final _PolicyVersionGetter<T> _policyVersionOf;
  final _PolicyStatusGetter<T> _statusOf;
  final _PolicyValidator<T> _validator;
  final Map<String, T> _policies = {};
  bool _frozen = false;

  bool get isFrozen => _frozen;

  List<T> list() => _policies.values.toList()
    ..sort((a, b) {
      final idCmp = _policyIdOf(a).compareTo(_policyIdOf(b));
      if (idCmp != 0) return idCmp;
      return _policyVersionOf(a).compareTo(_policyVersionOf(b));
    });

  void register(T policy) {
    if (_frozen) {
      throw ReleaseSupplyChainRegistryFrozenException(_registryName);
    }
    final validation = _validator(policy);
    if (!validation.isValid) {
      throw ReleaseSupplyChainPolicyInvalidException(
        'Invalid policy ${_policyIdOf(policy)}',
        policyId: _policyIdOf(policy),
      );
    }
    final key = _key(_policyIdOf(policy), _policyVersionOf(policy));
    if (_policies.containsKey(key)) {
      throw ReleaseSupplyChainPolicyInvalidException(
        'Duplicate policy: ${_policyIdOf(policy)} v${_policyVersionOf(policy)}',
        policyId: _policyIdOf(policy),
      );
    }
    _policies[key] = policy;
  }

  void registerAll(Iterable<T> policies) {
    for (final policy in policies) {
      register(policy);
    }
  }

  void freeze() => _frozen = true;

  bool contains(String policyId, int policyVersion) {
    return _policies.containsKey(_key(policyId, policyVersion));
  }

  T? get(String policyId, int policyVersion) {
    return _policies[_key(policyId, policyVersion)];
  }

  T? byVersion(String policyId, int policyVersion) {
    return get(policyId, policyVersion);
  }

  T? getLatestVersion(String policyId) {
    final matches =
        _policies.values.where((p) => _policyIdOf(p) == policyId).toList()
          ..sort(
            (a, b) => _policyVersionOf(b).compareTo(_policyVersionOf(a)),
          );
    return matches.isEmpty ? null : matches.first;
  }

  T? _latestByStatus(String policyId, ReleaseSupplyChainPolicyStatus status) {
    final matches = _policies.values
        .where(
          (p) => _policyIdOf(p) == policyId && _statusOf(p) == status,
        )
        .toList()
      ..sort(
        (a, b) => _policyVersionOf(b).compareTo(_policyVersionOf(a)),
      );
    return matches.isEmpty ? null : matches.first;
  }

  T? candidate(String policyId) =>
      _latestByStatus(policyId, ReleaseSupplyChainPolicyStatus.candidate);

  T? active(String policyId) =>
      _latestByStatus(policyId, ReleaseSupplyChainPolicyStatus.active);

  T? deprecated(String policyId) =>
      _latestByStatus(policyId, ReleaseSupplyChainPolicyStatus.deprecated);

  T? retired(String policyId) =>
      _latestByStatus(policyId, ReleaseSupplyChainPolicyStatus.retired);

  T? resolve({
    required String policyId,
    int? policyVersion,
    bool allowCandidate = true,
    bool historicalEvaluation = false,
  }) {
    if (policyVersion != null) {
      final policy = get(policyId, policyVersion);
      if (policy == null) return null;
      if (_statusOf(policy) == ReleaseSupplyChainPolicyStatus.retired &&
          !historicalEvaluation) {
        return null;
      }
      return policy;
    }

    final activePolicy = active(policyId);
    if (activePolicy != null) return activePolicy;

    if (allowCandidate) {
      final candidatePolicy = candidate(policyId);
      if (candidatePolicy != null) return candidatePolicy;
    }

    return null;
  }

  String _key(String policyId, int version) => '$policyId:v$version';
}

/// Registry of supply chain policies.
class SupplyChainPolicyRegistry {
  SupplyChainPolicyRegistry({SupplyChainPolicyValidator? validator})
      : _core =
            _ReleaseSupplyChainPolicyRegistryCore<RegisteredSupplyChainPolicy>(
          registryName: 'SupplyChainPolicyRegistry',
          policyIdOf: (p) => p.metadata.policyId,
          policyVersionOf: (p) => p.metadata.policyVersion,
          statusOf: (p) => p.metadata.status,
          validator: (p) =>
              (validator ?? const SupplyChainPolicyValidator()).validate(p),
        );

  final _ReleaseSupplyChainPolicyRegistryCore<RegisteredSupplyChainPolicy>
      _core;

  bool get isFrozen => _core.isFrozen;
  List<RegisteredSupplyChainPolicy> list() => _core.list();
  void register(RegisteredSupplyChainPolicy policy) => _core.register(policy);
  void registerAll(Iterable<RegisteredSupplyChainPolicy> policies) =>
      _core.registerAll(policies);
  void freeze() => _core.freeze();
  bool contains(String policyId, int policyVersion) =>
      _core.contains(policyId, policyVersion);
  RegisteredSupplyChainPolicy? get(String policyId, int policyVersion) =>
      _core.get(policyId, policyVersion);
  RegisteredSupplyChainPolicy? byVersion(String policyId, int policyVersion) =>
      _core.byVersion(policyId, policyVersion);
  RegisteredSupplyChainPolicy? getLatestVersion(String policyId) =>
      _core.getLatestVersion(policyId);
  RegisteredSupplyChainPolicy? candidate(String policyId) =>
      _core.candidate(policyId);
  RegisteredSupplyChainPolicy? active(String policyId) =>
      _core.active(policyId);
  RegisteredSupplyChainPolicy? deprecated(String policyId) =>
      _core.deprecated(policyId);
  RegisteredSupplyChainPolicy? retired(String policyId) =>
      _core.retired(policyId);
  RegisteredSupplyChainPolicy? resolve({
    required String policyId,
    int? policyVersion,
    bool allowCandidate = true,
    bool historicalEvaluation = false,
  }) =>
      _core.resolve(
        policyId: policyId,
        policyVersion: policyVersion,
        allowCandidate: allowCandidate,
        historicalEvaluation: historicalEvaluation,
      );
}

/// Registry of distribution policies.
class DistributionPolicyRegistry {
  DistributionPolicyRegistry({DistributionPolicyValidator? validator})
      : _core =
            _ReleaseSupplyChainPolicyRegistryCore<RegisteredDistributionPolicy>(
          registryName: 'DistributionPolicyRegistry',
          policyIdOf: (p) => p.metadata.policyId,
          policyVersionOf: (p) => p.metadata.policyVersion,
          statusOf: (p) => p.metadata.status,
          validator: (p) =>
              (validator ?? const DistributionPolicyValidator()).validate(p),
        );

  final _ReleaseSupplyChainPolicyRegistryCore<RegisteredDistributionPolicy>
      _core;

  bool get isFrozen => _core.isFrozen;
  List<RegisteredDistributionPolicy> list() => _core.list();
  void register(RegisteredDistributionPolicy policy) => _core.register(policy);
  void registerAll(Iterable<RegisteredDistributionPolicy> policies) =>
      _core.registerAll(policies);
  void freeze() => _core.freeze();
  bool contains(String policyId, int policyVersion) =>
      _core.contains(policyId, policyVersion);
  RegisteredDistributionPolicy? get(String policyId, int policyVersion) =>
      _core.get(policyId, policyVersion);
  RegisteredDistributionPolicy? byVersion(String policyId, int policyVersion) =>
      _core.byVersion(policyId, policyVersion);
  RegisteredDistributionPolicy? getLatestVersion(String policyId) =>
      _core.getLatestVersion(policyId);
  RegisteredDistributionPolicy? candidate(String policyId) =>
      _core.candidate(policyId);
  RegisteredDistributionPolicy? active(String policyId) =>
      _core.active(policyId);
  RegisteredDistributionPolicy? deprecated(String policyId) =>
      _core.deprecated(policyId);
  RegisteredDistributionPolicy? retired(String policyId) =>
      _core.retired(policyId);
  RegisteredDistributionPolicy? resolve({
    required String policyId,
    int? policyVersion,
    bool allowCandidate = true,
    bool historicalEvaluation = false,
  }) =>
      _core.resolve(
        policyId: policyId,
        policyVersion: policyVersion,
        allowCandidate: allowCandidate,
        historicalEvaluation: historicalEvaluation,
      );
}

/// Registry of compliance policies.
class CompliancePolicyRegistry {
  CompliancePolicyRegistry({CompliancePolicyValidator? validator})
      : _core =
            _ReleaseSupplyChainPolicyRegistryCore<RegisteredCompliancePolicy>(
          registryName: 'CompliancePolicyRegistry',
          policyIdOf: (p) => p.metadata.policyId,
          policyVersionOf: (p) => p.metadata.policyVersion,
          statusOf: (p) => p.metadata.status,
          validator: (p) =>
              (validator ?? const CompliancePolicyValidator()).validate(p),
        );

  final _ReleaseSupplyChainPolicyRegistryCore<RegisteredCompliancePolicy> _core;

  bool get isFrozen => _core.isFrozen;
  List<RegisteredCompliancePolicy> list() => _core.list();
  void register(RegisteredCompliancePolicy policy) => _core.register(policy);
  void registerAll(Iterable<RegisteredCompliancePolicy> policies) =>
      _core.registerAll(policies);
  void freeze() => _core.freeze();
  bool contains(String policyId, int policyVersion) =>
      _core.contains(policyId, policyVersion);
  RegisteredCompliancePolicy? get(String policyId, int policyVersion) =>
      _core.get(policyId, policyVersion);
  RegisteredCompliancePolicy? byVersion(String policyId, int policyVersion) =>
      _core.byVersion(policyId, policyVersion);
  RegisteredCompliancePolicy? getLatestVersion(String policyId) =>
      _core.getLatestVersion(policyId);
  RegisteredCompliancePolicy? candidate(String policyId) =>
      _core.candidate(policyId);
  RegisteredCompliancePolicy? active(String policyId) => _core.active(policyId);
  RegisteredCompliancePolicy? deprecated(String policyId) =>
      _core.deprecated(policyId);
  RegisteredCompliancePolicy? retired(String policyId) =>
      _core.retired(policyId);
  RegisteredCompliancePolicy? resolve({
    required String policyId,
    int? policyVersion,
    bool allowCandidate = true,
    bool historicalEvaluation = false,
  }) =>
      _core.resolve(
        policyId: policyId,
        policyVersion: policyVersion,
        allowCandidate: allowCandidate,
        historicalEvaluation: historicalEvaluation,
      );
}
