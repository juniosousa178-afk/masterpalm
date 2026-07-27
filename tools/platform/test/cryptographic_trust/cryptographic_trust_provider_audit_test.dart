import 'package:masterpalm_platform/cryptographic_trust/stores/in_memory_cryptographic_trust_store.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_query.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_operational_fixtures.dart';

void main() {
  group('Cryptographic Trust provider audit', () {
    late CryptographicTrustTestStack stack;

    setUp(() async {
      stack = CryptographicTrustOperationalFixtures.createTestStack();
      await stack.registerTestKeys();
    });

    test('evaluate is idempotent across 5 repetitions', () async {
      final fingerprints = <String>{};
      for (var i = 0; i < 5; i++) {
        final result = await evaluatePassingSnapshot(stack: stack);
        fingerprints.add(result.snapshot!.fingerprint);
      }
      expect(fingerprints, hasLength(1));
    });

    test('evaluateAndPublish is idempotent on second publish', () async {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest();
      final first = await stack.provider.evaluateAndPublish(request);
      final second = await stack.provider.evaluateAndPublish(request);
      expect(await stack.store.count(), 1);
      expect(
        second.snapshot!.metadata.cryptographicTrustSnapshotId,
        first.snapshot!.metadata.cryptographicTrustSnapshotId,
      );
    });

    test('publish direct is idempotent', () async {
      final result = await publishPassingSnapshot(stack: stack);
      final snapshot = result.snapshot!;
      await stack.provider.publish(snapshot);
      final loaded = await stack.provider.load(
        snapshot.metadata.cryptographicTrustSnapshotId,
      );
      expect(loaded!.fingerprint, snapshot.fingerprint);
    });

    test('latest returns most recent snapshot for project', () async {
      final snapshot = (await publishPassingSnapshot(stack: stack)).snapshot!;
      final latest = await stack.provider.latest(
        projectId: snapshot.metadata.projectId,
        releaseId: snapshot.metadata.releaseId,
      );
      expect(
        latest?.metadata.cryptographicTrustSnapshotId,
        snapshot.metadata.cryptographicTrustSnapshotId,
      );
    });

    test('query filters by projectId', () async {
      await publishPassingSnapshot(stack: stack);
      final results = await stack.provider.query(
        const CryptographicTrustQuery(
          projectId: CryptographicTrustOperationalFixtures.projectId,
        ),
      );
      expect(results, isNotEmpty);
    });

    test('invalidate removes snapshot from load', () async {
      final snapshot = (await publishPassingSnapshot(stack: stack)).snapshot!;
      await stack.provider.invalidate(
        snapshot.metadata.cryptographicTrustSnapshotId,
      );
      expect(
        await stack.provider.load(
          snapshot.metadata.cryptographicTrustSnapshotId,
        ),
        isNull,
      );
    });
  });

  group('Cryptographic Trust provider store integration', () {
    test('simulated concurrent saves are serialized and idempotent', () async {
      final store = InMemoryCryptographicTrustStore();
      final stack = CryptographicTrustOperationalFixtures.createTestStack(
        store: store,
      );
      await stack.registerTestKeys();
      final snapshot = (await evaluatePassingSnapshot(stack: stack)).snapshot!;
      await Future.wait(List.generate(10, (_) => store.save(snapshot)));
      expect(await store.count(), 1);
    });
  });
}
