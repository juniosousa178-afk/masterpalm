import '../models/cicd_integration/cicd_integration_operational_enums.dart';
import '../models/cicd_integration/cicd_integration_policy_models.dart';
import '../models/cicd_integration/pipeline_validation_result.dart';
import 'cicd_integration_exceptions.dart';
import 'deployment_integration_policy_validator.dart';
import 'pipeline_execution_policy_validator.dart';
import 'pipeline_integration_policy_validator.dart';

typedef _PolicyStatusGetter<T> = CicdIntegrationPolicyStatus Function(T policy);
typedef _PolicyIdGetter<T> = String Function(T policy);
typedef _PolicyVersionGetter<T> = int Function(T policy);
typedef _PolicyValidator<T> = PipelineValidationResult Function(T policy);
typedef _PolicyStatusUpdater<T> = T Function(
  T policy,
  CicdIntegrationPolicyStatus status,
);

class _CicdIntegrationPolicyRegistryCore<T> {
  _CicdIntegrationPolicyRegistryCore({
    required String registryName,
    required _PolicyIdGetter<T> policyIdOf,
    required _PolicyVersionGetter<T> policyVersionOf,
    required _PolicyStatusGetter<T> statusOf,
    required _PolicyValidator<T> validator,
    required _PolicyStatusUpdater<T> statusUpdater,
  })  : _registryName = registryName,
        _policyIdOf = policyIdOf,
        _policyVersionOf = policyVersionOf,
        _statusOf = statusOf,
        _validator = validator,
        _statusUpdater = statusUpdater;

  final String _registryName;
  final _PolicyIdGetter<T> _policyIdOf;
  final _PolicyVersionGetter<T> _policyVersionOf;
  final _PolicyStatusGetter<T> _statusOf;
  final _PolicyValidator<T> _validator;
  final _PolicyStatusUpdater<T> _statusUpdater;
  final Map<String, T> _policies = {};
  bool _frozen = false;

  bool get isFrozen => _frozen;

  List<T> list() => _policies.values.toList()
    ..sort((a, b) {
      final idCmp = _policyIdOf(a).compareTo(_policyIdOf(b));
      if (idCmp != 0) return idCmp;
      return _policyVersionOf(a).compareTo(_policyVersionOf(b));
    });

  List<T> query() => list();

