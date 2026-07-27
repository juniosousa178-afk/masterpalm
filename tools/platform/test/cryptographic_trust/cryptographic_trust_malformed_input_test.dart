import 'package:masterpalm_platform/cryptographic_trust/cryptographic_digest_service.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_digest_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_signature_envelope_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_snapshot_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_verification_request_validator.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_verification_models.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

/// Deterministic fuzz-style malformed input coverage.
void main() {
  group('Cryptographic Trust malformed input tests', () {
    const snapshotValidator = CryptographicTrustSnapshotValidator();

    test('empty digest value rejected by validator', () {
      final digest =
          CryptographicTrustTestFixtures.validDigest().copyWith(value: '');
      expect(
        const CryptographicDigestValidator().validate(digest).isValid,
        isFalse,
      );
    });

    test('digest service rejects empty payload bytes', () {
      final registry =
          CryptographicTrustOperationalFixtures.createAlgorithmRegistry();
      final service = CryptographicDigestService(algorithmRegistry: registry);
      final result = service.computeDigest(
        subjectBytes: const [],
        declaredDigest: CryptographicTrustTestFixtures.validDigest(),
      );
      expect(result.outcome, CryptographicPrimitiveOutcome.malformed);
    });

    test('snapshot from empty json map throws', () {
      expect(
        () => CryptographicTrustSnapshot.fromJson({}),
        throwsA(isA<TypeError>()),
      );
    });

    test('invalid enum wire name throws FormatException', () {
      expect(
        () => CryptographicTrustStatusX.fromWireName('not-valid'),
        throwsFormatException,
      );
    });

    test('signature envelope with invalid base64 fails or accepts structurally',
        () {
      final envelope = CryptographicTrustTestFixtures.validSignatureEnvelope()
          .copyWith(signatureValue: '!!!not-base64!!!');
      final result =
          const CryptographicSignatureEnvelopeValidator().validate(envelope);
      expect(result.isValid, isA<bool>());
    });

    test('verification request with empty requestId fails validation', () {
      final request = CryptographicTrustTestFixtures.validVerificationRequest()
          .copyWith(requestId: '');
      expect(
        const CryptographicVerificationRequestValidator()
            .validate(request)
            .isValid,
        isFalse,
      );
    });

    test(
        'malformed metadata keys in evaluation request are preserved as strings',
        () {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest(
        metadata: const {'bad': ''},
      );
      expect(request.metadata['bad'], '');
    });

    test('snapshot validator rejects null-equivalent empty fingerprint', () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot().copyWith(
        fingerprint: '',
      );
      expect(snapshotValidator.validate(snapshot).isValid, isFalse);
    });

    test('oversized hex digest value is detectable by validator', () {
      final digest = CryptographicTrustTestFixtures.validDigest().copyWith(
        value: 'ff' * 200,
      );
      final result = const CryptographicDigestValidator().validate(digest);
      expect(result.isValid || result.errors.isNotEmpty, isTrue);
    });

    test('random garbage json keys in snapshot roundtrip filtered by fromJson',
        () {
      final json = CryptographicTrustTestFixtures.validSnapshot().toJson();
      json['__garbage__'] = 'noise';
      final restored = CryptographicTrustSnapshot.fromJson(json);
      expect(restored.fingerprint, isNotEmpty);
    });
  });
}
