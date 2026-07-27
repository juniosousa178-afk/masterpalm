import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/interfaces/release_governance_provider.dart';
import 'package:masterpalm_platform/interfaces/release_supply_chain_provider.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_operational_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_query.dart';
import 'package:masterpalm_platform/release_supply_chain/stores/in_memory_release_supply_chain_store.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_supply_chain_hardening_helpers.dart';
import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('Release Supply Chain provider hardening', () {
    late ReleaseSupplyChainProvider provider;
    late ReleaseGovernanceProvider governanceProvider;
    late ReleaseEvidenceProvider evidenceProvider;

    setUp(() {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      provider = core.releaseSupplyChain();
      governanceProvider = core.releaseGovernance();
      evidenceProvider = core.releaseEvidence();
    });

    Future<dynamic> publishedSnapshot() async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final reResult = await evidenceProvider.evaluate(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
      );
      final result = await provider.evaluateAndPublish(
        ReleaseSupplyChainTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
          releaseEvidenceBundle: reResult.bundle,
        ),
      );
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
      final snapshot = await publishedSnapshot();
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final reResult = await evidenceProvider.evaluate(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
      );
      final second = await provider.evaluateAndPublish(
        ReleaseSupplyChainTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
          releaseEvidenceBundle: reResult.bundle,
        ),
      );
      expect(
        second.publicationStatus,
        ReleaseSupplyChainPublicationStatus.skipped.wireName,
      );
      expect(
        second.snapshot!.metadata.supplyChainSnapshotId,
        snapshot.metadata.supplyChainSnapshotId,
      );
    });

    test('publish direct is idempotent', () async {
      final snapshot = await publishedSnapshot();
      await provider.publish(snapshot);
      final loaded =
          await provider.load(snapshot.metadata.supplyChainSnapshotId);
      expect(loaded!.fingerprint, snapshot.fingerprint);
    });

    test('latest returns most recent snapshot for project', () async {
      final snapshot = await publishedSnapshot();
      final latest = await provider.latest(
        projectId: snapshot.metadata.projectId,
        releaseId: snapshot.metadata.releaseId,
      );
      expect(
        latest?.metadata.supplyChainSnapshotId,
        snapshot.metadata.supplyChainSnapshotId,
      );
    });

    test('query filters by projectId', () async {
      final snapshot = await publishedSnapshot();
      final results = await provider.query(
        ReleaseSupplyChainQuery(projectId: snapshot.metadata.projectId),
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
      await provider.invalidate(snapshot.metadata.supplyChainSnapshotId);
      expect(
          await provider.load(snapshot.metadata.supplyChainSnapshotId), isNull);
    });
  });

  group('Release Supply Chain store hardening', () {
    late InMemoryReleaseSupplyChainStore store;

    setUp(() => store = InMemoryReleaseSupplyChainStore());

    test('save overwrite with identical content is no-op', () async {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      await store.save(snapshot);
      await store.save(snapshot);
      expect(await store.count(), 1);
    });

    test('clear removes all snapshots', () async {
      await store
          .save(ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot());
      await store.clear();
      expect(await store.count(), 0);
    });

    test('simulated concurrent saves are serialized and idempotent', () async {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      await Future.wait(List.generate(10, (_) => store.save(snapshot)));
      expect(await store.count(), 1);
    });

    test('query with limit and offset', () async {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      await store.save(snapshot);
      final page = await store.query(
        const ReleaseSupplyChainQuery(
          projectId: ReleaseSupplyChainTestFixtures.projectId,
          limit: 1,
          offset: 0,
        ),
      );
      expect(page, hasLength(1));
    });
  });
}
