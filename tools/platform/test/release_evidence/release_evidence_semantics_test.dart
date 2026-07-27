import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_request.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_evidence_policy_v1.dart';
import 'package:test/test.dart';

import '../quality_gate/support/quality_gate_snapshot_fixtures.dart';
import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_evidence_test_fixtures.dart';

/// Documental semantics tests for release evidence domain invariants.
void main() {
  group('Release evidence semantics', () {
    test('bundle does not mutate quality gate snapshot', () {
      final qgSnapshot = QualityGateSnapshotFixtures.minimal();
      final request = ReleaseGovernanceRequest(
        releaseContext: ReleaseGovernanceTestFixtures.validContext(),
        qualityGateSnapshot: qgSnapshot,
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
      );
      final originalDecision = request.qualityGateSnapshot!.decision;
      final json = qgSnapshot.toJson();
      json['decision'] = 'failed';
      expect(request.qualityGateSnapshot!.decision, originalDecision);
      expect(json['decision'], 'failed');
    });

    test('bundle does not mutate release decision snapshot', () {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      final decision = bundle.releaseDecisionReference.decision;
      final json = bundle.toJson();
      (json['releaseDecisionReference'] as Map<String, dynamic>)['decision'] =
          'rejected';
      expect(bundle.releaseDecisionReference.decision, decision);
    });

    test('attestation does not mutate origin artifact fingerprint', () {
      final attestation = ReleaseEvidenceTestFixtures.validAttestation();
      final fingerprint = attestation.fingerprint;
      final json = attestation.toJson();
      json['fingerprint'] = 'mutated';
      expect(attestation.fingerprint, fingerprint);
    });

    test('attestation does not approve rejected release', () {
      expect(
        ReleaseAttestationType.releaseAuthorization,
        isNot(ReleaseAttestationType.qualityGateDecision),
      );
      expect(ReleaseGovernanceDecision.rejected.wireName, 'rejected');
    });

    test('verified does not mean release approved', () {
      expect(
        ReleaseVerificationStatus.verified,
        isNot(ReleaseGovernanceDecision.approved),
      );
      expect(
        ReleaseVerificationStatus.verified.wireName,
        isNot(ReleaseGovernanceDecision.approved.wireName),
      );
    });

    test('release approved does not mean evidence verified', () {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      expect(bundle.releaseDecisionReference.decision, 'approved');
      expect(
        ReleaseVerificationStatus.verified,
        isNot(ReleaseEvidenceResultStatus.success),
      );
    });

    test('signature present does not mean valid', () {
      expect(
        ReleaseSignatureVerificationStatus.present,
        isNot(ReleaseSignatureVerificationStatus.valid),
      );
      expect(
        ReleaseSignatureVerificationStatus.unverified.wireName,
        'unverified',
      );
    });

    test('issuer active does not mean cryptographically verified', () {
      expect(
        ReleaseIdentityStatus.structurallyValidated,
        isNot(ReleaseIdentityStatus.externallyVerified),
      );
      expect(ReleaseAttestationIssuerType.platform.wireName, 'platform');
    });

    test('authority active does not mean externally verified', () {
      expect(
        ReleaseAttestationAuthorityStatus.active,
        isNot(ReleaseIdentityStatus.externallyVerified),
      );
    });

    test('unverified is not invalid', () {
      expect(
        ReleaseVerificationStatus.unverified,
        isNot(ReleaseVerificationStatus.invalid),
      );
      expect(
        ReleaseAttestationStatus.unverified,
        isNot(ReleaseAttestationStatus.invalid),
      );
    });

    test('expired is not unavailable', () {
      expect(
        ReleaseVerificationStatus.expired,
        isNot(ReleaseVerificationStatus.unavailable),
      );
      expect(
        ReleaseEvidenceReferenceStatus.expired,
        isNot(ReleaseEvidenceReferenceStatus.unavailable),
      );
    });

    test('derived evidence remains marked', () {
      final artifact = ReleaseEvidenceTestFixtures.qualityGateArtifact();
      expect(artifact.evidenceRole, ReleaseEvidenceRole.normative);
      expect(ReleaseEvidenceRole.derived.wireName, 'derived');
    });

    test('evidence reference does not duplicate snapshot payload', () {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      final json = bundle.toJson();
      expect(json['evidence'], isA<List<dynamic>>());
      expect(json.containsKey('qualityGateSnapshot'), isFalse);
      expect(json.containsKey('releaseDecisionSnapshot'), isFalse);
    });

    test('historical evidence does not authorize current release', () {
      final policy = ReleaseEvidencePolicyV1.create();
      expect(policy.eligibilityPolicy.allowHistoricalEvaluation, isFalse);
    });

    test('retired policy only for historical replay', () {
      final policy = ReleaseEvidencePolicyV1.create();
      expect(policy.metadata.status, ReleaseEvidencePolicyStatus.candidate);
      expect(
          policy.metadata.status, isNot(ReleaseEvidencePolicyStatus.retired));
      expect(policy.metadata.status, isNot(ReleaseEvidencePolicyStatus.active));
    });
  });
}
