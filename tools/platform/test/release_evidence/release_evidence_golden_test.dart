import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/release_governance_provider.dart';
import 'package:masterpalm_platform/models/release_evidence/release_attestation_set.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_verification_result.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_canonical_serializer.dart';
import 'package:test/test.dart';

import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('Release Evidence golden snapshots', () {
    late Map<String, dynamic> bundleNormative;
    late Map<String, dynamic> verificationNormative;
    late Map<String, dynamic> attestationSetNormative;
    const serializer = ReleaseEvidenceCanonicalSerializer();

    setUpAll(() async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final rg = await core.releaseGovernance().evaluate(
            ReleaseGovernanceTestFixtures.passingRequest(),
          );
      final result = await core.releaseEvidence().evaluate(
            ReleaseEvidenceTestFixtures.passingRequest(
              releaseDecisionSnapshot: rg.snapshot,
            ),
          );
      final bundle = result.bundle!;
      final verification = result.verificationResult!;
      final attestationSet = ReleaseEvidenceTestFixtures.validAttestationSet();

      bundleNormative = {
        'bundleId': bundle.metadata.bundleId,
        'fingerprint': bundle.fingerprint,
        'policyId': bundle.metadata.policyId,
        'policyVersion': bundle.metadata.policyVersion,
        'evidenceCount': bundle.evidence.length,
        'attestationCount': bundle.attestations.length,
        'compatibilityStatus': bundle.compatibility.status.wireName,
        'eligibilityStatus': bundle.eligibility.status.wireName,
        'canonicalFingerprint': serializer.bundleFingerprint(bundle),
      };

      verificationNormative = {
        'verificationId': verification.verificationId,
        'fingerprint': verification.fingerprint,
        'status': verification.status.wireName,
        'checkCount': verification.checks.length,
        'canonicalFingerprint':
            serializer.verificationFingerprint(verification),
      };

      attestationSetNormative = {
        'subjectId': attestationSet.subjectId,
        'fingerprint': attestationSet.fingerprint,
        'attestationCount': attestationSet.attestations.length,
        'schemaVersion': attestationSet.schemaVersion,
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
                'Intentional golden for Release Evidence. Update explicitly only.',
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

    test('passing_bundle golden metadata is stable', () {
      assertGolden(
        'test/golden/release_evidence/passing_bundle.json',
        bundleNormative,
        [
          'bundleId',
          'fingerprint',
          'policyId',
          'policyVersion',
          'evidenceCount',
          'attestationCount',
          'compatibilityStatus',
          'eligibilityStatus',
          'canonicalFingerprint',
        ],
      );
    });

    test('passing_verification golden metadata is stable', () {
      assertGolden(
        'test/golden/release_evidence/passing_verification.json',
        verificationNormative,
        [
          'verificationId',
          'fingerprint',
          'status',
          'checkCount',
          'canonicalFingerprint',
        ],
      );
    });

    test('valid_attestation_set golden metadata is stable', () {
      assertGolden(
        'test/golden/release_evidence/valid_attestation_set.json',
        attestationSetNormative,
        [
          'subjectId',
          'fingerprint',
          'attestationCount',
          'schemaVersion',
        ],
      );
    });

    test('bundle json round-trip matches golden fingerprint', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final rg = await core.releaseGovernance().evaluate(
            ReleaseGovernanceTestFixtures.passingRequest(),
          );
      final result = await core.releaseEvidence().evaluate(
            ReleaseEvidenceTestFixtures.passingRequest(
              releaseDecisionSnapshot: rg.snapshot,
            ),
          );
      final bundle = result.bundle!;
      final restored = ReleaseEvidenceBundle.fromJson(bundle.toJson());
      expect(serializer.bundleFingerprint(restored),
          serializer.bundleFingerprint(bundle));
    });

    test('verification json round-trip matches golden fingerprint', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final rg = await core.releaseGovernance().evaluate(
            ReleaseGovernanceTestFixtures.passingRequest(),
          );
      final result = await core.releaseEvidence().evaluate(
            ReleaseEvidenceTestFixtures.passingRequest(
              releaseDecisionSnapshot: rg.snapshot,
            ),
          );
      final verification = result.verificationResult!;
      final restored =
          ReleaseVerificationResult.fromJson(verification.toJson());
      expect(
        serializer.verificationFingerprint(restored),
        serializer.verificationFingerprint(verification),
      );
    });
  });
}
