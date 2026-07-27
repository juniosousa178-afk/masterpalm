import '../../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../../models/cryptographic_trust/cryptographic_trust_policy.dart';
import '../../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import '../../models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import '../../models/cryptographic_trust/policies/attestation_trust_policy_v1.dart';
import '../../models/cryptographic_trust/policies/release_trust_policy_v1.dart';
import 'cryptographic_trust_exceptions.dart';
import 'cryptographic_trust_policy_validator.dart';

typedef _PolicyStatusGetter = CryptographicPolicyStatus Function(
  CryptographicTrustPolicy policy,
);
typedef _PolicyIdGetter = String Function(CryptographicTrustPolicy policy);
typedef _PolicyVersionGetter = int Function(CryptographicTrustPolicy policy);
typedef _PolicyValidator = CryptographicValidationResult Function(
  CryptographicTrustPolicy policy,
);
typedef _PolicyStatusUpdater = CryptographicTrustPolicy Function(
  CryptographicTrustPolicy policy,
  CryptographicPolicyStatus status,
);

class _CryptographicTrustPolicyRegistryCore {
  _CryptographicTrustPolicyRegistryCore({
    required String registryName,
    required _PolicyIdGetter policyIdOf,
    required _PolicyVersionGetter policyVersionOf,
    required _PolicyStatusGetter statusOf,
    required _PolicyValidator validator,
    required _PolicyStatusUpdater statusUpdater,
  })  : _registryName = registryName,
        _policyIdOf = policyIdOf,
        _policyVersionOf = policyVersionOf,
        _statusOf = statusOf,
        _validator = validator,
        _statusUpdater = statusUpdater;

  final String _registryName;
  final _PolicyIdGetter _policyIdOf;
  final _PolicyVersionGetter _policyVersionOf;
  final _PolicyStatusGetter _statusOf;
  final _PolicyValidator _validator;
  final _PolicyStatusUpdater _statusUpdater;
  final Map<String, CryptographicTrustPolicy> _policies = {};
  bool _frozen = false;

  bool get isFrozen => _frozen;

  List<CryptographicTrustPolicy> list() => _policies.values.toList()
    ..sort((a, b) {
      final idCmp = _policyIdOf(a).compareTo(_policyIdOf(b));
      if (idCmp != 0) return idCmp;
      return _policyVersionOf(a).compareTo(_policyVersionOf(b));
    });

  List<CryptographicTrustPolicy> query() => list();

  void register(CryptographicTrustPolicy policy) {
    if (_frozen) {
      throw CryptographicTrustRegistryFrozenException(_registryName);
    }
    final validation = _validator(policy);
    if (!validation.isValid) {
      throw CryptographicTrustPolicyInvalidException(
        'Invalid policy ${_policyIdOf(policy)}',
        policyId: _policyIdOf(policy),
      );
    }
    final key = _key(_policyIdOf(policy), _policyVersionOf(policy));
    if (_policies.containsKey(key)) {
      throw CryptographicTrustPolicyInvalidException(
        'Duplicate policy: ${_policyIdOf(policy)} v${_policyVersionOf(policy)}',
        policyId: _policyIdOf(policy),
      );
    }
    _policies[key] = policy;
  }

  void registerAll(Iterable<CryptographicTrustPolicy> policies) {
    for (final policy in policies) {
      register(policy);
    }
  }

  void freeze() => _frozen = true;

  bool contains(String policyId, int policyVersion) {
    return _policies.containsKey(_key(policyId, policyVersion));
  }

  CryptographicTrustPolicy? resolveById(String policyId, int policyVersion) {
    return _policies[_key(policyId, policyVersion)];
  }

  CryptographicTrustPolicy? byVersion(String policyId, int policyVersion) {
    return resolveById(policyId, policyVersion);
  }

  CryptographicTrustPolicy? latest(String policyId) {
    final matches =
        _policies.values.where((p) => _policyIdOf(p) == policyId).toList()
          ..sort(
            (a, b) => _policyVersionOf(b).compareTo(_policyVersionOf(a)),
          );
    return matches.isEmpty ? null : matches.first;
  }

