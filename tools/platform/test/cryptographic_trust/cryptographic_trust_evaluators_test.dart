import 'package:masterpalm_platform/cryptographic_trust/cryptographic_revocation_evaluator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_transparency_evaluator.dart';
import 'package:masterpalm_platform/cryptographic_trust/interfaces/cryptographic_transparency_proof_verifier.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust evaluators', () {
    const revocationEvaluator = CryptographicRevocationEvaluator();
    final transparencyEvaluator = CryptographicTransparencyEvaluator();

    group('CryptographicRevocationEvaluator', () {
      test('evaluateKey returns unknown when no revocations', () {
        final result = revocationEvaluator.evaluateKey(
          keyId: 'key-signer-001',
        );
        expect(result.status, CryptographicRevocationEvaluationStatus.unknown);
      });

      test('evaluateKey returns nonRevoked when no matching record', () {
        final result = revocationEvaluator.evaluateKey(
          keyId: 'key-signer-001',
          revocations: [
            CryptographicTrustTestFixtures.validRevocationRecord().copyWith(
              subjectId: 'other-key',
            ),
          ],
        );
        expect(
            result.status, CryptographicRevocationEvaluationStatus.nonRevoked);
      });

      test('evaluateKey returns revoked for active matching record', () {
        final result = revocationEvaluator.evaluateKey(
          keyId: 'key-signer-001',
          revocations: [CryptographicTrustTestFixtures.validRevocationRecord()],
          referenceTime: CryptographicTrustOperationalFixtures.referenceTime,
        );
        expect(result.status, CryptographicRevocationEvaluationStatus.revoked);
        expect(
            result.issues.any((i) => i.code == 'CT_REVOCATION_ACTIVE'), isTrue);
      });

      test('evaluateSubject returns revoked for matching subject', () {
        final record =
            CryptographicTrustTestFixtures.validRevocationRecord().copyWith(
          subjectType: CryptographicTrustSubjectType.artifact,
          subjectId: 'subject-art-001',
        );
        final result = revocationEvaluator.evaluateSubject(
          subjectId: 'subject-art-001',
          subjectType: CryptographicTrustSubjectType.artifact,
          revocations: [record],
          referenceTime: CryptographicTrustOperationalFixtures.referenceTime,
        );
        expect(result.status, CryptographicRevocationEvaluationStatus.revoked);
      });

      test('evaluateKey returns conflicting for duplicate active records', () {
        final base = CryptographicTrustTestFixtures.validRevocationRecord();
        final second = base.copyWith(
          revocationId: 'rev-key-002',
          reason: 'second record',
        );
        final result = revocationEvaluator.evaluateKey(
          keyId: 'key-signer-001',
          revocations: [base, second],
          referenceTime: CryptographicTrustOperationalFixtures.referenceTime,
        );
        expect(
            result.status, CryptographicRevocationEvaluationStatus.conflicting);
        expect(result.issues.any((i) => i.code == 'CT_REVOCATION_CONFLICT'),
            isTrue);
      });

      test('inactive revocation record does not revoke key', () {
        final record = CryptographicTrustTestFixtures.validRevocationRecord()
            .copyWith(status: CryptographicRevocationStatus.superseded);
        final result = revocationEvaluator.evaluateKey(
          keyId: 'key-signer-001',
          revocations: [record],
        );
        expect(
            result.status, CryptographicRevocationEvaluationStatus.nonRevoked);
      });
    });

    group('CryptographicTransparencyEvaluator', () {
      test('evaluate returns structurallyValid without proof verifier', () {
        final reference =
            CryptographicTrustTestFixtures.validTransparencyLogReference();
        final result = transparencyEvaluator.evaluate(reference: reference);
        expect(
          result.status,
          CryptographicTransparencyEvaluationStatus.structurallyValid,
        );
      });

      test('evaluate rejects rejected log status', () {
        final reference =
            CryptographicTrustTestFixtures.validTransparencyLogReference()
                .copyWith(status: CryptographicTransparencyLogStatus.rejected);
        final result = transparencyEvaluator.evaluate(reference: reference);
        expect(
            result.status, CryptographicTransparencyEvaluationStatus.invalid);
      });

      test('evaluate rejects expired log status', () {
        final reference =
            CryptographicTrustTestFixtures.validTransparencyLogReference()
                .copyWith(status: CryptographicTransparencyLogStatus.expired);
        final result = transparencyEvaluator.evaluate(reference: reference);
        expect(
            result.status, CryptographicTransparencyEvaluationStatus.invalid);
      });

      test(
          'evaluate returns unavailable when proof bytes missing with verifier',
          () {
        final evaluator = CryptographicTransparencyEvaluator(
          proofVerifier: _FakeTransparencyProofVerifier(),
        );
        final reference =
            CryptographicTrustTestFixtures.validTransparencyLogReference();
        final result = evaluator.evaluate(reference: reference);
        expect(
          result.status,
          CryptographicTransparencyEvaluationStatus.unavailable,
        );
      });

      test('evaluate verifies proof when bytes provided', () {
        final evaluator = CryptographicTransparencyEvaluator(
          proofVerifier: _FakeTransparencyProofVerifier(valid: true),
        );
        final reference =
            CryptographicTrustTestFixtures.validTransparencyLogReference();
        final result = evaluator.evaluate(
          reference: reference,
          leafDigestBytes: const [1, 2, 3],
          proofBytes: const [4, 5, 6],
          rootHashBytes: const [7, 8, 9],
        );
        expect(
            result.status, CryptographicTransparencyEvaluationStatus.verified);
      });

      test('evaluate invalid proof returns invalid status', () {
        final evaluator = CryptographicTransparencyEvaluator(
          proofVerifier: _FakeTransparencyProofVerifier(valid: false),
        );
        final reference =
            CryptographicTrustTestFixtures.validTransparencyLogReference();
        final result = evaluator.evaluate(
          reference: reference,
          leafDigestBytes: const [1],
          proofBytes: const [2],
          rootHashBytes: const [3],
        );
        expect(
            result.status, CryptographicTransparencyEvaluationStatus.invalid);
      });
    });
  });
}

class _FakeTransparencyProofVerifier
    implements CryptographicTransparencyProofVerifier {
  _FakeTransparencyProofVerifier({this.valid = false});

  final bool valid;

  @override
  String get logId => 'rekor-log-001';

  @override
  Set<CryptographicProviderCapability> get capabilities => const {
        CryptographicProviderCapability.transparencyProofVerification,
      };

  @override
  CryptographicTransparencyProofVerificationResult verifyProof({
    required List<int> leafDigest,
    required List<int> proofBytes,
    required List<int> rootHash,
  }) {
    return CryptographicTransparencyProofVerificationResult(
      outcome: valid
          ? CryptographicPrimitiveOutcome.valid
          : CryptographicPrimitiveOutcome.invalid,
      message: valid ? null : 'invalid proof',
    );
  }
}
