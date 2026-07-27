import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_query.dart';
import 'package:test/test.dart';

import 'support/release_supply_chain_hardening_helpers.dart';
import 'support/release_supply_chain_test_fixtures.dart';

/// Records performance baselines for Sprint 05.0 Part 3.
/// Thresholds are generous to avoid CI flakiness; values logged for audit.
void main() {
  group('Release Supply Chain performance baseline', () {
    late dynamic provider;

    setUp(() {
      provider = PlatformBootstrap.forRepo(Directory.current.path)
          .releaseSupplyChain();
    });

    Future<Duration> measure(Future<void> Function() action) async {
      final sw = Stopwatch()..start();
      await action();
      sw.stop();
      return sw.elapsed;
    }

    test('evaluate baseline under 5s', () async {
      final elapsed = await measure(() async {
        await evaluatePassingSnapshot(provider: provider);
      });
      expect(elapsed.inMilliseconds, lessThan(5000));
    });

    test('publish and load baseline under 5s', () async {
      final elapsed = await measure(() async {
        final result = await evaluatePassingSnapshot(provider: provider);
        await provider.publish(result.snapshot!);
        await provider.load(result.snapshot!.metadata.supplyChainSnapshotId);
      });
      expect(elapsed.inMilliseconds, lessThan(5000));
    });

    test('query baseline under 2s after publish', () async {
      final result = await evaluatePassingSnapshot(provider: provider);
      await provider.publish(result.snapshot!);
      final elapsed = await measure(() async {
        await provider.query(
          const ReleaseSupplyChainQuery(
            projectId: ReleaseSupplyChainTestFixtures.projectId,
          ),
        );
      });
      expect(elapsed.inMilliseconds, lessThan(2000));
    });

    test('replay 10 evaluations baseline under 10s', () async {
      final elapsed = await measure(() async {
        for (var i = 0; i < 10; i++) {
          await evaluatePassingSnapshot(provider: provider);
        }
      });
      expect(elapsed.inMilliseconds, lessThan(10000));
    });

    test('large graph fixture baseline under 3s', () async {
      final elapsed = await measure(() async {
        buildLargeSupplyChainGraph(nodeCount: 1000);
        buildLargeSbom(componentCount: 1000);
      });
      expect(elapsed.inMilliseconds, lessThan(3000));
    });
  });
}