  CryptographicTrustPolicy? _latestByStatus(
    String policyId,
    CryptographicPolicyStatus status,
  ) {
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

  CryptographicTrustPolicy? candidate(String policyId) =>
      _latestByStatus(policyId, CryptographicPolicyStatus.candidate);

  CryptographicTrustPolicy? active(String policyId) =>
      _latestByStatus(policyId, CryptographicPolicyStatus.active);

  CryptographicTrustPolicy? deprecated(String policyId) =>
      _latestByStatus(policyId, CryptographicPolicyStatus.deprecated);

  CryptographicTrustPolicy? retired(String policyId) =>
      _latestByStatus(policyId, CryptographicPolicyStatus.retired);

  CryptographicTrustPolicy? resolve({
    required String policyId,
    int? policyVersion,
    bool allowCandidate = false,
    bool useLatest = false,
    bool historicalEvaluation = false,
  }) {
    if (policyVersion != null) {
      final policy = resolveById(policyId, policyVersion);
      if (policy == null) return null;
      if (_statusOf(policy) == CryptographicPolicyStatus.retired &&
          !historicalEvaluation) {
        return null;
      }
      return policy;
    }

    if (useLatest) {
      final latestPolicy = latest(policyId);
      if (latestPolicy != null) return latestPolicy;
    }

    final activePolicy = active(policyId);
    if (activePolicy != null) return activePolicy;

    if (allowCandidate) {
      final candidatePolicy = candidate(policyId);
      if (candidatePolicy != null) return candidatePolicy;
    }

    return null;
  }

  void promote(String policyId, int policyVersion) {
    _transitionStatus(
      policyId,
      policyVersion,
      CryptographicPolicyStatus.active,
    );
  }

  void deprecate(String policyId, int policyVersion) {
    _transitionStatus(
      policyId,
      policyVersion,
      CryptographicPolicyStatus.deprecated,
    );
  }

  void retire(String policyId, int policyVersion) {
    _transitionStatus(
      policyId,
      policyVersion,
      CryptographicPolicyStatus.retired,
    );
  }

  void _transitionStatus(
    String policyId,
    int policyVersion,
    CryptographicPolicyStatus status,
  ) {
    if (_frozen) {
      throw CryptographicTrustRegistryFrozenException(_registryName);
    }
    final key = _key(policyId, policyVersion);
    final existing = _policies[key];
    if (existing == null) {
      throw CryptographicTrustPolicyNotFoundException(
        policyId,
        policyVersion: policyVersion,
      );
    }
    _policies[key] = _statusUpdater(existing, status);
  }

  String _key(String policyId, int version) => '$policyId:v$version';
}

/// Registry of cryptographic trust policies.
///
/// Candidate policies require explicit selection. Policy resolution does not
/// authorize release.
class CryptographicTrustPolicyRegistry {
  CryptographicTrustPolicyRegistry({
    CryptographicTrustPolicyValidator? validator,
    bool registerDefaults = false,
  }) : _core = _CryptographicTrustPolicyRegistryCore(
          registryName: 'CryptographicTrustPolicyRegistry',
          policyIdOf: (p) => p.policyId,
          policyVersionOf: (p) => p.version,
          statusOf: (p) => p.status,
          validator: (p) =>
              (validator ?? const CryptographicTrustPolicyValidator())
                  .validate(p),
          statusUpdater: (policy, status) => policy.copyWith(status: status),
        ) {
    if (registerDefaults) {
      registerDefaultPolicies();
    }
  }

  final _CryptographicTrustPolicyRegistryCore _core;

  bool get isFrozen => _core.isFrozen;
  List<CryptographicTrustPolicy> list() => _core.list();
  List<CryptographicTrustPolicy> query() => _core.query();

  void register(CryptographicTrustPolicy policy) => _core.register(policy);

  void registerAll(Iterable<CryptographicTrustPolicy> policies) =>
      _core.registerAll(policies);

  void registerDefaultPolicies() {
    register(ArtifactSignatureTrustPolicyV1.create());
    register(AttestationTrustPolicyV1.create());
    register(ReleaseTrustPolicyV1.create());
  }

  void freeze() => _core.freeze();

  bool contains(String policyId, int policyVersion) =>
      _core.contains(policyId, policyVersion);

  CryptographicTrustPolicy? resolveById(String policyId, int policyVersion) =>
      _core.resolveById(policyId, policyVersion);

  CryptographicTrustPolicy? byVersion(String policyId, int policyVersion) =>
      _core.byVersion(policyId, policyVersion);

  CryptographicTrustPolicy? latest(String policyId) => _core.latest(policyId);

  CryptographicTrustPolicy? candidate(String policyId) =>
      _core.candidate(policyId);

  CryptographicTrustPolicy? active(String policyId) => _core.active(policyId);

  CryptographicTrustPolicy? deprecated(String policyId) =>
      _core.deprecated(policyId);

  CryptographicTrustPolicy? retired(String policyId) => _core.retired(policyId);

  CryptographicTrustPolicy? resolve({
    required String policyId,
    int? policyVersion,
    bool allowCandidate = false,
    bool useLatest = false,
    bool historicalEvaluation = false,
  }) =>
      _core.resolve(
        policyId: policyId,
        policyVersion: policyVersion,
        allowCandidate: allowCandidate,
        useLatest: useLatest,
        historicalEvaluation: historicalEvaluation,
      );

  void promote(String policyId, int policyVersion) =>
      _core.promote(policyId, policyVersion);

  void deprecate(String policyId, int policyVersion) =>
      _core.deprecate(policyId, policyVersion);

  void retire(String policyId, int policyVersion) =>
      _core.retire(policyId, policyVersion);
}
