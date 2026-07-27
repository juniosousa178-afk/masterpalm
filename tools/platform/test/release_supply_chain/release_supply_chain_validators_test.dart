import 'package:masterpalm_platform/models/release_supply_chain/release_provenance_record.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_validation_result.dart';
import 'package:masterpalm_platform/release_supply_chain/artifact_registry_validator.dart';
import 'package:masterpalm_platform/release_supply_chain/compliance_validator.dart';
import 'package:masterpalm_platform/release_supply_chain/release_distribution_validator.dart';
import 'package:masterpalm_platform/release_supply_chain/release_provenance_validator.dart';
import 'package:masterpalm_platform/release_supply_chain/sbom_validator.dart';
import 'package:masterpalm_platform/release_supply_chain/supply_chain_validator.dart';
import 'package:test/test.dart';

import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('Release supply chain validators', () {
    test('provenance validator accepts valid record', () {
      final result = const ReleaseProvenanceValidator().validate(
        ReleaseSupplyChainTestFixtures.validProvenanceRecord(),
      );
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('provenance validator rejects empty fingerprint', () {
      final record = ReleaseSupplyChainTestFixtures.validProvenanceRecord();
      final mutated = record.copyWith(
        metadata: record.metadata.copyWith(fingerprint: ''),
      );
      final result = const ReleaseProvenanceValidator().validate(mutated);
      expect(result.isValid, isFalse);
      expect(result.errors, isNotEmpty);
    });

    test('provenance validator rejects artifact count mismatch', () {
      final record = ReleaseSupplyChainTestFixtures.validProvenanceRecord();
      final json = record.toJson();
      (json['metadata'] as Map<String, dynamic>)['artifactCount'] = 99;
      final mutated = ReleaseProvenanceRecord.fromJson(json);
      final result = const ReleaseProvenanceValidator().validate(mutated);
      expect(result.isValid, isFalse);
    });

    test('supply chain validator accepts valid record', () {
      final result = const SupplyChainValidator().validate(
        ReleaseSupplyChainTestFixtures.validSupplyChainRecord(),
      );
      expect(result.isValid, isTrue);
    });

    test('supply chain validator rejects missing fingerprint', () {
      final record = ReleaseSupplyChainTestFixtures.validSupplyChainRecord()
          .copyWith(fingerprint: '');
      final result = const SupplyChainValidator().validate(record);
      expect(result.isValid, isFalse);
    });

    test('sbom validator accepts valid sbom', () {
      final result = const SbomValidator().validate(
        ReleaseSupplyChainTestFixtures.validSbom(),
      );
      expect(result.isValid, isTrue);
    });

    test('sbom validator rejects component without hashes', () {
      final sbom = ReleaseSupplyChainTestFixtures.validSbom();
      final component = sbom.components.first.copyWith(hashes: []);
      final mutated = sbom.copyWith(components: [component]);
      final result = const SbomValidator().validate(mutated);
      expect(result.isValid, isFalse);
    });

    test('artifact registry validator accepts valid record', () {
      final result = const ArtifactRegistryValidator().validate(
        ReleaseSupplyChainTestFixtures.validArtifactRecord(),
      );
      expect(result.isValid, isTrue);
    });

    test('artifact registry validator rejects empty digest', () {
      final artifact = ReleaseSupplyChainTestFixtures.validArtifactRecord();
      final mutated = artifact.copyWith(
        integrity: artifact.integrity.copyWith(
          digest: artifact.integrity.digest.copyWith(value: ''),
        ),
      );
      final result = const ArtifactRegistryValidator().validate(mutated);
      expect(result.isValid, isFalse);
    });

    test('distribution validator accepts valid distribution', () {
      final result = const ReleaseDistributionValidator().validate(
        ReleaseSupplyChainTestFixtures.validReleaseDistribution(),
      );
      expect(result.isValid, isTrue);
    });

    test('distribution validator rejects disallowed channel', () {
      final dist = ReleaseSupplyChainTestFixtures.validReleaseDistribution();
      final mutated = dist.copyWith(
        channel: dist.channel.copyWith(
          channelType: ReleaseChannelType.staging,
        ),
      );
      final result = const ReleaseDistributionValidator().validate(mutated);
      expect(result.isValid, isFalse);
    });

    test('compliance validator accepts valid result', () {
      final result = const ComplianceValidator().validate(
        ReleaseSupplyChainTestFixtures.validComplianceResult(),
      );
      expect(result.isValid, isTrue);
    });

    test('compliance validator rejects nonCompliant without violations', () {
      final comp = ReleaseSupplyChainTestFixtures.validComplianceResult();
      final mutated = comp.copyWith(
        status: ComplianceStatus.nonCompliant,
        violations: const [],
      );
      final result = const ComplianceValidator().validate(mutated);
      expect(result.isValid, isFalse);
    });

    test('validation result roundtrip via json', () {
      final original = ReleaseSupplyChainValidationResult(
        isValid: false,
        errors: const ['error'],
        warnings: const ['warn'],
        limitations: const ['no-auto-scan'],
      );
      final restored = ReleaseSupplyChainValidationResult.fromJson(
        original.toJson(),
      );
      expect(restored, equals(original));
    });
  });
}
