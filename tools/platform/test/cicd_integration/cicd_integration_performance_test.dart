import 'dart:io';

import 'package:masterpalm_platform/cicd_integration/cicd_integration_canonical_serializer.dart';
import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_query.dart';
import 'package:test/test.dart';

import 'support/cicd_integration_hardening_helpers.dart';
import 'support/cicd_integration_operational_fixtures.dart';

/// Records performance baselines for CI/CD Integration Part 3.
/// Thresholds are generous to avoid CI flakiness; values logged for audit.
void main() {
  group('CI/CD Integration performance baseline', () {
    late dynamic provider;

    setUp(() {
      provider =
          PlatformBootstrap.forRepo(Directory.current.path).cicdIntegration();
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
        final result = await publishPassingSnapshot(provider: provider);
        await provider
            .load(result.snapshot!.metadata.cicdIntegrationSnapshotId);
      });
      expect(elapsed.inMilliseconds, lessThan(5000));
    });

    test('query baseline under 2s after publish', () async {
      await publishPassingSnapshot(provider: provider);
      final elapsed = await measure(() async {
        await provider.query(
          const CicdIntegrationQuery(
            projectId: CicdIntegrationOperationalFixtures.projectId,
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

    test('large pipeline fixture baseline under 3s', () async {
      final elapsed = await measure(() async {
        buildLargePipelineDefinition(stageCount: 1000);
        const CicdIntegrationCanonicalSerializer();
      });
      expect(elapsed.inMilliseconds, lessThan(3000));
    });
  });
}
