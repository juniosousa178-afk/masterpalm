import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_policy.dart';
import 'quality_gate_exceptions.dart';
import 'quality_gate_policy_validator.dart';

/// Registry of quality gate policies.
class QualityGatePolicyRegistry {
  QualityGatePolicyRegistry({QualityGatePolicyValidator? validator})
      : _validator = validator ?? const QualityGatePolicyValidator();

  final QualityGatePolicyValidator _validator;
  final Map<String, QualityGatePolicy> _policies = {};
  bool _frozen = false;

  bool get isFrozen => _frozen;

  List<QualityGatePolicy> list() => _policies.values.toList()
    ..sort((a, b) {
      final idCmp = a.metadata.policyId.compareTo(b.metadata.policyId);
      if (idCmp != 0) return idCmp;
      return a.metadata.policyVersion.compareTo(b.metadata.policyVersion);
    });

  void register(QualityGatePolicy policy) {
    if (_frozen) {
      throw QualityGateRegistryFrozenException('QualityGatePolicyRegistry');
    }
    final validation = _validator.validate(policy);
    if (!validation.isValid) {
      throw QualityGatePolicyInvalidException(
        'Invalid policy ${policy.metadata.policyId}',
        errors: validation.errors,
      );
    }
    final key = _key(policy.metadata.policyId, policy.metadata.policyVersion);
    if (_policies.containsKey(key)) {
      throw QualityGatePolicyInvalidException(
        'Duplicate policy: ${policy.metadata.policyId} v${policy.metadata.policyVersion}',
      );
    }
    _policies[key] = policy;
  }

  void registerAll(Iterable<QualityGatePolicy> policies) {
    for (final policy in policies) {
      register(policy);
    }
  }

  void freeze() => _frozen = true;

  bool contains(String policyId, int policyVersion) {
    return _policies.containsKey(_key(policyId, policyVersion));
  }

  QualityGatePolicy? get(String policyId, int policyVersion) {
    return _policies[_key(policyId, policyVersion)];
  }

  QualityGatePolicy? getLatestVersion(String policyId) {
    final matches = _policies.values
        .where((p) => p.metadata.policyId == policyId)
        .toList()
      ..sort(
        (a, b) => b.metadata.policyVersion.compareTo(a.metadata.policyVersion),
      );
    return matches.isEmpty ? null : matches.first;
  }

  QualityGatePolicy? getActive(String policyId) {
    final active = _policies.values
        .where((p) =>
            p.metadata.policyId == policyId &&
            p.metadata.status == QualityGatePolicyStatus.active)
        .toList()
      ..sort(
        (a, b) => b.metadata.policyVersion.compareTo(a.metadata.policyVersion),
      );
    return active.isEmpty ? null : active.first;
  }

  QualityGatePolicy? resolve({
    required String policyId,
    int? policyVersion,
    bool allowCandidate = true,
    bool historicalEvaluation = false,
  }) {
    final policy = policyVersion == null
        ? getLatestVersion(policyId)
        : get(policyId, policyVersion);
    if (policy == null) return null;
    if (policy.metadata.status == QualityGatePolicyStatus.retired &&
        !historicalEvaluation) {
      return null;
    }
    if (policy.metadata.status == QualityGatePolicyStatus.candidate &&
        !allowCandidate &&
        getActive(policyId) != null) {
      return getActive(policyId);
    }
    return policy;
  }

  String _key(String policyId, int version) => '$policyId:v$version';
}
