import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_policy.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_attestation_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_evidence_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_verification_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/release_attestation_policy_validator.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_policy_validator.dart';
import 'package:masterpalm_platform/release_evidence/release_verification_policy_validator.dart';
import 'package:test/test.dart';

void main() {
  const evidenceValidator = ReleaseEvidencePolicyValidator();
  const attestationValidator = ReleaseAttestationPolicyValidator();
  const verificationValidator = ReleaseVerificationPolicyValidator();

  group('ReleaseEvidencePolicyV1', () {
    late final policy = ReleaseEvidencePolicyV1.create();

    test('policy is valid', () {
      final result = evidenceValidator.validate(policy);
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });

    test('has 22 rules with unique IDs', () {
      expect(policy.rules, hasLength(22));
      expect(policy.rules.map((r) => r.ruleId).toSet(), hasLength(22));
      expect(policy.rules.first.ruleId, 'RE001');
      expect(policy.rules.last.ruleId, 'RE022');
    });

    test('has 7 rule sets', () {
      expect(policy.ruleSets, hasLength(7));
      expect(
        policy.ruleSets.map((s) => s.ruleSetId).toSet(),
        containsAll([
          'subject-integrity',
          'technical-evidence',
          'governance-evidence',
          'provenance-integrity',
          'attestation-integrity',
          'source-consistency',
          'verification-readiness',
        ]),
      );
    });

    test('candidate status and owner', () {
      expect(policy.metadata.policyId, 'release-evidence-v1');
      expect(policy.metadata.status, ReleaseEvidencePolicyStatus.candidate);
      expect(policy.metadata.owner, 'MasterPalm Engineering Governance');
    });

    test('critical integrity rules', () {
      final re001 = policy.rules.firstWhere((r) => r.ruleId == 'RE001');
      final re002 = policy.rules.firstWhere((r) => r.ruleId == 'RE002');
      final re017 = policy.rules.firstWhere((r) => r.ruleId == 'RE017');
      expect(re001.severity, ReleaseEvidenceCollectionRuleSeverity.critical);
      expect(re002.severity, ReleaseEvidenceCollectionRuleSeverity.critical);
      expect(re017.severity, ReleaseEvidenceCollectionRuleSeverity.critical);
    });

    test('toComparableJson strips non-normative metadata', () {
      final comparable = policy.toComparableJson();
      final meta = comparable['metadata'] as Map<String, dynamic>;
      expect(meta.containsKey('createdAt'), isFalse);
      expect(meta.containsKey('fingerprint'), isFalse);
    });
  });

  group('ReleaseAttestationPolicyV1', () {
    late final policy = ReleaseAttestationPolicyV1.create();

    test('policy is valid', () {
      final result = attestationValidator.validate(policy);
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });

    test('candidate with environment requirements', () {
      expect(policy.metadata.policyId, 'release-attestation-v1');
      expect(policy.metadata.status, ReleaseEvidencePolicyStatus.candidate);
      expect(policy.requiredAttestations, isNotEmpty);
      expect(
        policy.requiredAttestations
            .where(
                (r) => r.environments.contains(ReleaseEnvironment.production))
            .length,
        greaterThan(0),
      );
    });

    test('production signature is future capability not false validation', () {
      final prodReq = policy.requiredAttestations.firstWhere(
        (r) => r.requirementId == 'prod-release-authorization',
      );
      expect(prodReq.signatureRequired, isTrue);
      expect(policy.signaturePolicy.futureCapabilityOnly, isFalse);
      expect(policy.limitations, contains('no-cryptographic-verification'));
    });
  });

  group('ReleaseVerificationPolicyV1', () {
    late final policy = ReleaseVerificationPolicyV1.create();

    test('policy is valid', () {
      final result = verificationValidator.validate(policy);
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });

    test('candidate requires fingerprints and schemas', () {
      expect(policy.metadata.policyId, 'release-verification-v1');
      expect(policy.requireFingerprint, isTrue);
      expect(policy.requireSchemaCompatibility, isTrue);
      expect(policy.supportedSchemas, isNotEmpty);
    });

    test('production strict cannot be fully verified with unverified signature',
        () {
      final strict = ReleaseVerificationPolicyV1.createProductionStrict();
      expect(strict.requireSignature, isTrue);
      expect(strict.allowUnverifiedSignature, isTrue);
      expect(strict.allowPartialVerification, isFalse);
      expect(
        strict.limitations,
        contains(
            'production-signature-required-but-not-cryptographically-verified'),
      );
    });
  });
}
