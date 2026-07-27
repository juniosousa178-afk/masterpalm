import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_query.dart';
import 'package:masterpalm_platform/release_evidence/stores/in_memory_release_evidence_store.dart';
import 'package:test/test.dart';

import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_evidence_hardening_helpers.dart';
import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('Release Evidence provider hardening', () {
    late ReleaseEvidenceProvider provider;

    setUp(() {
      provider =
          PlatformBootstrap.forRepo(Directory.current.path).releaseEvidence();
    });

    Future<dynamic> publishedBundle() async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final rg = await core.releaseGovernance().evaluate(
            ReleaseGovernanceTestFixtures.passingRequest(),
          );
      final result = await provider.evaluateAndPublish(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rg.snapshot,
        ),
      );
      return result.bundle!;
    }

    test('evaluate is idempotent across 5 repetitions', () async {
      final fingerprints = <String>{};
      for (var i = 0; i < 5; i++) {
        final result = await evaluatePassingBundle(provider: provider);
        fingerprints.add(result.bundle!.fingerprint);
      }
      expect(fingerprints, hasLength(1));
    });

    test('evaluateAndPublish is idempotent on second publish', () async {
      final bundle = await publishedBundle();
      final second = await provider.evaluateAndPublish(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: (await PlatformBootstrap.forRepo(
            Directory.current.path,
          ).releaseGovernance().evaluate(
                    ReleaseGovernanceTestFixtures.passingRequest(),
                  ))
              .snapshot,
        ),
      );
      expect(
        second.publicationStatus,
        ReleaseEvidencePublicationStatus.skipped.wireName,
      );
      expect(second.bundle!.metadata.bundleId, bundle.metadata.bundleId);
    });

    test('publish direct is idempotent', () async {
      final bundle = await publishedBundle();
      await provider.publish(bundle);
      final loaded = await provider.load(bundle.metadata.bundleId);
      expect(loaded!.fingerprint, bundle.fingerprint);
    });

    test('latest returns most recent bundle for project', () async {
      final bundle = await publishedBundle();
      final latest = await provider.latest(
        projectId: bundle.metadata.projectId,
        releaseId: bundle.metadata.releaseId,
      );
      expect(latest?.metadata.bundleId, bundle.metadata.bundleId);
    });

    test('query filters by projectId', () async {
      final bundle = await publishedBundle();
      final results = await provider.query(
        ReleaseEvidenceQuery(projectId: bundle.metadata.projectId),
      );
      expect(results, isNotEmpty);
      expect(
          results
              .every((b) => b.metadata.projectId == bundle.metadata.projectId),
          isTrue);
    });

    test('invalidate removes bundle from load', () async {
      final bundle = await publishedBundle();
      await provider.invalidate(bundle.metadata.bundleId);
      expect(await provider.load(bundle.metadata.bundleId), isNull);
    });
  });

  group('Release Evidence store hardening', () {
    late InMemoryReleaseEvidenceStore store;

    setUp(() => store = InMemoryReleaseEvidenceStore());

    test('save overwrite with identical content is no-op', () async {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      await store.save(bundle);
      await store.save(bundle);
      expect(await store.count(), 1);
    });

    test('clear removes all bundles', () async {
      await store.save(ReleaseEvidenceTestFixtures.validBundle());
      await store.clear();
      expect(await store.count(), 0);
    });

    test('simulated concurrent saves are serialized and idempotent', () async {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      await Future.wait(List.generate(10, (_) => store.save(bundle)));
      expect(await store.count(), 1);
    });

    test('query with limit and offset', () async {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      await store.save(bundle);
      final page = await store.query(
        ReleaseEvidenceQuery(
          projectId: bundle.metadata.projectId,
          limit: 1,
          offset: 0,
        ),
      );
      expect(page, hasLength(1));
    });
  });
}
