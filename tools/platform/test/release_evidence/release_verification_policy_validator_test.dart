import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_verification_check.dart';
import 'package:masterpalm_platform/models/release_evidence/release_verification_policy.dart';
import 'package:masterpalm_platform/models/release_evidence/release_verification_result.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_verification_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/release_verification_policy_validator.dart';
import 'package:masterpalm_platform/release_evidence/release_verification_result_validator.dart';
import 'package:test/test.dart';

import 'support/release_evidence_test_fixtures.dart';

void main() {
  const policyValidator = ReleaseVerificationPolicyValidator();
  const resultValidator = ReleaseVerificationResultValidator();

  group('ReleaseVerificationPolicyValidator', () {
    test('valid candidate policy passes', () {
      final result =
          policyValidator.validate(ReleaseVerificationPolicyV1.create());
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });

    test('empty supported schemas fails', () {
      final base = ReleaseVerificationPolicyV1.create();
      final policy = ReleaseVerificationPolicy(
        metadata: base.metadata,
        supportedSchemas: const [],
      );
      expect(policyValidator.validate(policy).isValid, isFalse);
    });

    test('signature required without partial verification fails', () {
      final base = ReleaseVerificationPolicyV1.create();
      final policy = ReleaseVerificationPolicy(
        metadata: base.metadata,
        requireSignature: true,
        allowUnverifiedSignature: true,
        allowPartialVerification: false,
      );
      expect(policyValidator.validate(policy).isValid, isFalse);
    });

    test('invalid coverage threshold fails', () {
      final base = ReleaseVerificationPolicyV1.create();
      final policy = ReleaseVerificationPolicy(
        metadata: base.metadata,
        minimumEvidenceCoverage: 150,
      );
      expect(policyValidator.validate(policy).isValid, isFalse);
    });
  });

  group('ReleaseVerificationResultValidator', () {
    test('valid verification result passes', () {
      final result = resultValidator.validate(
        ReleaseEvidenceTestFixtures.validVerificationResult(),
      );
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });

    test('verified with failed checks fails', () {
      final base = ReleaseEvidenceTestFixtures.validVerificationResult();
      final verification = ReleaseVerificationResult(
        verificationId: base.verificationId,
        subject: base.subject,
        policyReference: base.policyReference,
        status: base.status,
        checks: const [
          ReleaseVerificationCheck(
            checkId: 'check-fail',
            checkType: ReleaseVerificationCheckType.identity,
            subjectId: 'subject-release-001',
            status: ReleaseVerificationCheckStatus.failed,
          ),
        ],
        compatibility: base.compatibility,
        eligibility: base.eligibility,
        coverage: base.coverage,
        evaluatedAt: base.evaluatedAt,
        referenceTime: base.referenceTime,
        fingerprint: base.fingerprint,
        schemaVersion: base.schemaVersion,
      );
      expect(resultValidator.validate(verification).isValid, isFalse);
    });
  });
}
