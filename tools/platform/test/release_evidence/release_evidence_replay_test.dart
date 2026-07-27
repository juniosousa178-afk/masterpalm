import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/interfaces/release_governance_provider.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_evidence/release_verification_result.dart';
import 'package:test/test.dart';

import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('Release Evidence replay', () {
    late ReleaseEvidenceProvider provider;
    late ReleaseGovernanceProvider governanceProvider;

    setUp(() {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      provider = core.releaseEvidence();
      governanceProvider = core.releaseGovernance();
    });

    Future<ReleaseEvidenceBundle> evaluateOnce() async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final result = await provider.evaluate(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
      );
      expect(result.bundle, isNotNull);
      return result.bundle!;
    }

    test('re-evaluate same inputs yields identical bundle fingerprint',
        () async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final request = ReleaseEvidenceTestFixtures.passingRequest(
        releaseDecisionSnapshot: rgResult.snapshot,
      );

      final first = await provider.evaluate(request);
      final second = await provider.evaluate(request);

      expect(first.bundle!.metadata.bundleId, second.bundle!.metadata.bundleId);
      expect(first.bundle!.fingerprint, second.bundle!.fingerprint);
      expect(
        first.verificationResult!.fingerprint,
        second.verificationResult!.fingerprint,
      );
    });

    test('replay preserves compatibility eligibility and coverage', () async {
      final first = await evaluateOnce();
      final second = await evaluateOnce();

      expect(second.compatibility.status, first.compatibility.status);
      expect(
        second.compatibility.compatibilityFingerprint,
        first.compatibility.compatibilityFingerprint,
      );
      expect(second.eligibility.status, first.eligibility.status);
      expect(
        second.eligibility.eligibilityFingerprint,
        first.eligibility.eligibilityFingerprint,
      );
      expect(second.coverage.fingerprint, first.coverage.fingerprint);
      expect(
        second.coverage.evidenceCoveragePercentage,
        first.coverage.evidenceCoveragePercentage,
      );
    });

    test('replay preserves attestations ordering and fingerprints', () async {
      final first = await evaluateOnce();
      final second = await evaluateOnce();

      expect(second.attestations.length, first.attestations.length);
      for (var i = 0; i < first.attestations.length; i++) {
        expect(
          second.attestations[i].metadata.attestationId,
          first.attestations[i].metadata.attestationId,
        );
        expect(
          second.attestations[i].fingerprint,
          first.attestations[i].fingerprint,
        );
      }
    });

    test('toJson/fromJson round-trip preserves bundle identity', () async {
      final bundle = await evaluateOnce();
      final restored = ReleaseEvidenceBundle.fromJson(
          jsonDecode(jsonEncode(bundle.toJson())));

      expect(restored.metadata.bundleId, bundle.metadata.bundleId);
      expect(restored.fingerprint, bundle.fingerprint);
      expect(restored.evidence.length, bundle.evidence.length);
    });

    test('verification round-trip preserves fingerprint', () async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final result = await provider.evaluate(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
      );
      final verification = result.verificationResult!;
      final restored = ReleaseVerificationResult.fromJson(
        jsonDecode(jsonEncode(verification.toJson())),
      );
      expect(restored.verificationId, verification.verificationId);
      expect(restored.fingerprint, verification.fingerprint);
      expect(restored.checks.length, verification.checks.length);
    });
  });
}
