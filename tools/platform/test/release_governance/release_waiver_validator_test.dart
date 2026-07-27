import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_waiver.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1.dart';
import 'package:masterpalm_platform/release_governance/release_waiver_validator.dart';
import 'package:test/test.dart';

import 'support/release_governance_test_fixtures.dart';

void main() {
  const validator = ReleaseWaiverValidator();
  final context = ReleaseGovernanceTestFixtures.validContext();
  final policy = ReleaseGovernancePolicyV1.create();

  group('ReleaseWaiverValidator', () {
    test('valid waiver passes', () {
      final result = validator.validate(
        ReleaseGovernanceTestFixtures.validWaiver(),
        releaseContext: context,
        policy: policy,
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });

    test('missing justification fails', () {
      final waiver = ReleaseGovernanceTestFixtures.validWaiver();
      final bad = ReleaseWaiver(
        waiverId: waiver.waiverId,
        releaseId: waiver.releaseId,
        policyId: waiver.policyId,
        policyVersion: waiver.policyVersion,
        status: waiver.status,
        scope: waiver.scope,
        authority: waiver.authority,
        issuerId: waiver.issuerId,
        issuedAt: waiver.issuedAt,
        expiration: waiver.expiration,
        justification: '',
        compensatingControls: waiver.compensatingControls,
        evidence: waiver.evidence,
        affectedRuleIds: waiver.affectedRuleIds,
        fingerprint: waiver.fingerprint,
        schemaVersion: waiver.schemaVersion,
      );
      final result =
          validator.validate(bad, releaseContext: context, policy: policy);
      expect(result.isValid, isFalse);
    });

    test('critical forbidden rule in waiver fails', () {
      final waiver = ReleaseGovernanceTestFixtures.validWaiver();
      final bad = ReleaseWaiver(
        waiverId: waiver.waiverId,
        releaseId: waiver.releaseId,
        policyId: waiver.policyId,
        policyVersion: waiver.policyVersion,
        status: waiver.status,
        scope: waiver.scope,
        authority: waiver.authority,
        issuerId: waiver.issuerId,
        issuedAt: waiver.issuedAt,
        expiration: waiver.expiration,
        justification: waiver.justification,
        compensatingControls: waiver.compensatingControls,
        evidence: waiver.evidence,
        affectedRuleIds: const ['RG001'],
        fingerprint: waiver.fingerprint,
        schemaVersion: waiver.schemaVersion,
      );
      final result =
          validator.validate(bad, releaseContext: context, policy: policy);
      expect(result.isValid, isFalse);
    });

    test('expired waiver warns', () {
      final waiver = ReleaseGovernanceTestFixtures.validWaiver();
      final bad = ReleaseWaiver(
        waiverId: waiver.waiverId,
        releaseId: waiver.releaseId,
        policyId: waiver.policyId,
        policyVersion: waiver.policyVersion,
        status: waiver.status,
        scope: waiver.scope,
        authority: waiver.authority,
        issuerId: waiver.issuerId,
        issuedAt: waiver.issuedAt,
        expiration: const ReleaseWaiverExpiration(
          validFrom: '2026-01-01T00:00:00.000Z',
          expiresAt: '2026-01-02T00:00:00.000Z',
          maximumDuration: 'P1D',
          expirationMode: ReleaseWaiverExpirationMode.timeBased,
        ),
        justification: waiver.justification,
        compensatingControls: waiver.compensatingControls,
        evidence: waiver.evidence,
        affectedRuleIds: waiver.affectedRuleIds,
        fingerprint: waiver.fingerprint,
        schemaVersion: waiver.schemaVersion,
      );
      final result = validator.validate(
        bad,
        releaseContext: context,
        policy: policy,
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );
      expect(result.warnings, isNotEmpty);
    });

    test('production waiver without compensating control fails', () {
      final waiver = ReleaseGovernanceTestFixtures.validWaiver();
      final bad = ReleaseWaiver(
        waiverId: waiver.waiverId,
        releaseId: waiver.releaseId,
        policyId: waiver.policyId,
        policyVersion: waiver.policyVersion,
        status: waiver.status,
        scope: waiver.scope,
        authority: waiver.authority,
        issuerId: waiver.issuerId,
        issuedAt: waiver.issuedAt,
        expiration: waiver.expiration,
        justification: waiver.justification,
        compensatingControls: const [],
        evidence: waiver.evidence,
        affectedRuleIds: waiver.affectedRuleIds,
        fingerprint: waiver.fingerprint,
        schemaVersion: waiver.schemaVersion,
      );
      final result =
          validator.validate(bad, releaseContext: context, policy: policy);
      expect(result.isValid, isFalse);
    });
  });
}
