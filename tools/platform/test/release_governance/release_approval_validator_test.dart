import 'package:masterpalm_platform/models/release_governance/release_approval.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/release_governance/release_approval_validator.dart';
import 'package:test/test.dart';

import 'support/release_governance_test_fixtures.dart';

void main() {
  const validator = ReleaseApprovalValidator();
  final context = ReleaseGovernanceTestFixtures.validContext();

  group('ReleaseApprovalValidator', () {
    test('valid approval passes', () {
      final result = validator.validate(
        ReleaseGovernanceTestFixtures.validApproval(),
        releaseContext: context,
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });

    test('release mismatch fails', () {
      final approval = ReleaseGovernanceTestFixtures.validApproval();
      final bad = ReleaseApproval(
        approvalId: approval.approvalId,
        releaseId: 'other-release',
        policyId: approval.policyId,
        policyVersion: approval.policyVersion,
        approvalType: approval.approvalType,
        authority: approval.authority,
        approverId: approval.approverId,
        status: approval.status,
        decision: approval.decision,
        scope: approval.scope,
        issuedAt: approval.issuedAt,
        validFrom: approval.validFrom,
        expiresAt: approval.expiresAt,
        evidence: approval.evidence,
        reason: approval.reason,
        fingerprint: approval.fingerprint,
        schemaVersion: approval.schemaVersion,
      );
      final result = validator.validate(bad, releaseContext: context);
      expect(result.isValid, isFalse);
    });

    test('inactive authority fails', () {
      final approval = ReleaseGovernanceTestFixtures.validApproval();
      final authority = ReleaseApprovalAuthority(
        authorityId: approval.authority.authorityId,
        authorityType: approval.authority.authorityType,
        role: approval.authority.role,
        organization: approval.authority.organization,
        allowedApprovalTypes: approval.authority.allowedApprovalTypes,
        allowedEnvironments: approval.authority.allowedEnvironments,
        allowedReleaseTypes: approval.authority.allowedReleaseTypes,
        separationOfDutiesGroup: approval.authority.separationOfDutiesGroup,
        validFrom: approval.authority.validFrom,
        status: ReleaseAuthorityStatus.revoked,
        schemaVersion: approval.authority.schemaVersion,
      );
      final bad = ReleaseApproval(
        approvalId: approval.approvalId,
        releaseId: approval.releaseId,
        policyId: approval.policyId,
        policyVersion: approval.policyVersion,
        approvalType: approval.approvalType,
        authority: authority,
        approverId: approval.approverId,
        status: approval.status,
        decision: approval.decision,
        scope: approval.scope,
        issuedAt: approval.issuedAt,
        validFrom: approval.validFrom,
        expiresAt: approval.expiresAt,
        evidence: approval.evidence,
        reason: approval.reason,
        fingerprint: approval.fingerprint,
        schemaVersion: approval.schemaVersion,
      );
      final result = validator.validate(bad, releaseContext: context);
      expect(result.isValid, isFalse);
    });

    test('expired approval warns', () {
      final result = validator.validate(
        ReleaseGovernanceTestFixtures.validApproval(
          expiresAt: '2026-01-01T00:00:00.000Z',
        ),
        releaseContext: context,
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );
      expect(result.warnings, isNotEmpty);
    });

    test('missing evidence fails', () {
      final approval = ReleaseGovernanceTestFixtures.validApproval();
      final bad = ReleaseApproval(
        approvalId: approval.approvalId,
        releaseId: approval.releaseId,
        policyId: approval.policyId,
        policyVersion: approval.policyVersion,
        approvalType: approval.approvalType,
        authority: approval.authority,
        approverId: approval.approverId,
        status: approval.status,
        decision: approval.decision,
        scope: approval.scope,
        issuedAt: approval.issuedAt,
        validFrom: approval.validFrom,
        expiresAt: approval.expiresAt,
        evidence: const [],
        reason: approval.reason,
        fingerprint: approval.fingerprint,
        schemaVersion: approval.schemaVersion,
      );
      final result = validator.validate(bad, releaseContext: context);
      expect(result.isValid, isFalse);
    });
  });
}
