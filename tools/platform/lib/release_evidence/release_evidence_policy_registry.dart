import '../models/release_evidence/release_attestation_policy.dart';
import '../models/release_evidence/release_evidence_enums.dart';
import '../models/release_evidence/release_evidence_policy.dart';
import '../models/release_evidence/release_evidence_validation_result.dart';
import '../models/release_evidence/release_verification_policy.dart';
import 'release_attestation_policy_validator.dart';
import 'release_evidence_exceptions.dart';
import 'release_evidence_policy_validator.dart';
import 'release_verification_policy_validator.dart';

typedef _PolicyStatusGetter<T> = ReleaseEvidencePolicyStatus Function(T policy);
typedef _PolicyIdGetter<T> = String Function(T policy);
typedef _PolicyVersionGetter<T> = int Function(T policy);
typedef _PolicyValidator<T> = ReleaseEvidenceValidationResult Function(
    T policy);

class _ReleaseEvidencePolicyRegistryCore<T> {
  _ReleaseEvidencePolicyRegistryCore({
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
      throw ReleaseEvidenceRegistryFrozenException(_registryName);
    }
    final validation = _validator(policy);
    if (!validation.isValid) {
      throw ReleaseEvidencePolicyInvalidException(
        'Invalid policy ${_policyIdOf(policy)}',
        policyId: _policyIdOf(policy),
      );
    }
    final key = _key(_policyIdOf(policy), _policyVersionOf(policy));
    if (_policies.containsKey(key)) {
      throw ReleaseEvidencePolicyInvalidException(
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

  T? _latestByStatus(String policyId, ReleaseEvidencePolicyStatus status) {
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
      _latestByStatus(policyId, ReleaseEvidencePolicyStatus.candidate);

  T? active(String policyId) =>
      _latestByStatus(policyId, ReleaseEvidencePolicyStatus.active);

  T? deprecated(String policyId) =>
      _latestByStatus(policyId, ReleaseEvidencePolicyStatus.deprecated);

  T? retired(String policyId) =>
      _latestByStatus(policyId, ReleaseEvidencePolicyStatus.retired);

  T? resolve({
    required String policyId,
    int? policyVersion,
    bool allowCandidate = true,
    bool historicalEvaluation = false,
  }) {
    if (policyVersion != null) {
      final policy = get(policyId, policyVersion);
      if (policy == null) return null;
      if (_statusOf(policy) == ReleaseEvidencePolicyStatus.retired &&
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

/// Registry of release evidence collection policies.
class ReleaseEvidencePolicyRegistry {
  ReleaseEvidencePolicyRegistry({ReleaseEvidencePolicyValidator? validator})
      : _core = _ReleaseEvidencePolicyRegistryCore<ReleaseEvidencePolicy>(
          registryName: 'ReleaseEvidencePolicyRegistry',
          policyIdOf: (p) => p.metadata.policyId,
          policyVersionOf: (p) => p.metadata.policyVersion,
          statusOf: (p) => p.metadata.status,
          validator: (p) =>
              (validator ?? const ReleaseEvidencePolicyValidator()).validate(p),
        );

  final _ReleaseEvidencePolicyRegistryCore<ReleaseEvidencePolicy> _core;

  bool get isFrozen => _core.isFrozen;
  List<ReleaseEvidencePolicy> list() => _core.list();
  void register(ReleaseEvidencePolicy policy) => _core.register(policy);
  void registerAll(Iterable<ReleaseEvidencePolicy> policies) =>
      _core.registerAll(policies);
  void freeze() => _core.freeze();
  bool contains(String policyId, int policyVersion) =>
      _core.contains(policyId, policyVersion);
  ReleaseEvidencePolicy? get(String policyId, int policyVersion) =>
      _core.get(policyId, policyVersion);
  ReleaseEvidencePolicy? byVersion(String policyId, int policyVersion) =>
      _core.byVersion(policyId, policyVersion);
  ReleaseEvidencePolicy? getLatestVersion(String policyId) =>
      _core.getLatestVersion(policyId);
  ReleaseEvidencePolicy? candidate(String policyId) =>
      _core.candidate(policyId);
  ReleaseEvidencePolicy? active(String policyId) => _core.active(policyId);
  ReleaseEvidencePolicy? deprecated(String policyId) =>
      _core.deprecated(policyId);
  ReleaseEvidencePolicy? retired(String policyId) => _core.retired(policyId);
  ReleaseEvidencePolicy? resolve({
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

/// Registry of release attestation policies.
class ReleaseAttestationPolicyRegistry {
  ReleaseAttestationPolicyRegistry({
    ReleaseAttestationPolicyValidator? validator,
  }) : _core = _ReleaseEvidencePolicyRegistryCore<ReleaseAttestationPolicy>(
          registryName: 'ReleaseAttestationPolicyRegistry',
          policyIdOf: (p) => p.metadata.policyId,
          policyVersionOf: (p) => p.metadata.policyVersion,
          statusOf: (p) => p.metadata.status,
          validator: (p) =>
              (validator ?? const ReleaseAttestationPolicyValidator())
                  .validate(p),
        );

  final _ReleaseEvidencePolicyRegistryCore<ReleaseAttestationPolicy> _core;

  bool get isFrozen => _core.isFrozen;
  List<ReleaseAttestationPolicy> list() => _core.list();
  void register(ReleaseAttestationPolicy policy) => _core.register(policy);
  void registerAll(Iterable<ReleaseAttestationPolicy> policies) =>
      _core.registerAll(policies);
  void freeze() => _core.freeze();
  bool contains(String policyId, int policyVersion) =>
      _core.contains(policyId, policyVersion);
  ReleaseAttestationPolicy? get(String policyId, int policyVersion) =>
      _core.get(policyId, policyVersion);
  ReleaseAttestationPolicy? byVersion(String policyId, int policyVersion) =>
      _core.byVersion(policyId, policyVersion);
  ReleaseAttestationPolicy? getLatestVersion(String policyId) =>
      _core.getLatestVersion(policyId);
  ReleaseAttestationPolicy? candidate(String policyId) =>
      _core.candidate(policyId);
  ReleaseAttestationPolicy? active(String policyId) => _core.active(policyId);
  ReleaseAttestationPolicy? deprecated(String policyId) =>
      _core.deprecated(policyId);
  ReleaseAttestationPolicy? retired(String policyId) => _core.retired(policyId);
  ReleaseAttestationPolicy? resolve({
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

/// Registry of release verification policies.
class ReleaseVerificationPolicyRegistry {
  ReleaseVerificationPolicyRegistry({
    ReleaseVerificationPolicyValidator? validator,
  }) : _core = _ReleaseEvidencePolicyRegistryCore<ReleaseVerificationPolicy>(
          registryName: 'ReleaseVerificationPolicyRegistry',
          policyIdOf: (p) => p.metadata.policyId,
          policyVersionOf: (p) => p.metadata.policyVersion,
          statusOf: (p) => p.metadata.status,
          validator: (p) =>
              (validator ?? const ReleaseVerificationPolicyValidator())
                  .validate(p),
        );

  final _ReleaseEvidencePolicyRegistryCore<ReleaseVerificationPolicy> _core;

  bool get isFrozen => _core.isFrozen;
  List<ReleaseVerificationPolicy> list() => _core.list();
  void register(ReleaseVerificationPolicy policy) => _core.register(policy);
  void registerAll(Iterable<ReleaseVerificationPolicy> policies) =>
      _core.registerAll(policies);
  void freeze() => _core.freeze();
  bool contains(String policyId, int policyVersion) =>
      _core.contains(policyId, policyVersion);
  ReleaseVerificationPolicy? get(String policyId, int policyVersion) =>
      _core.get(policyId, policyVersion);
  ReleaseVerificationPolicy? byVersion(String policyId, int policyVersion) =>
      _core.byVersion(policyId, policyVersion);
  ReleaseVerificationPolicy? getLatestVersion(String policyId) =>
      _core.getLatestVersion(policyId);
  ReleaseVerificationPolicy? candidate(String policyId) =>
      _core.candidate(policyId);
  ReleaseVerificationPolicy? active(String policyId) => _core.active(policyId);
  ReleaseVerificationPolicy? deprecated(String policyId) =>
      _core.deprecated(policyId);
  ReleaseVerificationPolicy? retired(String policyId) =>
      _core.retired(policyId);
  ReleaseVerificationPolicy? resolve({
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
