import 'package:masterpalm_platform/cryptographic_trust/cryptographic_transparency_evaluator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_transparency_log_reference_validator.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust transparency audit', () {
    const validator = CryptographicTransparencyLogReferenceValidator();
    final evaluator = CryptographicTransparencyEvaluator();

    test('validator accepts valid transparency reference', () {
      final ref =
          CryptographicTrustTestFixtures.validTransparencyLogReference();
      expect(validator.validate(ref).isValid, isTrue);
    });

    test('validator rejects empty logId', () {
      final ref = CryptographicTrustTestFixtures.validTransparencyLogReference()
          .copyWith(logId: '');
      expect(validator.validate(ref).isValid, isFalse);
    });

    test('evaluator returns structurallyValid for valid reference', () {
      final ref =
          CryptographicTrustTestFixtures.validTransparencyLogReference();
      final result = evaluator.evaluate(reference: ref);
      expect(
        result.status,
        CryptographicTransparencyEvaluationStatus.structurallyValid,
      );
    });

    test('snapshot includes transparency references after evaluation',
        () async {
      final stack = CryptographicTrustOperationalFixtures.createTestStack();
      await stack.registerTestKeys();
      final result = await stack.provider.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(result.snapshot?.transparencyLogReferences, isNotEmpty);
    });
  });
}
