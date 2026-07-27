import 'package:masterpalm_platform/models/release_supply_chain/artifact_registry_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/compliance_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_distribution_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_provenance_record.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_operational_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_policy_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_request.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_result.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_snapshot.dart';
import 'package:masterpalm_platform/models/release_supply_chain/sbom_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/supply_chain_models.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/compliance_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/distribution_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/supply_chain_policy_v1.dart';
import 'package:test/test.dart';

import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('Release Supply Chain serialization audit', () {
    void roundTrip<T>({
      required T original,
      required Map<String, dynamic> Function(T) toJson,
      required T Function(Map<String, dynamic>) fromJson,
      void Function(T restored)? assertEqual,
    }) {
      final json = toJson(original);
      final restored = fromJson(Map<String, dynamic>.from(json));
      assertEqual?.call(restored);
    }

    test('ReleaseSupplyChainSnapshot roundtrip', () {
      roundTrip<ReleaseSupplyChainSnapshot>(
        original: ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot(),
        toJson: (s) => s.toJson(),
        fromJson: ReleaseSupplyChainSnapshot.fromJson,
        assertEqual: (r) {
          expect(
            r.metadata.supplyChainSnapshotId,
            ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot()
                .metadata
                .supplyChainSnapshotId,
          );
          expect(r.fingerprint, isNotEmpty);
        },
      );
    });

    test('ReleaseProvenanceRecord roundtrip', () {
      roundTrip<ReleaseProvenanceRecord>(
        original: ReleaseSupplyChainTestFixtures.validProvenanceRecord(),
        toJson: (p) => p.toJson(),
        fromJson: ReleaseProvenanceRecord.fromJson,
        assertEqual: (r) => expect(r.artifacts, hasLength(3)),
      );
    });

    test('SupplyChainRecord roundtrip', () {
      roundTrip<SupplyChainRecord>(
        original: ReleaseSupplyChainTestFixtures.validSupplyChainRecord(),
        toJson: (r) => r.toJson(),
        fromJson: SupplyChainRecord.fromJson,
        assertEqual: (r) => expect(r.fingerprint, isNotEmpty),
      );
    });

    test('SoftwareBillOfMaterials roundtrip', () {
      roundTrip<SoftwareBillOfMaterials>(
        original: ReleaseSupplyChainTestFixtures.validSbom(),
        toJson: (s) => s.toJson(),
        fromJson: SoftwareBillOfMaterials.fromJson,
        assertEqual: (r) => expect(r.components, hasLength(1)),
      );
    });

    test('ArtifactRecord roundtrip', () {
      roundTrip<ArtifactRecord>(
        original: ReleaseSupplyChainTestFixtures.validArtifactRecord(),
        toJson: (a) => a.toJson(),
        fromJson: ArtifactRecord.fromJson,
        assertEqual: (r) => expect(r.identifier.artifactId, 'artifact-apk-001'),
      );
    });

    test('ReleaseDistribution roundtrip', () {
      roundTrip<ReleaseDistribution>(
        original: ReleaseSupplyChainTestFixtures.validReleaseDistribution(),
        toJson: (d) => d.toJson(),
        fromJson: ReleaseDistribution.fromJson,
        assertEqual: (r) => expect(r.status, DistributionStatus.published),
      );
    });

    test('ComplianceResult roundtrip', () {
      roundTrip<ComplianceResult>(
        original: ReleaseSupplyChainTestFixtures.validComplianceResult(),
        toJson: (c) => c.toJson(),
        fromJson: ComplianceResult.fromJson,
        assertEqual: (r) => expect(r.status, ComplianceStatus.compliant),
      );
    });

    test('ReleaseSupplyChainRequest roundtrip preserves useLatest', () {
      final request =
          ReleaseSupplyChainTestFixtures.passingRequest(useLatest: true);
      final json = request.toJson();
      final restored = ReleaseSupplyChainRequest.fromJson(json);
      expect(restored.useLatest, isTrue);
      expect(
          restored.referenceTime, ReleaseSupplyChainTestFixtures.referenceTime);
    });

    test('ReleaseSupplyChainResult roundtrip', () {
      final original = ReleaseSupplyChainResult(
        status: ReleaseSupplyChainResultStatus.success,
        snapshot: ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot(),
      );
      roundTrip<ReleaseSupplyChainResult>(
        original: original,
        toJson: (r) => r.toJson(),
        fromJson: ReleaseSupplyChainResult.fromJson,
        assertEqual: (r) =>
            expect(r.status, ReleaseSupplyChainResultStatus.success),
      );
    });

    test('policies roundtrip via json', () {
      final supplyChain = SupplyChainPolicyV1.create();
      final distribution = DistributionPolicyV1.create();
      final compliance = CompliancePolicyV1.create();

      final supplyChainRestored =
          RegisteredSupplyChainPolicy.fromJson(supplyChain.toJson());
      final distributionRestored =
          RegisteredDistributionPolicy.fromJson(distribution.toJson());
      final complianceRestored =
          RegisteredCompliancePolicy.fromJson(compliance.toJson());

      expect(
        supplyChainRestored.metadata.policyId,
        supplyChain.metadata.policyId,
      );
      expect(
        distributionRestored.metadata.policyId,
        distribution.metadata.policyId,
      );
      expect(
        complianceRestored.metadata.policyId,
        compliance.metadata.policyId,
      );
    });

    test('enum wire names roundtrip', () {
      for (final status in ComplianceStatus.values) {
        expect(ComplianceStatusX.fromWireName(status.wireName), status);
      }
      for (final status in ReleaseSupplyChainResultStatus.values) {
        expect(
          ReleaseSupplyChainResultStatusX.fromWireName(status.wireName),
          status,
        );
      }
    });

    test('referenceTime uses UTC Z suffix in fixtures', () {
      expect(
          ReleaseSupplyChainTestFixtures.referenceTime.endsWith('Z'), isTrue);
    });

    test('unknown enum throws FormatException', () {
      expect(
        () => ComplianceStatusX.fromWireName('not-a-status'),
        throwsFormatException,
      );
    });
  });
}
