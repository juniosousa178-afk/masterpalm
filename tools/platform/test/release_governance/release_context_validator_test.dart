import 'package:masterpalm_platform/models/release_governance/release_context.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1.dart';
import 'package:masterpalm_platform/release_governance/release_context_validator.dart';
import 'package:test/test.dart';

import 'support/release_governance_test_fixtures.dart';

void main() {
  const validator = ReleaseContextValidator();
  final policy = ReleaseGovernancePolicyV1.create();

  group('ReleaseContextValidator', () {
    test('valid context passes', () {
      final result = validator.validate(
        ReleaseGovernanceTestFixtures.validContext(),
        policy: policy,
      );
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });

    test('empty releaseId fails', () {
      final base = ReleaseGovernanceTestFixtures.validContext();
      final context = ReleaseContext(
        projectId: base.projectId,
        releaseId: '',
        releaseName: base.releaseName,
        releaseVersion: base.releaseVersion,
        commitId: base.commitId,
        branch: base.branch,
        environment: base.environment,
        releaseType: base.releaseType,
        requestedAt: base.requestedAt,
        requestedBy: base.requestedBy,
      );
      final result = validator.validate(context, policy: policy);
      expect(result.isValid, isFalse);
    });

    test('production without commit fails', () {
      final base = ReleaseGovernanceTestFixtures.validContext();
      final context = ReleaseContext(
        projectId: base.projectId,
        releaseId: base.releaseId,
        releaseName: base.releaseName,
        releaseVersion: base.releaseVersion,
        commitId: '',
        branch: base.branch,
        environment: ReleaseEnvironment.production,
        releaseType: base.releaseType,
        requestedAt: base.requestedAt,
        requestedBy: base.requestedBy,
      );
      final result = validator.validate(context, policy: policy);
      expect(result.isValid, isFalse);
    });

    test('targetDate before requestedAt fails', () {
      final base = ReleaseGovernanceTestFixtures.validContext();
      final context = ReleaseContext(
        projectId: base.projectId,
        releaseId: base.releaseId,
        releaseName: base.releaseName,
        releaseVersion: base.releaseVersion,
        commitId: base.commitId,
        branch: base.branch,
        environment: base.environment,
        releaseType: base.releaseType,
        requestedAt: '2026-06-15T10:00:00.000Z',
        requestedBy: base.requestedBy,
        targetDate: '2026-06-14T00:00:00.000Z',
      );
      final result = validator.validate(context, policy: policy);
      expect(result.isValid, isFalse);
    });

    test('duplicate artifact fails', () {
      final base = ReleaseGovernanceTestFixtures.validContext();
      final dup = base.artifactReferences.first;
      final context = ReleaseContext(
        projectId: base.projectId,
        releaseId: base.releaseId,
        releaseName: base.releaseName,
        releaseVersion: base.releaseVersion,
        commitId: base.commitId,
        branch: base.branch,
        environment: base.environment,
        releaseType: base.releaseType,
        requestedAt: base.requestedAt,
        requestedBy: base.requestedBy,
        artifactReferences: [dup, dup],
      );
      final result = validator.validate(context, policy: policy);
      expect(result.isValid, isFalse);
    });
  });
}
