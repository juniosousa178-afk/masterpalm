import '../models/mes/mes_enums.dart';
import '../models/mes/mes_policy.dart';
import 'mes_exceptions.dart';

/// Registry of official MES policies.
class MESPolicyRegistry {
  final Map<String, MESPolicy> _policies = {};
  bool _frozen = false;

  bool get isFrozen => _frozen;

  Set<String> get supportedPolicyIds => _policies.keys.toSet();

  void register(MESPolicy policy) {
    if (_frozen) {
      throw MESPolicyException('MES policy registry is frozen');
    }
    final key = _key(policy.policyId, policy.policyVersion);
    if (_policies.containsKey(key)) {
      throw MESPolicyException(
        'Duplicate MES policy: ${policy.policyId} v${policy.policyVersion}',
      );
    }
    _policies[key] = policy;
  }

  void freeze() => _frozen = true;

  MESPolicy? getPolicy(String policyId, {int? policyVersion}) {
    if (policyVersion != null) {
      return _policies[_key(policyId, policyVersion)];
    }
    final matches = _policies.entries
        .where((e) => e.value.policyId == policyId)
        .toList()
      ..sort((a, b) => b.value.policyVersion.compareTo(a.value.policyVersion));
    return matches.isEmpty ? null : matches.first.value;
  }

  MESPolicy? getCandidatePolicy() {
    final candidates = _policies.values
        .where((p) => p.metadata.status == MESPolicyStatus.candidate)
        .toList()
      ..sort((a, b) => b.policyVersion.compareTo(a.policyVersion));
    return candidates.isEmpty ? null : candidates.first;
  }

  MESPolicy? getActivePolicy() {
    final active = _policies.values
        .where((p) => p.metadata.status == MESPolicyStatus.active)
        .toList()
      ..sort((a, b) => b.policyVersion.compareTo(a.policyVersion));
    return active.isEmpty ? null : active.first;
  }

  String _key(String policyId, int version) => '$policyId:v$version';
}
