import 'package:masterpalm_platform/cryptographic_trust/cryptographic_revocation_evaluator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_revocation_validator.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust revocation audit', () {
    const evaluator = CryptographicRevocationEvaluator();
    const validator = CryptographicRevocationValidator();

    test('validator accepts valid revocation record', () {
      final record = CryptographicTrustTestFixtures.validRevocationRecord();
      expect(validator.validate(record).isValid, isTrue);
    });

    test('validator rejects empty revocationId', () {
      final record = CryptographicTrustTestFixtures.validRevocationRecord()
          .copyWith(revocationId: '');
      expect(validator.validate(record).isValid, isFalse);
    });

    test('evaluator returns active for matching key revocation', () {
      final record = CryptographicTrustTestFixtures.validRevocationRecord();
      final result = evaluator.evaluateKey(
        keyId: record.subjectId,
        revocations: [record],
        referenceTime: CryptographicTrustOperationalFixtures.referenceTime,
      );
      expect(result.status, CryptographicRevocationEvaluationStatus.revoked);
    });

    test('evaluator returns notRevoked when no matching record', () {
      final result = evaluator.evaluateKey(
        keyId: 'unknown-key',
        revocations: [CryptographicTrustTestFixtures.validRevocationRecord()],
        referenceTime: CryptographicTrustOperationalFixtures.referenceTime,
      );
      expect(result.status, CryptographicRevocationEvaluationStatus.nonRevoked);
    });

    test('duplicate active revocations return conflicting status', () {
      final record = CryptographicTrustTestFixtures.validRevocationRecord();
      final duplicate = record.copyWith(revocationId: 'rev-dup');
      final result = evaluator.evaluateKey(
        keyId: record.subjectId,
        revocations: [record, duplicate],
        referenceTime: CryptographicTrustOperationalFixtures.referenceTime,
      );
      expect(
        result.status,
        CryptographicRevocationEvaluationStatus.conflicting,
      );
    });
  });
}
