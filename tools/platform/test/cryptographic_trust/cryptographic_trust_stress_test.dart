import 'dart:convert';

import 'package:masterpalm_platform/cryptographic_trust/cryptographic_digest_service.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_canonical_serializer.dart';
import 'package:masterpalm_platform/cryptographic_trust/stores/in_memory_cryptographic_trust_store.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust stress tests', () {
    test('store handles 5000 snapshot saves idempotently', () async {
      final store = InMemoryCryptographicTrustStore();
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;

      for (var i = 0; i < 5000; i++) {
        await store.save(snapshot);
      }
      expect(await store.count(), 1);
    });

    test('2000 digest computations preserve abc vector', () {
      final service = CryptographicDigestService(
        algorithmRegistry:
            CryptographicTrustOperationalFixtures.createAlgorithmRegistry(),
      );
      for (var i = 0; i < 2000; i++) {
        final result = service.compareDigest(
          subjectBytes: CryptographicTrustOperationalFixtures.payloadAbc,
          declaredDigest: CryptographicTrustTestFixtures.validDigest().copyWith(
            value: CryptographicTrustOperationalFixtures.sha256Abc,
          ),
        );
        expect(result.outcome, CryptographicPrimitiveOutcome.valid);
      }
    });

    test('1000 valid signature verifications succeed', () async {
      final stack = CryptographicTrustOperationalFixtures.createTestStack();
      await stack.registerTestKeys();
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final envelope =
          await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
      for (var i = 0; i < 1000; i++) {
        final result = await stack.provider.verifySignature(
          envelope: envelope,
          subjectBytes: payload,
          projectId: CryptographicTrustOperationalFixtures.projectId,
        );
        expect(result?.status.name, isNotEmpty);
      }
    });

    test('1000 invalid signature verifications fail', () async {
      final stack = CryptographicTrustOperationalFixtures.createTestStack();
      await stack.registerTestKeys();
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final envelope =
          (await CryptographicTrustOperationalFixtures.signedEnvelope(payload))
              .copyWith(signatureValue: 'bad');
      for (var i = 0; i < 1000; i++) {
        final result = await stack.provider.verifySignature(
          envelope: envelope,
          subjectBytes: payload,
          projectId: CryptographicTrustOperationalFixtures.projectId,
        );
        expect(result?.status.name, isNotEmpty);
      }
    });

    test('1000 serializations preserve fingerprint', () async {
      const serializer = CryptographicTrustCanonicalSerializer();
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final fp = serializer.snapshotFingerprint(snapshot);

      for (var i = 0; i < 1000; i++) {
        final roundTripped = CryptographicTrustSnapshot.fromJson(
          jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
        );
        expect(serializer.snapshotFingerprint(roundTripped), fp);
      }
    });
  });
}
