import 'package:masterpalm_platform/models/release_supply_chain/artifact_registry_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/compliance_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_distribution_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_provenance_record.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_fingerprint.dart';
import 'package:masterpalm_platform/models/release_supply_chain/sbom_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/supply_chain_models.dart';
import 'package:test/test.dart';

import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('Release supply chain models', () {
    test('provenance record roundtrip via json', () {
      final record = ReleaseSupplyChainTestFixtures.validProvenanceRecord();
      final json = record.toJson();
      final restored = ReleaseProvenanceRecord.fromJson(
        Map<String, dynamic>.from(json),
      );
      expect(restored.metadata.provenanceRecordId,
          record.metadata.provenanceRecordId);
      expect(restored.artifacts, hasLength(3));
      expect(restored.relations, hasLength(1));
      expect(restored, equals(record));
    });

    test('supply chain record roundtrip via json', () {
      final record = ReleaseSupplyChainTestFixtures.validSupplyChainRecord();
      final restored = SupplyChainRecord.fromJson(record.toJson());
      expect(restored.recordId, record.recordId);
      expect(restored.nodes, hasLength(1));
      expect(restored, equals(record));
    });

    test('sbom roundtrip via json', () {
      final sbom = ReleaseSupplyChainTestFixtures.validSbom();
      final restored = SoftwareBillOfMaterials.fromJson(sbom.toJson());
      expect(restored.metadata.sbomId, sbom.metadata.sbomId);
      expect(restored.components, hasLength(1));
      expect(restored, equals(sbom));
    });

    test('artifact record roundtrip via json', () {
      final artifact = ReleaseSupplyChainTestFixtures.validArtifactRecord();
      final restored = ArtifactRecord.fromJson(artifact.toJson());
      expect(restored.metadata.recordId, artifact.metadata.recordId);
      expect(restored, equals(artifact));
    });

    test('release distribution roundtrip via json', () {
      final dist = ReleaseSupplyChainTestFixtures.validReleaseDistribution();
      final restored = ReleaseDistribution.fromJson(dist.toJson());
      expect(restored.distributionId, dist.distributionId);
      expect(restored.targets, hasLength(1));
      expect(restored, equals(dist));
    });

    test('compliance result roundtrip via json', () {
      final result = ReleaseSupplyChainTestFixtures.validComplianceResult();
      final restored = ComplianceResult.fromJson(result.toJson());
      expect(restored.resultId, result.resultId);
      expect(restored.checks, hasLength(1));
      expect(restored, equals(result));
    });

    test('copyWith updates provenance subject releaseId', () {
      final subject = ReleaseSupplyChainTestFixtures.validProvenanceSubject();
      final updated = subject.copyWith(releaseId: 'rel-new');
      expect(updated.releaseId, 'rel-new');
      expect(subject.releaseId, ReleaseSupplyChainTestFixtures.releaseId);
    });

    test('enum wireName roundtrip', () {
      expect(
        ReleaseProvenanceStatus.complete,
        ReleaseProvenanceStatusX.fromWireName('complete'),
      );
      expect(SupplyChainStatus.active.wireName, 'active');
      expect(SbomStatus.complete.wireName, 'complete');
      expect(ArtifactStatus.available.wireName, 'available');
      expect(DistributionStatus.published.wireName, 'published');
      expect(ComplianceStatus.compliant.wireName, 'compliant');
    });

    test('unknown enum throws FormatException', () {
      expect(
        () => SupplyChainStatusX.fromWireName('not-a-status'),
        throwsFormatException,
      );
    });

    test('collections are unmodifiable in supply chain record', () {
      final record = ReleaseSupplyChainTestFixtures.validSupplyChainRecord();
      expect(
        () => (record.nodes as dynamic).add(record.nodes.first),
        throwsUnsupportedError,
      );
    });

    test('fingerprint is deterministic for comparable json', () {
      final record = ReleaseSupplyChainTestFixtures.validProvenanceRecord();
      final fp1 = ReleaseSupplyChainFingerprint.fromComparableJson(
        record.toComparableJson(),
      );
      final fp2 = ReleaseSupplyChainFingerprint.fromComparableJson(
        record.toComparableJson(),
      );
      expect(fp1, fp2);
      expect(fp1, isNotEmpty);
    });

    test('comparable json excludes transient provenance metadata fields', () {
      final record = ReleaseSupplyChainTestFixtures.validProvenanceRecord();
      final comparable = record.toComparableJson();
      final metadata = comparable['metadata'] as Map<String, dynamic>;
      expect(metadata.containsKey('provenanceRecordId'), isFalse);
      expect(metadata.containsKey('createdAt'), isFalse);
      expect(metadata.containsKey('fingerprint'), isFalse);
    });
  });
}
