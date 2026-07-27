import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust dashboard audit', () {
    test('published snapshot exposes dashboard-ready status fields', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      expect(snapshot.status, isA<CryptographicTrustStatus>());
      expect(snapshot.verificationResults, isNotEmpty);
      expect(snapshot.limitations, isNotEmpty);
    });

    test('snapshot includes component counts for dashboard widgets', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      expect(snapshot.subjects.length, greaterThan(0));
      expect(snapshot.signatures.length, greaterThan(0));
      expect(snapshot.trustPolicies.length, greaterThan(0));
    });

    test('limitations document no release authorization for dashboard',
        () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      expect(
        snapshot.limitations.any((l) => l.contains('no-release-authorization')),
        isTrue,
      );
    });

    test('fixture snapshot provides stable dashboard fields without evaluate',
        () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      expect(snapshot.metadata.projectId, isNotEmpty);
      expect(snapshot.fingerprint, isNotEmpty);
      expect(snapshot.identity, isNotNull);
    });
  });
}
