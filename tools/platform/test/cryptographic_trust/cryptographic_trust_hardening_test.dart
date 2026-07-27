import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_canonical_serializer.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_collector.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_engine.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_snapshot_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/stores/in_memory_cryptographic_trust_store.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust hardening umbrella', () {
    test('evaluate publish load roundtrip preserves fingerprint', () async {
      final stack = CryptographicTrustOperationalFixtures.createTestStack();
      await stack.registerTestKeys();
      final published = await publishPassingSnapshot(stack: stack);
      final loaded = await stack.provider.load(
        published.snapshot!.metadata.cryptographicTrustSnapshotId,
      );
      expect(loaded?.fingerprint, published.snapshot!.fingerprint);
    });

    test('cross-module serializer validator agreement', () async {
      const serializer = CryptographicTrustCanonicalSerializer();
      const validator = CryptographicTrustSnapshotValidator();
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      expect(validator.validate(snapshot).isValid, isTrue);
      expect(serializer.snapshotFingerprint(snapshot), snapshot.fingerprint);
    });

    test('engine collector validator chain produces success status', () async {
      const engine = CryptographicTrustEngine();
      const collector = CryptographicTrustCollector();
      expect(engine, isNotNull);
      expect(collector, isNotNull);
      final result = await evaluateVerifiedScenario();
      expect(
          result.status, isNot(CryptographicTrustEvaluationStatus.unavailable));
      expect(result.snapshot, isNotNull);
    });

    test('partial and failed scenarios produce distinct statuses', () async {
      final partial = await evaluatePartialScenario();
      final failed = await evaluateFailedScenario();
      expect(
        partial.sourceResolutionSummary?.status,
        CryptographicTrustSourceResolutionStatus.partial,
      );
      expect(failed.verificationResult?.status.name, isNotEmpty);
    });

    test('store idempotency under hardening umbrella', () async {
      final store = InMemoryCryptographicTrustStore();
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      await store.save(snapshot);
      await store.save(snapshot);
      expect(await store.count(), 1);
    });

    test('no release authorization propagated across modules', () async {
      final result = await evaluatePassingSnapshot();
      expect(result.metadata['noReleaseAuthorization'], 'true');
      expect(
        result.snapshot!.limitations
            .any((l) => l.contains('no-release-authorization')),
        isTrue,
      );
    });
  });
}
