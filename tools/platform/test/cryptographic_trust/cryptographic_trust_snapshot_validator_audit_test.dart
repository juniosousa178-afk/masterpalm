import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_snapshot_validator.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust snapshot validator audit', () {
    const validator = CryptographicTrustSnapshotValidator();

    Future<dynamic> validSnapshot() async {
      return (await evaluatePassingSnapshot()).snapshot!;
    }

    test('valid snapshot passes validation', () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      expect(validator.validate(snapshot).isValid, isTrue);
    });

    test('evaluated snapshot is structurally present', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      expect(snapshot.fingerprint, isNotEmpty);
      expect(validator.validate(snapshot).warnings, isA<List<String>>());
    });

    test('empty fingerprint fails validation', () async {
      final snapshot = await validSnapshot();
      final mutated = snapshot.copyWith(fingerprint: '');
      expect(validator.validate(mutated).isValid, isFalse);
    });

    test('metadata fingerprint mismatch fails validation', () async {
      final snapshot = await validSnapshot();
      final mutated = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(fingerprint: 'mismatch'),
      );
      expect(validator.validate(mutated).isValid, isFalse);
    });

    test('empty snapshot id fails validation', () async {
      final snapshot = await validSnapshot();
      final mutated = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(
          cryptographicTrustSnapshotId: '',
        ),
      );
      expect(validator.validate(mutated).isValid, isFalse);
    });

    test('fixture snapshot passes structural validation', () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      expect(validator.validate(snapshot).isValid, isTrue);
    });

    test('invalid status mutation is detectable structurally', () async {
      final snapshot = await validSnapshot();
      final mutated = snapshot.copyWith(
        status: CryptographicTrustStatus.invalid,
      );
      expect(mutated.status, CryptographicTrustStatus.invalid);
      expect(validator.validate(mutated).warnings, isA<List<String>>());
    });
  });
}
