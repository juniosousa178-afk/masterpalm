import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_exceptions.dart';
import 'package:masterpalm_platform/cryptographic_trust/stores/in_memory_cryptographic_trust_store.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_query.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('InMemoryCryptographicTrustStore', () {
    late InMemoryCryptographicTrustStore store;

    setUp(() {
      store = InMemoryCryptographicTrustStore();
    });

    test('save and load roundtrip', () async {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      await store.save(snapshot);
      final loaded = await store.load(
        snapshot.metadata.cryptographicTrustSnapshotId,
      );
      expect(loaded, isNotNull);
      expect(loaded!.fingerprint, snapshot.fingerprint);
    });

    test('save is idempotent for identical snapshot', () async {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      await store.save(snapshot);
      await store.save(snapshot);
      expect(await store.count(), 1);
    });

    test('save throws conflict for same id different canonical content',
        () async {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      await store.save(snapshot);
      final conflicting = snapshot.copyWith(
        status: CryptographicTrustStatus.invalid,
      );
      await expectLater(
        store.save(conflicting),
        throwsA(isA<CryptographicTrustSnapshotConflictException>()),
      );
    });

    test('latest returns newest evaluated snapshot for project', () async {
      final older = CryptographicTrustTestFixtures.validSnapshot().copyWith(
        metadata: CryptographicTrustTestFixtures.validSnapshotMetadata(
          fingerprint: CryptographicTrustTestFixtures.sha256Placeholder,
        ).copyWith(
          cryptographicTrustSnapshotId: 'ct-snap-old',
          evaluatedAt: '2026-07-21T12:00:00.000Z',
        ),
      );
      final newer = CryptographicTrustTestFixtures.validSnapshot().copyWith(
        metadata: CryptographicTrustTestFixtures.validSnapshotMetadata(
          fingerprint: CryptographicTrustTestFixtures.sha256Placeholder,
        ).copyWith(
          cryptographicTrustSnapshotId: 'ct-snap-new',
          evaluatedAt: CryptographicTrustOperationalFixtures.referenceTime,
        ),
      );
      await store.save(older);
      await store.save(newer);

      final latest = await store.latest(
        projectId: CryptographicTrustOperationalFixtures.projectId,
      );
      expect(latest?.metadata.cryptographicTrustSnapshotId, 'ct-snap-new');
    });

    test('query filters by project release and trust status', () async {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      await store.save(snapshot);

      final results = await store.query(
        CryptographicTrustQuery(
          projectId: CryptographicTrustOperationalFixtures.projectId,
          releaseId: CryptographicTrustOperationalFixtures.releaseId,
          trustStatus: CryptographicTrustStatus.provisional,
        ),
      );
      expect(results, hasLength(1));
    });

    test('query respects limit and offset', () async {
      for (var i = 0; i < 3; i++) {
        final snapshot =
            CryptographicTrustTestFixtures.validSnapshot().copyWith(
          metadata: CryptographicTrustTestFixtures.validSnapshotMetadata(
            fingerprint: CryptographicTrustTestFixtures.sha256Placeholder,
          ).copyWith(
            cryptographicTrustSnapshotId: 'ct-snap-$i',
            createdAt: '2026-07-2${i}T12:00:00.000Z',
          ),
        );
        await store.save(snapshot);
      }

      final page = await store.query(
        const CryptographicTrustQuery(limit: 1, offset: 1),
      );
      expect(page, hasLength(1));
    });

    test('invalidate removes snapshot', () async {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      await store.save(snapshot);
      await store.invalidate(snapshot.metadata.cryptographicTrustSnapshotId);
      expect(await store.exists(snapshot.metadata.cryptographicTrustSnapshotId),
          isFalse);
    });

    test('clear removes all snapshots', () async {
      await store.save(CryptographicTrustTestFixtures.validSnapshot());
      await store.clear();
      expect(await store.count(), 0);
    });
  });
}
