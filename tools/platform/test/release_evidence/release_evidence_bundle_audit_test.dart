import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_bundle_validator.dart';
import 'package:test/test.dart';

import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('Release Evidence bundle audit', () {
    Future<dynamic> operationalBundle() async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final rg = await core.releaseGovernance().evaluate(
            ReleaseGovernanceTestFixtures.passingRequest(),
          );
      final result = await core.releaseEvidence().evaluate(
            ReleaseEvidenceTestFixtures.passingRequest(
              releaseDecisionSnapshot: rg.snapshot,
            ),
          );
      return result.bundle!;
    }

    test('evidence is sorted by artifactId', () async {
      final bundle = await operationalBundle();
      final ids =
          bundle.evidence.map((e) => e.artifactReference.artifactId).toList();
      expect(ids, equals(ids.toList()..sort()));
    });

    test('provenance is sorted by provenanceId', () async {
      final bundle = await operationalBundle();
      final ids = bundle.provenance.map((p) => p.provenanceId).toList();
      expect(ids, equals(ids.toList()..sort()));
    });

    test('attestations sorted by attestationId', () async {
      final bundle = await operationalBundle();
      final ids =
          bundle.attestations.map((a) => a.metadata.attestationId).toList();
      expect(ids, equals(ids.toList()..sort()));
    });

    test('operational bundle passes structural validator', () async {
      final bundle = await operationalBundle();
      final validation =
          const ReleaseEvidenceBundleValidator().validate(bundle);
      expect(validation.isValid, isTrue, reason: validation.errors.join('; '));
    });

    test('bundle has required references and assessments', () async {
      final bundle = await operationalBundle();
      expect(bundle.qualityGateReference.qualityGateSnapshotId, isNotEmpty);
      expect(
        bundle.releaseDecisionReference.releaseDecisionSnapshotId,
        isNotEmpty,
      );
      expect(bundle.compatibility.status, isNotNull);
      expect(bundle.eligibility.status, isNotNull);
      expect(bundle.coverage.presentEvidenceCount, bundle.evidence.length);
      expect(
        bundle.coverage.presentAttestationCount,
        bundle.attestations.length,
      );
    });

    test('limitations include no-crypto-verification', () async {
      final bundle = await operationalBundle();
      expect(
        bundle.limitations.any(
          (l) =>
              l.code ==
              ReleaseEvidenceLimitationCode.noCryptographicVerification,
        ),
        isTrue,
      );
    });
  });
}
