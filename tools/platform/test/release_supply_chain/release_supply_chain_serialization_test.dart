import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_fingerprint.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_validation_result.dart';
import 'package:test/test.dart';

import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('Release supply chain serialization audit', () {
    final aggregates = <String, dynamic Function()>{
      'ReleaseProvenanceRecord': () =>
          ReleaseSupplyChainTestFixtures.validProvenanceRecord().toJson(),
      'SupplyChainRecord': () =>
          ReleaseSupplyChainTestFixtures.validSupplyChainRecord().toJson(),
      'SoftwareBillOfMaterials': () =>
          ReleaseSupplyChainTestFixtures.validSbom().toJson(),
      'ArtifactRecord': () =>
          ReleaseSupplyChainTestFixtures.validArtifactRecord().toJson(),
      'ReleaseDistribution': () =>
          ReleaseSupplyChainTestFixtures.validReleaseDistribution().toJson(),
      'ComplianceResult': () =>
          ReleaseSupplyChainTestFixtures.validComplianceResult().toJson(),
    };

    for (final entry in aggregates.entries) {
      test('${entry.key} json keys are non-empty', () {
        final json = entry.value() as Map<String, dynamic>;
        expect(json.keys, isNotEmpty);
      });
    }

    test('fingerprint stable across repeated comparable serialization', () {
      final record = ReleaseSupplyChainTestFixtures.validProvenanceRecord();
      final fps = List.generate(
        5,
        (_) => ReleaseSupplyChainFingerprint.fromComparableJson(
          record.toComparableJson(),
        ),
      );
      expect(fps.toSet(), hasLength(1));
    });

    test('validation issue supports equality and hashCode', () {
      const a = ReleaseSupplyChainValidationIssue(
        code: 'X',
        path: 'p',
        severity: ReleaseSupplyChainValidationSeverity.error,
        message: 'm',
      );
      const b = ReleaseSupplyChainValidationIssue(
        code: 'X',
        path: 'p',
        severity: ReleaseSupplyChainValidationSeverity.error,
        message: 'm',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
