import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/interfaces/release_governance_provider.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_request.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_evidence_policy_v1.dart';
import 'package:test/test.dart';

import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('ReleaseEvidenceProvider', () {
    late ReleaseEvidenceProvider evidenceProvider;
    late ReleaseGovernanceProvider governanceProvider;

    setUp(() {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      evidenceProvider = core.releaseEvidence();
      governanceProvider = core.releaseGovernance();
    });

    test('PlatformCore resolves ReleaseEvidenceProvider', () {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      expect(core.releaseEvidence(), isA<ReleaseEvidenceProvider>());
    });

    test('evaluate builds bundle from injected snapshots', () async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      expect(rgResult.snapshot, isNotNull);

      final result = await evidenceProvider.evaluate(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
      );

      expect(result.bundle, isNotNull);
      expect(result.bundle!.evidence, isNotEmpty);
      expect(result.verificationResult, isNotNull);
      expect(result.sourceResolutionSummary?.injectedSources, isNotEmpty);
    });

    test('evaluateAndPublish stores bundle idempotently', () async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );

      final request = ReleaseEvidenceTestFixtures.passingRequest(
        releaseDecisionSnapshot: rgResult.snapshot,
        publish: true,
      );

      final first = await evidenceProvider.evaluateAndPublish(request);
      expect(first.bundle, isNotNull);
      expect(
        first.publicationStatus,
        ReleaseEvidencePublicationStatus.published.wireName,
      );

      final loaded =
          await evidenceProvider.load(first.bundle!.metadata.bundleId);
      expect(loaded, isNotNull);
      expect(loaded!.fingerprint, first.bundle!.fingerprint);

      final second = await evidenceProvider.evaluateAndPublish(request);
      expect(
        second.publicationStatus,
        ReleaseEvidencePublicationStatus.skipped.wireName,
      );
      expect(
        second.bundle!.metadata.bundleId,
        first.bundle!.metadata.bundleId,
      );
    });

    test('bundle fingerprint is deterministic across evaluations', () async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final request = ReleaseEvidenceTestFixtures.passingRequest(
        releaseDecisionSnapshot: rgResult.snapshot,
      );

      final first = await evidenceProvider.evaluate(request);
      final second = await evidenceProvider.evaluate(request);

      expect(first.bundle!.fingerprint, second.bundle!.fingerprint);
    });

    test('missing policy id without registry match throws', () async {
      final request = ReleaseEvidenceRequest(
        releaseContext: ReleaseEvidenceTestFixtures.validContext(),
        evidencePolicyId: 'nonexistent-policy',
        qualityGateSnapshot:
            ReleaseEvidenceTestFixtures.passingQualityGateSnapshot(),
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
      );

      expect(
        () => evidenceProvider.evaluate(request),
        throwsA(isA<Exception>()),
      );
    });

    test('default policy resolves to release-evidence-v1', () async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );

      final result = await evidenceProvider.evaluate(
        ReleaseEvidenceRequest(
          releaseContext: ReleaseEvidenceTestFixtures.validContext(),
          qualityGateSnapshot:
              ReleaseEvidenceTestFixtures.passingQualityGateSnapshot(),
          releaseDecisionSnapshot: rgResult.snapshot,
          referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
        ),
      );

      expect(
        result.bundle?.metadata.policyId,
        ReleaseEvidencePolicyV1.policyId,
      );
    });
  });
}
