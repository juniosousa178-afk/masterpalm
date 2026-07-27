import 'dart:io';

import 'package:masterpalm_platform/cicd_integration/stores/in_memory_cicd_integration_store.dart';
import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/cicd_integration_provider.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_operational_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_query.dart';
import 'package:test/test.dart';

import 'support/cicd_integration_hardening_helpers.dart';
import 'support/cicd_integration_operational_fixtures.dart';

void main() {
  group('CI/CD Integration provider hardening', () {
    late CicdIntegrationProvider provider;

    setUp(() {
      provider =
          PlatformBootstrap.forRepo(Directory.current.path).cicdIntegration();
    });

    Future<dynamic> publishedSnapshot() async {
      final result = await publishPassingSnapshot(provider: provider);
      return result.snapshot!;
    }

    test('evaluate is idempotent across 5 repetitions', () async {
      final fingerprints = <String>{};
      for (var i = 0; i < 5; i++) {
        final result = await evaluatePassingSnapshot(provider: provider);
        fingerprints.add(result.snapshot!.fingerprint);
      }
      expect(fingerprints, hasLength(1));
    });

    test('evaluateAndPublish is idempotent on second publish', () async {
      final first = await publishPassingSnapshot(provider: provider);
      final second = await publishPassingSnapshot(provider: provider);
      expect(
        second.publicationStatus,
        CicdIntegrationPublicationStatus.skipped,
      );
      expect(
        second.snapshot!.metadata.cicdIntegrationSnapshotId,
        first.snapshot!.metadata.cicdIntegrationSnapshotId,
      );
    });

    test('publish direct is idempotent', () async {
      final snapshot = await publishedSnapshot();
      await provider.publish(snapshot);
      final loaded =
          await provider.load(snapshot.metadata.cicdIntegrationSnapshotId);
      expect(loaded!.fingerprint, snapshot.fingerprint);
    });

    test('latest returns most recent snapshot for project', () async {
      final snapshot = await publishedSnapshot();
      final latest = await provider.latest(
        projectId: snapshot.metadata.projectId,
        releaseId: snapshot.metadata.releaseId,
      );
      expect(
        latest?.metadata.cicdIntegrationSnapshotId,
        snapshot.metadata.cicdIntegrationSnapshotId,
      );
    });

    test('query filters by projectId', () async {
      final snapshot = await publishedSnapshot();
      final results = await provider.query(
        CicdIntegrationQuery(projectId: snapshot.metadata.projectId),
      );
      expect(results, isNotEmpty);
      expect(
        results
            .every((s) => s.metadata.projectId == snapshot.metadata.projectId),
        isTrue,
      );
    });

    test('invalidate removes snapshot from load', () async {
      final snapshot = await publishedSnapshot();
      await provider.invalidate(snapshot.metadata.cicdIntegrationSnapshotId);
      expect(
        await provider.load(snapshot.metadata.cicdIntegrationSnapshotId),
        isNull,
      );
    });
  });

  group('CI/CD Integration store hardening', () {
    late InMemoryCicdIntegrationStore store;

    setUp(() => store = InMemoryCicdIntegrationStore());

    test('save overwrite with identical content is no-op', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      await store.save(snapshot);
      await store.save(snapshot);
      expect(await store.count(), 1);
    });

    test('clear removes all snapshots', () async {
      await store.save((await evaluatePassingSnapshot()).snapshot!);
      await store.clear();
      expect(await store.count(), 0);
    });

    test('simulated concurrent saves are serialized and idempotent', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      await Future.wait(List.generate(10, (_) => store.save(snapshot)));
      expect(await store.count(), 1);
    });

    test('query with limit and offset', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      await store.save(snapshot);
      final page = await store.query(
        const CicdIntegrationQuery(
          projectId: CicdIntegrationOperationalFixtures.projectId,
          limit: 1,
          offset: 0,
        ),
      );
      expect(page, hasLength(1));
    });
  });
}
