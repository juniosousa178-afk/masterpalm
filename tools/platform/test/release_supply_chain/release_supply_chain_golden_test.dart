import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/models/release_supply_chain/artifact_registry_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/compliance_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_distribution_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_snapshot.dart';
import 'package:masterpalm_platform/models/release_supply_chain/sbom_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/supply_chain_models.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_canonical_serializer.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('Release Supply Chain golden snapshots', () {
    late Map<String, dynamic> snapshotNormative;
    late Map<String, dynamic> graphNormative;
    late Map<String, dynamic> sbomNormative;
    late Map<String, dynamic> registryNormative;
    late Map<String, dynamic> distributionNormative;
    late Map<String, dynamic> complianceNormative;
    const serializer = ReleaseSupplyChainCanonicalSerializer();

    setUpAll(() async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final rg = await core.releaseGovernance().evaluate(
            ReleaseGovernanceTestFixtures.passingRequest(),
          );
      final re = await core.releaseEvidence().evaluate(
            ReleaseEvidenceTestFixtures.passingRequest(
              releaseDecisionSnapshot: rg.snapshot,
            ),
          );
      final result = await core.releaseSupplyChain().evaluate(
            ReleaseSupplyChainTestFixtures.passingRequest(
              releaseDecisionSnapshot: rg.snapshot,
              releaseEvidenceBundle: re.bundle,
            ),
          );
      final snapshot = result.snapshot!;
      final graph = snapshot.supplyChain!;
      final sbom = snapshot.sbom!;
      final artifact = snapshot.artifacts.first;
      final distribution = snapshot.distribution!;
      final compliance = snapshot.compliance!;

      snapshotNormative = {
        'supplyChainSnapshotId': snapshot.metadata.supplyChainSnapshotId,
        'fingerprint': snapshot.fingerprint,
        'supplyChainPolicyId': snapshot.metadata.supplyChainPolicyId,
        'supplyChainPolicyVersion': snapshot.metadata.supplyChainPolicyVersion,
        'artifactCount': snapshot.artifacts.length,
        'canonicalFingerprint': serializer.snapshotFingerprint(snapshot),
      };

      graphNormative = {
        'recordId': graph.recordId,
        'fingerprint': graph.fingerprint,
        'stageCount': graph.stages.length,
        'nodeCount': graph.nodes.length,
        'canonicalFingerprint': serializer.supplyChainFingerprint(graph),
      };

      sbomNormative = {
        'sbomId': sbom.metadata.sbomId,
        'fingerprint': sbom.metadata.fingerprint,
        'componentCount': sbom.components.length,
        'canonicalFingerprint': serializer.sbomFingerprint(sbom),
      };

      registryNormative = {
        'recordId': artifact.metadata.recordId,
        'fingerprint': artifact.metadata.fingerprint,
        'artifactId': artifact.identifier.artifactId,
        'canonicalFingerprint':
            serializer.registryFingerprint(snapshot.artifacts),
      };

      distributionNormative = {
        'distributionId': distribution.distributionId,
        'fingerprint': distribution.fingerprint,
        'targetCount': distribution.targets.length,
        'canonicalFingerprint':
            serializer.distributionFingerprint(distribution),
      };

      complianceNormative = {
        'resultId': compliance.resultId,
        'fingerprint': compliance.fingerprint,
        'status': compliance.status.wireName,
        'checkCount': compliance.checks.length,
        'canonicalFingerprint': serializer.complianceFingerprint(compliance),
      };
    });

    void assertGolden(
      String path,
      Map<String, dynamic> normative,
      List<String> keys,
    ) {
      final file = File(path);
      if (!file.existsSync()) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            '_note':
                'Intentional golden for Release Supply Chain. Update explicitly only.',
            ...normative,
          }),
        );
      }
      final golden =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final key in keys) {
        expect(normative[key], golden[key], reason: 'golden key: $key');
      }
    }

    test('passing_snapshot golden metadata is stable', () {
      assertGolden(
        'test/golden/release_supply_chain/passing_snapshot.json',
        snapshotNormative,
        [
          'supplyChainSnapshotId',
          'fingerprint',
          'supplyChainPolicyId',
          'supplyChainPolicyVersion',
          'artifactCount',
          'canonicalFingerprint',
        ],
      );
    });

    test('supply_chain_graph golden metadata is stable', () {
      assertGolden(
        'test/golden/release_supply_chain/supply_chain_graph.json',
        graphNormative,
        [
          'recordId',
          'fingerprint',
          'stageCount',
          'nodeCount',
          'canonicalFingerprint',
        ],
      );
    });

    test('sbom golden metadata is stable', () {
      assertGolden(
        'test/golden/release_supply_chain/sbom.json',
        sbomNormative,
        [
          'sbomId',
          'fingerprint',
          'componentCount',
          'canonicalFingerprint',
        ],
      );
    });

    test('artifact_registry golden metadata is stable', () {
      assertGolden(
        'test/golden/release_supply_chain/artifact_registry.json',
        registryNormative,
        [
          'recordId',
          'fingerprint',
          'artifactId',
          'canonicalFingerprint',
        ],
      );
    });

    test('distribution golden metadata is stable', () {
      assertGolden(
        'test/golden/release_supply_chain/distribution.json',
        distributionNormative,
        [
          'distributionId',
          'fingerprint',
          'targetCount',
          'canonicalFingerprint',
        ],
      );
    });

    test('compliance golden metadata is stable', () {
      assertGolden(
        'test/golden/release_supply_chain/compliance.json',
        complianceNormative,
        [
          'resultId',
          'fingerprint',
          'status',
          'checkCount',
          'canonicalFingerprint',
        ],
      );
    });

    test('snapshot json round-trip matches golden fingerprint', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final rg = await core.releaseGovernance().evaluate(
            ReleaseGovernanceTestFixtures.passingRequest(),
          );
      final re = await core.releaseEvidence().evaluate(
            ReleaseEvidenceTestFixtures.passingRequest(
              releaseDecisionSnapshot: rg.snapshot,
            ),
          );
      final result = await core.releaseSupplyChain().evaluate(
            ReleaseSupplyChainTestFixtures.passingRequest(
              releaseDecisionSnapshot: rg.snapshot,
              releaseEvidenceBundle: re.bundle,
            ),
          );
      final snapshot = result.snapshot!;
      final restored = ReleaseSupplyChainSnapshot.fromJson(snapshot.toJson());
      expect(
        serializer.snapshotFingerprint(restored),
        serializer.snapshotFingerprint(snapshot),
      );
    });

    test('graph json round-trip matches golden fingerprint', () async {
      final graph = ReleaseSupplyChainTestFixtures.validSupplyChainRecord();
      final restored = SupplyChainRecord.fromJson(graph.toJson());
      expect(
        serializer.supplyChainFingerprint(restored),
        serializer.supplyChainFingerprint(graph),
      );
    });

    test('sbom json round-trip matches golden fingerprint', () {
      final sbom = ReleaseSupplyChainTestFixtures.validSbom();
      final restored = SoftwareBillOfMaterials.fromJson(sbom.toJson());
      expect(
        serializer.sbomFingerprint(restored),
        serializer.sbomFingerprint(sbom),
      );
    });

    test('artifact json round-trip matches golden fingerprint', () {
      final artifact = ReleaseSupplyChainTestFixtures.validArtifactRecord();
      final restored = ArtifactRecord.fromJson(artifact.toJson());
      expect(
        restored.metadata.fingerprint,
        artifact.metadata.fingerprint,
      );
    });

    test('distribution json round-trip matches golden fingerprint', () {
      final distribution =
          ReleaseSupplyChainTestFixtures.validReleaseDistribution();
      final restored = ReleaseDistribution.fromJson(distribution.toJson());
      expect(
        serializer.distributionFingerprint(restored),
        serializer.distributionFingerprint(distribution),
      );
    });

    test('compliance json round-trip matches golden fingerprint', () {
      final compliance = ReleaseSupplyChainTestFixtures.validComplianceResult();
      final restored = ComplianceResult.fromJson(compliance.toJson());
      expect(
        serializer.complianceFingerprint(restored),
        serializer.complianceFingerprint(compliance),
      );
    });
  });
}
