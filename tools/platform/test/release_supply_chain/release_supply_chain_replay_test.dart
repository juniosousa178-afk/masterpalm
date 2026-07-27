import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/interfaces/release_governance_provider.dart';
import 'package:masterpalm_platform/interfaces/release_supply_chain_provider.dart';
import 'package:masterpalm_platform/models/release_supply_chain/artifact_registry_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/compliance_models.dart';
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
  group('Release Supply Chain replay', () {
    late ReleaseSupplyChainProvider provider;
    late ReleaseGovernanceProvider governanceProvider;
    late ReleaseEvidenceProvider evidenceProvider;
    const serializer = ReleaseSupplyChainCanonicalSerializer();

    setUp(() {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      provider = core.releaseSupplyChain();
      governanceProvider = core.releaseGovernance();
      evidenceProvider = core.releaseEvidence();
    });

    Future<ReleaseSupplyChainSnapshot> evaluateOnce() async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final reResult = await evidenceProvider.evaluate(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
      );
      final result = await provider.evaluate(
        ReleaseSupplyChainTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
          releaseEvidenceBundle: reResult.bundle,
        ),
      );
      expect(result.snapshot, isNotNull);
      return result.snapshot!;
    }

    test('re-evaluate same inputs yields identical snapshot fingerprint',
        () async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final reResult = await evidenceProvider.evaluate(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
      );
      final request = ReleaseSupplyChainTestFixtures.passingRequest(
        releaseDecisionSnapshot: rgResult.snapshot,
        releaseEvidenceBundle: reResult.bundle,
      );

      final first = await provider.evaluate(request);
      final second = await provider.evaluate(request);

      expect(
        first.snapshot!.metadata.supplyChainSnapshotId,
        second.snapshot!.metadata.supplyChainSnapshotId,
      );
      expect(first.snapshot!.fingerprint, second.snapshot!.fingerprint);
    });

    test('replay preserves component fingerprints', () async {
      final first = await evaluateOnce();
      final second = await evaluateOnce();

      expect(
        second.metadata.graphFingerprint,
        first.metadata.graphFingerprint,
      );
      expect(second.metadata.sbomFingerprint, first.metadata.sbomFingerprint);
      expect(
        second.metadata.registryFingerprint,
        first.metadata.registryFingerprint,
      );
      expect(
        second.metadata.distributionFingerprint,
        first.metadata.distributionFingerprint,
      );
      expect(
        second.metadata.complianceFingerprint,
        first.metadata.complianceFingerprint,
      );
    });

    test('canonical serializer fingerprints are stable on replay', () async {
      final first = await evaluateOnce();
      final second = await evaluateOnce();

      expect(
        serializer.snapshotFingerprint(second),
        serializer.snapshotFingerprint(first),
      );
      expect(
        serializer.supplyChainFingerprint(second.supplyChain!),
        serializer.supplyChainFingerprint(first.supplyChain!),
      );
      expect(
        serializer.sbomFingerprint(second.sbom!),
        serializer.sbomFingerprint(first.sbom!),
      );
      expect(
        serializer.registryFingerprint(second.artifacts),
        serializer.registryFingerprint(first.artifacts),
      );
      expect(
        serializer.distributionFingerprint(second.distribution!),
        serializer.distributionFingerprint(first.distribution!),
      );
      expect(
        serializer.complianceFingerprint(second.compliance!),
        serializer.complianceFingerprint(first.compliance!),
      );
    });

    test('toJson/fromJson round-trip preserves snapshot identity', () async {
      final snapshot = await evaluateOnce();
      final restored = ReleaseSupplyChainSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())),
      );

      expect(
        restored.metadata.supplyChainSnapshotId,
        snapshot.metadata.supplyChainSnapshotId,
      );
      expect(restored.fingerprint, snapshot.fingerprint);
      expect(restored.artifacts.length, snapshot.artifacts.length);
    });

    test('component round-trips preserve fingerprints', () async {
      final snapshot = await evaluateOnce();

      final graph = SupplyChainRecord.fromJson(
        jsonDecode(jsonEncode(snapshot.supplyChain!.toJson())),
      );
      final sbom = SoftwareBillOfMaterials.fromJson(
        jsonDecode(jsonEncode(snapshot.sbom!.toJson())),
      );
      final artifact = ArtifactRecord.fromJson(
        jsonDecode(jsonEncode(snapshot.artifacts.first.toJson())),
      );
      final distribution = ReleaseDistribution.fromJson(
        jsonDecode(jsonEncode(snapshot.distribution!.toJson())),
      );
      final compliance = ComplianceResult.fromJson(
        jsonDecode(jsonEncode(snapshot.compliance!.toJson())),
      );

      expect(graph.fingerprint, snapshot.supplyChain!.fingerprint);
      expect(sbom.metadata.fingerprint, snapshot.sbom!.metadata.fingerprint);
      expect(artifact.metadata.fingerprint,
          snapshot.artifacts.first.metadata.fingerprint);
      expect(distribution.fingerprint, snapshot.distribution!.fingerprint);
      expect(compliance.fingerprint, snapshot.compliance!.fingerprint);
    });
  });
}
