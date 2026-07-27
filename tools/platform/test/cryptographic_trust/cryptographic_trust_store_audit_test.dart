import 'package:masterpalm_platform/cryptographic_trust/stores/in_memory_cryptographic_trust_store.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_query.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust store audit', () {
    late InMemoryCryptographicTrustStore store;

    setUp(() => store = InMemoryCryptographicTrustStore());

    test('save overwrite with identical content is no-op count', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      await store.save(snapshot);
      await store.save(snapshot);
      expect(await store.count(), 1);
    });

    test('5000 saves of same snapshot remain idempotent', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      for (var i = 0; i < 5000; i++) {
        await store.save(snapshot);
      }
      expect(await store.count(), 1);
    });

    test('query filters by projectId', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      await store.save(snapshot);
      final results = await store.query(
        CryptographicTrustQuery(projectId: snapshot.metadata.projectId),
      );
      expect(results, isNotEmpty);
    });

    test('query with limit and offset', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      await store.save(snapshot);
      final page = await store.query(
        const CryptographicTrustQuery(
          projectId: CryptographicTrustOperationalFixtures.projectId,
          limit: 1,
          offset: 0,
        ),
      );
      expect(page, hasLength(1));
    });

    test('latest returns most recent snapshot', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      await store.save(snapshot);
      final latest = await store.latest(
        projectId: snapshot.metadata.projectId,
      );
      expect(
        latest?.metadata.cryptographicTrustSnapshotId,
        snapshot.metadata.cryptographicTrustSnapshotId,
      );
    });

    test('invalidate removes snapshot', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      await store.save(snapshot);
      await store.invalidate(snapshot.metadata.cryptographicTrustSnapshotId);
      expect(await store.exists(snapshot.metadata.cryptographicTrustSnapshotId),
          isFalse);
    });

    test('conflicting save with different fingerprint throws', () async {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      await store.save(snapshot);
      final conflicting = snapshot.copyWith(
        status: CryptographicTrustStatus.invalid,
      );
      await expectLater(store.save(conflicting), throwsA(isA<Exception>()));
    });

    test('clear removes all snapshots', () async {
      await store.save((await evaluatePassingSnapshot()).snapshot!);
      await store.clear();
      expect(await store.count(), 0);
    });
  });
}
