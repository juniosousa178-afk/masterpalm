import 'package:masterpalm_platform/models/release_governance/release_governance_policy.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1_1.dart';
import 'package:masterpalm_platform/release_governance/release_governance_canonical_serializer.dart';
import 'package:test/test.dart';

void main() {
  group('Release Governance policy versioning', () {
    const serializer = ReleaseGovernanceCanonicalSerializer();

    test('v1 and v1.1 policy fingerprints differ', () {
      final v1 = ReleaseGovernancePolicyV1.create();
      final v11 = ReleaseGovernancePolicyV11.create();

      final fpV1 = serializer.policyFingerprint(v1);
      final fpV11 = serializer.policyFingerprint(v11);

      expect(fpV1, isNot(equals(fpV11)));
      expect(v1.metadata.policyId, isNot(v11.metadata.policyId));
    });

    test('RG006 operator changes from isValid to isEligible in v1.1', () {
      final v1 = ReleaseGovernancePolicyV1.create();
      final v11 = ReleaseGovernancePolicyV11.create();

      final rg006V1 = v1.rules.firstWhere((r) => r.ruleId == 'RG006');
      final rg006V11 = v11.rules.firstWhere((r) => r.ruleId == 'RG006');

      expect(rg006V1.operator.name, 'isValid');
      expect(rg006V11.operator.name, 'isEligible');
      expect(rg006V11.tags, contains('rg006-eligibility-fix'));
    });

    test('createdAt change does not alter policy comparable fingerprint', () {
      final base = ReleaseGovernancePolicyV1.create();
      final fpBase = serializer.policyFingerprint(base);

      final mutatedJson = base.toJson();
      final metadata = Map<String, dynamic>.from(
        mutatedJson['metadata'] as Map<String, dynamic>,
      );
      metadata['createdAt'] = '2099-01-01T00:00:00.000Z';
      mutatedJson['metadata'] = metadata;

      final restored = ReleaseGovernancePolicy.fromJson(mutatedJson);
      final fpMutated = serializer.policyFingerprint(restored);

      expect(fpMutated, fpBase);
      expect(restored.metadata.createdAt, isNot(base.metadata.createdAt));
    });

    test('v1.1 metadata records migration changelog entry', () {
      final v11 = ReleaseGovernancePolicyV11.create();
      expect(v11.metadata.policyVersion, 2);
      expect(
        v11.metadata.changelog.any(
          (e) => e.summary.contains('isEligible'),
        ),
        isTrue,
      );
    });
  });
}
