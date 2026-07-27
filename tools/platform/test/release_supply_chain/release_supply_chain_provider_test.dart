import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/interfaces/release_governance_provider.dart';
import 'package:masterpalm_platform/interfaces/release_supply_chain_provider.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_operational_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_request.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/supply_chain_policy_v1.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('ReleaseSupplyChainProvider', () {
    late ReleaseSupplyChainProvider supplyChainProvider;
    late ReleaseEvidenceProvider evidenceProvider;
    late ReleaseGovernanceProvider governanceProvider;

    setUp(() {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      supplyChainProvider = core.releaseSupplyChain();
      evidenceProvider = core.releaseEvidence();
      governanceProvider = core.releaseGovernance();
    });

    test('PlatformCore resolves ReleaseSupplyChainProvider', () {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      expect(core.releaseSupplyChain(), isA<ReleaseSupplyChainProvider>());
    });

    Future<void> publishEvidenceBundle() async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      await evidenceProvider.evaluateAndPublish(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
      );
    }

    test('evaluate builds snapshot from injected snapshots', () async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final reResult = await evidenceProvider.evaluate(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
      );

      final result = await supplyChainProvider.evaluate(
        ReleaseSupplyChainTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
          releaseEvidenceBundle: reResult.bundle,
        ),
      );

      expect(result.snapshot, isNotNull);
      expect(result.snapshot!.provenance, isNotNull);
      expect(result.snapshot!.supplyChain, isNotNull);
      expect(result.snapshot!.sbom, isNotNull);
      expect(result.snapshot!.compliance, isNotNull);
      expect(result.sourceResolutionSummary?.injectedSources, isNotEmpty);
    });

    test('evaluateAndPublish stores snapshot idempotently', () async {
      await publishEvidenceBundle();
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
        publish: true,
      );

      final first = await supplyChainProvider.evaluateAndPublish(request);
      expect(first.snapshot, isNotNull);
      expect(
        first.publicationStatus,
        ReleaseSupplyChainPublicationStatus.published.wireName,
      );

      final loaded = await supplyChainProvider.load(
        first.snapshot!.metadata.supplyChainSnapshotId,
      );
      expect(loaded, isNotNull);
      expect(loaded!.fingerprint, first.snapshot!.fingerprint);

      final second = await supplyChainProvider.evaluateAndPublish(request);
      expect(
        second.publicationStatus,
        ReleaseSupplyChainPublicationStatus.skipped.wireName,
      );
      expect(
        second.snapshot!.metadata.supplyChainSnapshotId,
        first.snapshot!.metadata.supplyChainSnapshotId,
      );
    });

    test('snapshot fingerprint is deterministic across evaluations', () async {
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

      final first = await supplyChainProvider.evaluate(request);
      final second = await supplyChainProvider.evaluate(request);

      expect(first.snapshot!.fingerprint, second.snapshot!.fingerprint);
    });

    test('missing policy id without registry match throws', () async {
      final request = ReleaseSupplyChainRequest(
        releaseContext: ReleaseSupplyChainTestFixtures.validContext(),
        supplyChainPolicyId: 'nonexistent-policy',
        qualityGateSnapshot:
            ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot(),
        referenceTime: ReleaseSupplyChainTestFixtures.referenceTime,
      );

      expect(
        () => supplyChainProvider.evaluate(request),
        throwsA(isA<Exception>()),
      );
    });

    test('default policy resolves to supply-chain-v1', () async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final reResult = await evidenceProvider.evaluate(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
      );

      final result = await supplyChainProvider.evaluate(
        ReleaseSupplyChainRequest(
          releaseContext: ReleaseSupplyChainTestFixtures.validContext(),
          qualityGateSnapshot:
              ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot(),
          releaseDecisionSnapshot: rgResult.snapshot,
          releaseEvidenceBundle: reResult.bundle,
          referenceTime: ReleaseSupplyChainTestFixtures.referenceTime,
        ),
      );

      expect(
        result.snapshot?.metadata.supplyChainPolicyId,
        SupplyChainPolicyV1.policyId,
      );
    });
  });
}
