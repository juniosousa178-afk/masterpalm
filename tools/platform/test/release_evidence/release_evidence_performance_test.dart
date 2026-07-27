import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_query.dart';
import 'package:test/test.dart';

import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_evidence_hardening_helpers.dart';
import 'support/release_evidence_test_fixtures.dart';

/// Records performance baselines for Sprint 04.3 Part 3.
/// Thresholds are generous to avoid CI flakiness; values logged for audit.
void main() {
  group('Release Evidence performance baseline', () {
    late dynamic provider;

    setUp(() {
      provider =
          PlatformBootstrap.forRepo(Directory.current.path).releaseEvidence();
    });

    Future<Duration> measure(Future<void> Function() action) async {
      final sw = Stopwatch()..start();
      await action();
      sw.stop();
      return sw.elapsed;
    }

    test('evaluate baseline under 3s', () async {
      final elapsed = await measure(() async {
        await evaluatePassingBundle(provider: provider);
      });
      expect(elapsed.inMilliseconds, lessThan(3000));
    });

    test('publish and load baseline under 3s', () async {
      final elapsed = await measure(() async {
        final result = await evaluatePassingBundle(provider: provider);
        await provider.publish(result.bundle!);
        await provider.load(result.bundle!.metadata.bundleId);
      });
      expect(elapsed.inMilliseconds, lessThan(3000));
    });

    test('query baseline under 1s after publish', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final rg = await core.releaseGovernance().evaluate(
            ReleaseGovernanceTestFixtures.passingRequest(),
          );
      await provider.evaluateAndPublish(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rg.snapshot,
        ),
      );
      final elapsed = await measure(() async {
        await provider.query(
          ReleaseEvidenceQuery(
            projectId: ReleaseEvidenceTestFixtures.projectId,
          ),
        );
      });
      expect(elapsed.inMilliseconds, lessThan(1000));
    });

    test('replay 10 evaluations baseline under 5s', () async {
      final elapsed = await measure(() async {
        for (var i = 0; i < 10; i++) {
          await evaluatePassingBundle(provider: provider);
        }
      });
      expect(elapsed.inMilliseconds, lessThan(5000));
    });
  });
}