  void register(T policy) {
    if (_frozen) {
      throw CicdIntegrationRegistryFrozenException(_registryName);
    }
    final validation = _validator(policy);
    if (!validation.isValid) {
      throw CicdIntegrationPolicyInvalidException(
        'Invalid policy ${_policyIdOf(policy)}',
        policyId: _policyIdOf(policy),
      );
    }
    final key = _key(_policyIdOf(policy), _policyVersionOf(policy));
    if (_policies.containsKey(key)) {
      throw CicdIntegrationPolicyInvalidException(
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

  T? _latestByStatus(String policyId, CicdIntegrationPolicyStatus status) {
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
      _latestByStatus(policyId, CicdIntegrationPolicyStatus.candidate);

  T? active(String policyId) =>
      _latestByStatus(policyId, CicdIntegrationPolicyStatus.active);

  T? deprecated(String policyId) =>
      _latestByStatus(policyId, CicdIntegrationPolicyStatus.deprecated);

  T? retired(String policyId) =>
      _latestByStatus(policyId, CicdIntegrationPolicyStatus.retired);

  T? resolve({
    required String policyId,
    int? policyVersion,
    bool allowCandidate = true,
    bool historicalEvaluation = false,
  }) {
    if (policyVersion != null) {
      final policy = get(policyId, policyVersion);
      if (policy == null) return null;
      if (_statusOf(policy) == CicdIntegrationPolicyStatus.retired &&
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

  void promote(String policyId, int policyVersion) {
    _transitionStatus(
      policyId,
      policyVersion,
      CicdIntegrationPolicyStatus.active,
    );
  }

  void deprecate(String policyId, int policyVersion) {
    _transitionStatus(
      policyId,
      policyVersion,
      CicdIntegrationPolicyStatus.deprecated,
    );
  }

  void retire(String policyId, int policyVersion) {
    _transitionStatus(
      policyId,
      policyVersion,
      CicdIntegrationPolicyStatus.retired,
    );
  }

  void _transitionStatus(
    String policyId,
    int policyVersion,
    CicdIntegrationPolicyStatus status,
  ) {
    if (_frozen) {
      throw CicdIntegrationRegistryFrozenException(_registryName);
    }
    final key = _key(policyId, policyVersion);
    final existing = _policies[key];
    if (existing == null) {
      throw CicdIntegrationPolicyNotFoundException(
        policyId,
        policyVersion: policyVersion,
      );
    }
    _policies[key] = _statusUpdater(existing, status);
  }

  String _key(String policyId, int version) => '$policyId:v$version';
}

/// Registry of pipeline integration policies.
class PipelineIntegrationPolicyRegistry {
  PipelineIntegrationPolicyRegistry(
      {PipelineIntegrationPolicyValidator? validator})
      : _core = _CicdIntegrationPolicyRegistryCore<
            RegisteredPipelineIntegrationPolicy>(
          registryName: 'PipelineIntegrationPolicyRegistry',
          policyIdOf: (p) => p.metadata.policyId,
          policyVersionOf: (p) => p.metadata.policyVersion,
          statusOf: (p) => p.metadata.status,
          validator: (p) =>
              (validator ?? const PipelineIntegrationPolicyValidator())
                  .validate(p),
          statusUpdater: (policy, status) => policy.copyWith(
            metadata: policy.metadata.copyWith(status: status),
          ),
        );

  final _CicdIntegrationPolicyRegistryCore<RegisteredPipelineIntegrationPolicy>
      _core;

  bool get isFrozen => _core.isFrozen;
  List<RegisteredPipelineIntegrationPolicy> list() => _core.list();
  List<RegisteredPipelineIntegrationPolicy> query() => _core.query();
  void register(RegisteredPipelineIntegrationPolicy policy) =>
      _core.register(policy);
  void registerAll(Iterable<RegisteredPipelineIntegrationPolicy> policies) =>
      _core.registerAll(policies);
  void freeze() => _core.freeze();
  bool contains(String policyId, int policyVersion) =>
      _core.contains(policyId, policyVersion);
  RegisteredPipelineIntegrationPolicy? get(
          String policyId, int policyVersion) =>
      _core.get(policyId, policyVersion);
  RegisteredPipelineIntegrationPolicy? byVersion(
    String policyId,
    int policyVersion,
  ) =>
      _core.byVersion(policyId, policyVersion);
  RegisteredPipelineIntegrationPolicy? getLatestVersion(String policyId) =>
      _core.getLatestVersion(policyId);
  RegisteredPipelineIntegrationPolicy? candidate(String policyId) =>
      _core.candidate(policyId);
  RegisteredPipelineIntegrationPolicy? active(String policyId) =>
      _core.active(policyId);
  RegisteredPipelineIntegrationPolicy? deprecated(String policyId) =>
      _core.deprecated(policyId);
  RegisteredPipelineIntegrationPolicy? retired(String policyId) =>
      _core.retired(policyId);
  RegisteredPipelineIntegrationPolicy? resolve({
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
  void promote(String policyId, int policyVersion) =>
      _core.promote(policyId, policyVersion);
  void deprecate(String policyId, int policyVersion) =>
      _core.deprecate(policyId, policyVersion);
  void retire(String policyId, int policyVersion) =>
      _core.retire(policyId, policyVersion);
}

/// Registry of pipeline execution policies.
class PipelineExecutionPolicyRegistry {
  PipelineExecutionPolicyRegistry({PipelineExecutionPolicyValidator? validator})
      : _core = _CicdIntegrationPolicyRegistryCore<
            RegisteredPipelineExecutionPolicy>(
          registryName: 'PipelineExecutionPolicyRegistry',
          policyIdOf: (p) => p.metadata.policyId,
          policyVersionOf: (p) => p.metadata.policyVersion,
          statusOf: (p) => p.metadata.status,
          validator: (p) =>
              (validator ?? const PipelineExecutionPolicyValidator())
                  .validate(p),
          statusUpdater: (policy, status) => policy.copyWith(
            metadata: policy.metadata.copyWith(status: status),
          ),
        );

  final _CicdIntegrationPolicyRegistryCore<RegisteredPipelineExecutionPolicy>
      _core;

  bool get isFrozen => _core.isFrozen;
  List<RegisteredPipelineExecutionPolicy> list() => _core.list();
  List<RegisteredPipelineExecutionPolicy> query() => _core.query();
  void register(RegisteredPipelineExecutionPolicy policy) =>
      _core.register(policy);
  void registerAll(Iterable<RegisteredPipelineExecutionPolicy> policies) =>
      _core.registerAll(policies);
  void freeze() => _core.freeze();
  bool contains(String policyId, int policyVersion) =>
      _core.contains(policyId, policyVersion);
  RegisteredPipelineExecutionPolicy? get(String policyId, int policyVersion) =>
      _core.get(policyId, policyVersion);
  RegisteredPipelineExecutionPolicy? byVersion(
    String policyId,
    int policyVersion,
  ) =>
      _core.byVersion(policyId, policyVersion);
  RegisteredPipelineExecutionPolicy? getLatestVersion(String policyId) =>
      _core.getLatestVersion(policyId);
  RegisteredPipelineExecutionPolicy? candidate(String policyId) =>
      _core.candidate(policyId);
  RegisteredPipelineExecutionPolicy? active(String policyId) =>
      _core.active(policyId);
  RegisteredPipelineExecutionPolicy? deprecated(String policyId) =>
      _core.deprecated(policyId);
  RegisteredPipelineExecutionPolicy? retired(String policyId) =>
      _core.retired(policyId);
  RegisteredPipelineExecutionPolicy? resolve({
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
  void promote(String policyId, int policyVersion) =>
      _core.promote(policyId, policyVersion);
  void deprecate(String policyId, int policyVersion) =>
      _core.deprecate(policyId, policyVersion);
  void retire(String policyId, int policyVersion) =>
      _core.retire(policyId, policyVersion);
}

/// Registry of deployment integration policies.
class DeploymentIntegrationPolicyRegistry {
  DeploymentIntegrationPolicyRegistry({
    DeploymentIntegrationPolicyValidator? validator,
  }) : _core = _CicdIntegrationPolicyRegistryCore<
            RegisteredDeploymentIntegrationPolicy>(
          registryName: 'DeploymentIntegrationPolicyRegistry',
          policyIdOf: (p) => p.metadata.policyId,
          policyVersionOf: (p) => p.metadata.policyVersion,
          statusOf: (p) => p.metadata.status,
          validator: (p) =>
              (validator ?? const DeploymentIntegrationPolicyValidator())
                  .validate(p),
          statusUpdater: (policy, status) => policy.copyWith(
            metadata: policy.metadata.copyWith(status: status),
          ),
        );

  final _CicdIntegrationPolicyRegistryCore<
      RegisteredDeploymentIntegrationPolicy> _core;

  bool get isFrozen => _core.isFrozen;
  List<RegisteredDeploymentIntegrationPolicy> list() => _core.list();
  List<RegisteredDeploymentIntegrationPolicy> query() => _core.query();
  void register(RegisteredDeploymentIntegrationPolicy policy) =>
      _core.register(policy);
  void registerAll(Iterable<RegisteredDeploymentIntegrationPolicy> policies) =>
      _core.registerAll(policies);
  void freeze() => _core.freeze();
  bool contains(String policyId, int policyVersion) =>
      _core.contains(policyId, policyVersion);
  RegisteredDeploymentIntegrationPolicy? get(
    String policyId,
    int policyVersion,
  ) =>
      _core.get(policyId, policyVersion);
  RegisteredDeploymentIntegrationPolicy? byVersion(
    String policyId,
    int policyVersion,
  ) =>
      _core.byVersion(policyId, policyVersion);
  RegisteredDeploymentIntegrationPolicy? getLatestVersion(String policyId) =>
      _core.getLatestVersion(policyId);
  RegisteredDeploymentIntegrationPolicy? candidate(String policyId) =>
      _core.candidate(policyId);
  RegisteredDeploymentIntegrationPolicy? active(String policyId) =>
      _core.active(policyId);
  RegisteredDeploymentIntegrationPolicy? deprecated(String policyId) =>
      _core.deprecated(policyId);
  RegisteredDeploymentIntegrationPolicy? retired(String policyId) =>
      _core.retired(policyId);
  RegisteredDeploymentIntegrationPolicy? resolve({
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
  void promote(String policyId, int policyVersion) =>
      _core.promote(policyId, policyVersion);
  void deprecate(String policyId, int policyVersion) =>
      _core.deprecate(policyId, policyVersion);
  void retire(String policyId, int policyVersion) =>
      _core.retire(policyId, policyVersion);
}
