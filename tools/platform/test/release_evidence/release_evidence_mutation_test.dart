import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_policy.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_evidence_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_bundle_validator.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_identity_builder.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_policy_validator.dart';
import 'package:test/test.dart';

import 'support/release_evidence_test_fixtures.dart';

/// Mutation coverage registry for Sprint 04.3 Part 3.
/// Each case documents a single-field mutation and expected validator rejection.
void main() {
  group('Release Evidence mutation tests', () {
    const bundleValidator = ReleaseEvidenceBundleValidator();
    const policyValidator = ReleaseEvidencePolicyValidator();
    const identity = ReleaseEvidenceIdentityBuilder();

    final mutations = <String, dynamic Function()>{
      'bundle-empty-fingerprint': () =>
          ReleaseEvidenceTestFixtures.validBundle().copyWith(fingerprint: ''),
      'bundle-project-mismatch': () {
        final b = ReleaseEvidenceTestFixtures.validBundle();
        return b.copyWith(
          subject: b.subject.copyWith(projectId: 'other-project'),
        );
      },
      'bundle-duplicate-evidence': () {
        final b = ReleaseEvidenceTestFixtures.validBundle();
        return b.copyWith(
          evidence: [...b.evidence, b.evidence.first],
        );
      },
      'bundle-coverage-count-mismatch': () {
        final b = ReleaseEvidenceTestFixtures.validBundle();
        final json = b.toJson();
        (json['coverage'] as Map<String, dynamic>)['presentEvidenceCount'] = 99;
        return ReleaseEvidenceBundle.fromJson(json);
      },
    };

    for (final entry in mutations.entries) {
      test('bundle validator rejects ${entry.key}', () {
        final mutated = entry.value() as dynamic;
        final result = bundleValidator.validate(mutated);
        expect(result.isValid, isFalse, reason: entry.key);
      });
    }

    test('identity fingerprint changes when normative field mutates', () {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      final fp1 = identity.fingerprintForBundle(bundle);
      final mutated = bundle.copyWith(
        metadata: bundle.metadata.copyWith(commitId: 'mutated-commit'),
      );
      expect(identity.fingerprintForBundle(mutated), isNot(fp1));
    });

    test('policy validator rejects policy with empty rules mutation', () {
      final policy = ReleaseEvidencePolicyV1.create();
      final json = policy.toJson();
      json['rules'] = [];
      final mutated = ReleaseEvidencePolicy.fromJson(json);
      expect(policyValidator.validate(mutated).isValid, isFalse);
    });
  });
}
