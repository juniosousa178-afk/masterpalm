import 'dart:convert';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_test_fixtures.dart';

void main() {
  group('Persistent Artifact Cloud determinism', () {
    for (var i = 0; i < 20; i++) {
      test('comparable json deterministic iteration #$i', () {
        final descriptor = CloudTestFixtures.backendDescriptor().copyWith(
          metadata: {'z': '$i', 'a': '$i'},
        );
        final a = jsonEncode(descriptor.toComparableJson());
        final b = jsonEncode(descriptor.toComparableJson());
        expect(a, b);
      });
    }

    for (var i = 0; i < 10; i++) {
      test('fingerprint deterministic iteration #$i', () {
        final request = CloudTestFixtures.operationRequest().copyWith(
          requestId: 'request-$i',
        );
        final first =
            PersistentArtifactCloudFingerprint.operationRequest(request);
        final second =
            PersistentArtifactCloudFingerprint.operationRequest(request);
        expect(first, second);
      });
    }

    test('governance evaluator deterministic', () {
      final evaluator = PersistentArtifactCloudStagingGovernanceEvaluator();
      final descriptor =
          CloudTestFixtures.backendDescriptor(stagingEligible: true);
      final criteria = CloudTestFixtures.promotionCriteria();
      final a = evaluator.evaluate(descriptor: descriptor, criteria: criteria);
      final b = evaluator.evaluate(descriptor: descriptor, criteria: criteria);
      expect(a.toComparableJson(), equals(b.toComparableJson()));
    });
  });
}
