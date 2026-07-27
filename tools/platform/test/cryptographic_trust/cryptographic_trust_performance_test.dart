import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_canonical_serializer.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_query.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_operational_fixtures.dart';

/// Records performance baselines for Cryptographic Trust Part 3.
void main() {
  group('Cryptographic Trust performance baseline', () {
    late CryptographicTrustTestStack stack;

    setUp(() async {
      stack = CryptographicTrustOperationalFixtures.createTestStack();
      await stack.registerTestKeys();
    });

    Future<Duration> measure(Future<void> Function() action) async {
      final sw = Stopwatch()..start();
      await action();
      sw.stop();
      return sw.elapsed;
    }

    test('evaluate baseline under 5s', () async {
      final elapsed = await measure(() async {
        await evaluatePassingSnapshot(stack: stack);
      });
      expect(elapsed.inMilliseconds, lessThan(5000));
    });

    test('publish and load baseline under 5s', () async {
      final elapsed = await measure(() async {
        final result = await publishPassingSnapshot(stack: stack);
        await stack.provider.load(
          result.snapshot!.metadata.cryptographicTrustSnapshotId,
        );
      });
      expect(elapsed.inMilliseconds, lessThan(5000));
    });

    test('query baseline under 2s after publish', () async {
      await publishPassingSnapshot(stack: stack);
      final elapsed = await measure(() async {
        await stack.provider.query(
          const CryptographicTrustQuery(
            projectId: CryptographicTrustOperationalFixtures.projectId,
          ),
        );
      });
      expect(elapsed.inMilliseconds, lessThan(2000));
    });

    test('replay 10 evaluations baseline under 10s', () async {
      final elapsed = await measure(() async {
        for (var i = 0; i < 10; i++) {
          await evaluatePassingSnapshot(stack: stack);
        }
      });
      expect(elapsed.inMilliseconds, lessThan(10000));
    });

    test('canonical serializer baseline under 3s', () async {
      final elapsed = await measure(() async {
        const serializer = CryptographicTrustCanonicalSerializer();
        final snapshot =
            (await evaluatePassingSnapshot(stack: stack)).snapshot!;
        for (var i = 0; i < 100; i++) {
          serializer.snapshotFingerprint(snapshot);
        }
      });
      expect(elapsed.inMilliseconds, lessThan(3000));
    });
  });
}
