import '../models/score/score_policy.dart';
import 'score_exceptions.dart';
import 'score_policy_validator.dart';

/// Registry of score policies.
class ScoreRegistry {
  ScoreRegistry({ScorePolicyValidator? validator})
      : _validator = validator ?? const ScorePolicyValidator();

  final ScorePolicyValidator _validator;
  final Map<String, ScorePolicy> _policies = {};
  bool _frozen = false;

  void register(ScorePolicy policy) {
    if (_frozen) {
      throw ScorePolicyException('ScoreRegistry is frozen');
    }
    final validation = _validator.validate(policy);
    if (!validation.isValid) {
      throw ScorePolicyException(validation.errors.join('; '));
    }
    if (_policies.containsKey(policy.policyId)) {
      throw ScorePolicyException('Duplicate policyId: ${policy.policyId}');
    }
    _policies[policy.policyId] = policy;
  }

  void freeze() => _frozen = true;

  bool get isFrozen => _frozen;

  ScorePolicy? getPolicy(String policyId) => _policies[policyId];

  Set<String> get supportedPolicyIds => _policies.keys.toSet();

  List<ScorePolicy> get allPolicies => _policies.values.toList()
    ..sort((a, b) => a.policyId.compareTo(b.policyId));
}
