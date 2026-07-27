import 'dart:convert';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_test_fixtures.dart';

void main() {
  group('Persistent Artifact Cloud serialization', () {
    final entities = <String, dynamic>{
      'endpoint': CloudTestFixtures.endpoint(),
      'region': CloudTestFixtures.region(),
      'container': CloudTestFixtures.container(),
      'object': CloudTestFixtures.objectReference(),
      'operationRequest': CloudTestFixtures.operationRequest(),
      'operationResult': CloudTestFixtures.operationResult(),
      'backendDescriptor': CloudTestFixtures.backendDescriptor(),
      'criteria': CloudTestFixtures.promotionCriteria(),
      'decision': CloudTestFixtures.readinessDecision(),
    };

    for (final entry in entities.entries) {
      test('${entry.key} toJson keys are non-empty', () {
        final asJson =
            (entry.value as dynamic).toJson() as Map<String, dynamic>;
        expect(asJson.keys, isNotEmpty);
      });

      test('${entry.key} toComparableJson deterministic encode', () {
        final asComparable =
            (entry.value as dynamic).toComparableJson() as Map<String, dynamic>;
        expect(jsonEncode(asComparable), jsonEncode(asComparable));
      });
    }

    test('metadata key ordering is stable in comparable json', () {
      final descriptorA = CloudTestFixtures.backendDescriptor().copyWith(
        metadata: const {'b': '2', 'a': '1'},
      );
      final descriptorB = CloudTestFixtures.backendDescriptor().copyWith(
        metadata: const {'a': '1', 'b': '2'},
      );
      expect(
        jsonEncode(descriptorA.toComparableJson()),
        jsonEncode(descriptorB.toComparableJson()),
      );
    });

    test('json encode/decode roundtrip for backend descriptor', () {
      final encoded =
          jsonEncode(CloudTestFixtures.backendDescriptor().toJson());
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final restored =
          PersistentArtifactCloudBackendDescriptor.fromJson(decoded);
      expect(
        restored.toComparableJson(),
        CloudTestFixtures.backendDescriptor().toComparableJson(),
      );
    });
  });
}
