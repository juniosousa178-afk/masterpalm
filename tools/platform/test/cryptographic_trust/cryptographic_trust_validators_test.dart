import 'package:masterpalm_platform/cryptographic_trust/cryptographic_attestation_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_digest_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_key_reference_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_revocation_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_signature_envelope_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_signer_identity_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_transparency_log_reference_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_anchor_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_chain_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_policy_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_requirement_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_snapshot_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_verification_request_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_verification_result_validator.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_verification_models.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust validators', () {
    test('digest validator accepts valid digest', () {
      final result = const CryptographicDigestValidator().validate(
        CryptographicTrustTestFixtures.validDigest(),
      );
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('digest validator rejects empty subjectId', () {
      final digest =
          CryptographicTrustTestFixtures.validDigest().copyWith(subjectId: '');
      final result = const CryptographicDigestValidator().validate(digest);
      expect(result.isValid, isFalse);
      expect(
          result.issues.any((i) => i.code == 'CT_DIGEST_SUBJECT_ID'), isTrue);
      expect(
        result.issues.firstWhere((i) => i.code == 'CT_DIGEST_SUBJECT_ID').path,
        'subjectId',
      );
    });

    test('digest validator rejects invalid outputSizeBits', () {
      final digest = CryptographicTrustTestFixtures.validDigest().copyWith(
        descriptor: CryptographicTrustTestFixtures.validDigestDescriptor()
            .copyWith(outputSizeBits: 0),
      );
      final result = const CryptographicDigestValidator().validate(digest);
      expect(result.isValid, isFalse);
      expect(
          result.issues.any((i) => i.code == 'CT_DIGEST_OUTPUT_SIZE'), isTrue);
    });

    test('key reference validator accepts valid key reference', () {
      final result = const CryptographicKeyReferenceValidator().validate(
        CryptographicTrustTestFixtures.validKeyReference(),
      );
      expect(result.isValid, isTrue);
    });

    test('key reference validator rejects sensitive metadata', () {
      final key = CryptographicTrustTestFixtures.validKeyReference().copyWith(
        metadata: const {'privateKey': 'must-not-appear'},
      );
      final result = const CryptographicKeyReferenceValidator().validate(key);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'CT_KEY_SENSITIVE_METADATA'),
        isTrue,
      );
      expect(
        result.issues
            .firstWhere((i) => i.code == 'CT_KEY_SENSITIVE_METADATA')
            .severity,
        CryptographicIssueSeverity.critical,
      );
    });

    test('key reference validator rejects incoherent validity window', () {
      final key = CryptographicTrustTestFixtures.validKeyReference().copyWith(
        validFrom: '2027-01-01T00:00:00.000Z',
        validUntil: '2026-01-01T00:00:00.000Z',
      );
      final result = const CryptographicKeyReferenceValidator().validate(key);
      expect(result.isValid, isFalse);
      expect(result.issues.any((i) => i.code == 'CT_KEY_VALIDITY'), isTrue);
    });

    test('signature envelope validator accepts valid envelope', () {
      final result = const CryptographicSignatureEnvelopeValidator().validate(
        CryptographicTrustTestFixtures.validSignatureEnvelope(),
      );
      expect(result.isValid, isTrue);
    });

    test('signature envelope validator rejects subject digest mismatch', () {
      final envelope =
          CryptographicTrustTestFixtures.validSignatureEnvelope().copyWith(
        subjectDigest: CryptographicTrustTestFixtures.validDigest(
          subjectId: 'other-subject',
        ),
      );
      final result =
          const CryptographicSignatureEnvelopeValidator().validate(envelope);
      expect(result.isValid, isFalse);
      expect(
          result.issues.any((i) => i.code == 'CT_SIG_SUBJECT_DIGEST_MISMATCH'),
          isTrue);
    });

    test('attestation validator rejects duplicate subject ids', () {
      final subject = CryptographicTrustTestFixtures.validAttestationSubject();
      final attestation =
          CryptographicTrustTestFixtures.validAttestationStatement().copyWith(
        subjects: [subject, subject],
      );
      final result =
          const CryptographicAttestationValidator().validate(attestation);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'CT_ATTESTATION_DUPLICATE_SUBJECT'),
        isTrue,
      );
    });

    test('policy validator accepts valid policy', () {
      final result = const CryptographicTrustPolicyValidator().validate(
        CryptographicTrustTestFixtures.validPolicy(),
      );
      expect(result.isValid, isTrue);
    });

    test('policy validator rejects duplicate requirement ids', () {
      final requirement = CryptographicTrustTestFixtures.validRequirement();
      final policy = CryptographicTrustTestFixtures.validPolicy().copyWith(
        requirements: [requirement, requirement],
      );
      final result = const CryptographicTrustPolicyValidator().validate(policy);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'CT_POLICY_DUPLICATE_REQUIREMENT'),
        isTrue,
      );
    });

    test('verification request validator accepts valid request', () {
      final result = const CryptographicVerificationRequestValidator().validate(
        CryptographicTrustTestFixtures.validVerificationRequest(),
      );
      expect(result.isValid, isTrue);
    });

    test('verification request validator rejects empty subjects', () {
      final request =
          CryptographicTrustTestFixtures.validVerificationRequest().copyWith(
        subjects: const [],
      );
      final result =
          const CryptographicVerificationRequestValidator().validate(request);
      expect(result.isValid, isFalse);
      expect(result.issues.any((i) => i.code == 'CT_VERIFY_REQUEST_SUBJECTS'),
          isTrue);
    });

    test('verification result validator rejects release authorization metadata',
        () {
      final resultModel =
          CryptographicTrustTestFixtures.validVerificationResult().copyWith(
        metadata: const {'releaseAuthorized': 'true'},
      );
      final result = const CryptographicVerificationResultValidator()
          .validate(resultModel);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any(
          (i) =>
              i.code == 'CT_VERIFY_RESULT_RELEASE_AUTHORIZATION' ||
              i.code == 'CT_VERIFY_RES_RELEASE_AUTH_FIELD',
        ),
        isTrue,
      );
    });

    test('verification result validator rejects verified with critical issues',
        () {
      final resultModel = CryptographicVerificationResult(
        verificationId: 'verify-result-002',
        requestId: 'verify-req-001',
        projectId: CryptographicTrustTestFixtures.projectId,
        status: CryptographicVerificationStatus.verified,
        trustLevel: CryptographicTrustLevel.high,
        issues: const [
          CryptographicVerificationIssue(
            code: 'CT_CRITICAL',
            severity: CryptographicIssueSeverity.critical,
            path: 'issues',
            message: 'critical issue present',
          ),
        ],
      );
      final result = const CryptographicVerificationResultValidator()
          .validate(resultModel);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any(
          (i) =>
              i.code == 'CT_VERIFY_RESULT_STATUS' ||
              i.code == 'CT_VERIFY_RES_STATUS_ISSUES',
        ),
        isTrue,
      );
    });

    test('trust chain validator accepts valid chain', () {
      final result = const CryptographicTrustChainValidator().validate(
        CryptographicTrustTestFixtures.validTrustChain(),
      );
      expect(result.isValid, isTrue);
    });

    test('snapshot validator accepts valid snapshot', () {
      final result = const CryptographicTrustSnapshotValidator().validate(
        CryptographicTrustTestFixtures.validSnapshot(),
      );
      expect(result.isValid, isTrue);
    });

    test('snapshot validator rejects fingerprint mismatch', () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot().copyWith(
        fingerprint:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      final result =
          const CryptographicTrustSnapshotValidator().validate(snapshot);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'CT_SNAPSHOT_FINGERPRINT_MISMATCH'),
        isTrue,
      );
    });

    test('validators sort issues deterministically by code', () {
      final digest = CryptographicTrustTestFixtures.validDigest().copyWith(
        subjectId: '',
        value: '',
        encoding: '',
      );
      final result = const CryptographicDigestValidator().validate(digest);
      final codes = result.issues.map((i) => i.code).toList();
      expect(codes, equals(List<String>.from(codes)..sort()));
    });

    test('digest validator aggregates multiple issues', () {
      final digest = CryptographicTrustTestFixtures.validDigest().copyWith(
        subjectId: '',
        value: '',
      );
      final result = const CryptographicDigestValidator().validate(digest);
      expect(result.isValid, isFalse);
      expect(result.issues.length, greaterThanOrEqualTo(2));
      expect(result.errors.length, greaterThanOrEqualTo(2));
    });

    test('signer identity validator rejects sensitive claims', () {
      final identity =
          CryptographicTrustTestFixtures.validSignerIdentity().copyWith(
        claims: const {'token': 'secret-value'},
      );
      final result =
          const CryptographicSignerIdentityValidator().validate(identity);
      expect(result.isValid, isFalse);
      expect(result.issues.any((i) => i.code == 'CT_SIGNER_SENSITIVE_CLAIM'),
          isTrue);
    });

    test('revocation validator accepts valid record', () {
      final result = const CryptographicRevocationValidator().validate(
        CryptographicTrustTestFixtures.validRevocationRecord(),
      );
      expect(result.isValid, isTrue);
    });

    test('transparency log reference validator accepts valid reference', () {
      final result =
          const CryptographicTransparencyLogReferenceValidator().validate(
        CryptographicTrustTestFixtures.validTransparencyLogReference(),
      );
      expect(result.isValid, isTrue);
    });

    test('trust anchor validator accepts valid anchor', () {
      final result = const CryptographicTrustAnchorValidator().validate(
        CryptographicTrustTestFixtures.validTrustAnchorReference(),
      );
      expect(result.isValid, isTrue);
    });

    test('requirement validator rejects invalid signature count', () {
      final requirement = CryptographicTrustTestFixtures.validRequirement()
          .copyWith(requiredSignatureCount: -1);
      final result =
          const CryptographicTrustRequirementValidator().validate(requirement);
      expect(result.isValid, isFalse);
      expect(
          result.issues.any((i) => i.code == 'CT_REQUIREMENT_SIGNATURE_COUNT'),
          isTrue);
    });
  });
}
