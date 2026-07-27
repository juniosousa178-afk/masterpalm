import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle_metadata.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_compatibility.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_bundle_validator.dart';
import 'package:test/test.dart';

import 'support/release_evidence_test_fixtures.dart';

void main() {
  const validator = ReleaseEvidenceBundleValidator();

  group('ReleaseEvidenceBundleValidator', () {
    test('valid bundle passes', () {
      final result =
          validator.validate(ReleaseEvidenceTestFixtures.validBundle());
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });

    test('missing bundleId fails', () {
      final base = ReleaseEvidenceTestFixtures.validBundle();
      final bundle = base.copyWith(
        metadata: ReleaseEvidenceBundleMetadata(
          bundleId: '',
          projectId: base.metadata.projectId,
          releaseId: base.metadata.releaseId,
          releaseVersion: base.metadata.releaseVersion,
          commitId: base.metadata.commitId,
          environment: base.metadata.environment,
          policyId: base.metadata.policyId,
          policyVersion: base.metadata.policyVersion,
          policyFingerprint: base.metadata.policyFingerprint,
          schemaVersion: base.metadata.schemaVersion,
          calculationVersion: base.metadata.calculationVersion,
          canonicalizationVersion: base.metadata.canonicalizationVersion,
          sourceSetFingerprint: base.metadata.sourceSetFingerprint,
          requestFingerprint: base.metadata.requestFingerprint,
          createdAt: base.metadata.createdAt,
          evaluatedAt: base.metadata.evaluatedAt,
          referenceTime: base.metadata.referenceTime,
          evidenceCount: base.metadata.evidenceCount,
          attestationCount: base.metadata.attestationCount,
          fingerprint: base.metadata.fingerprint,
        ),
      );
      expect(validator.validate(bundle).isValid, isFalse);
    });

    test('project mismatch fails', () {
      final base = ReleaseEvidenceTestFixtures.validBundle();
      final bundle = base.copyWith(
        subject: base.subject.copyWith(projectId: 'other-project'),
      );
      expect(validator.validate(bundle).isValid, isFalse);
    });

    test('duplicate evidence fails', () {
      final base = ReleaseEvidenceTestFixtures.validBundle();
      final evidence = [
        ...base.evidence,
        base.evidence.first,
      ];
      final bundle = base.copyWith(evidence: evidence);
      expect(validator.validate(bundle).isValid, isFalse);
    });

    test('coverage count mismatch fails', () {
      final base = ReleaseEvidenceTestFixtures.validBundle();
      final bundle = base.copyWith(
        coverage: ReleaseEvidenceTestFixtures.validCoverage(evidenceCount: 99),
      );
      expect(validator.validate(bundle).isValid, isFalse);
    });
  });
}
