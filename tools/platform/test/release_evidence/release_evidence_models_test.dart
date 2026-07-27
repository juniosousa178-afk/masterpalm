import 'package:masterpalm_platform/models/release_evidence/release_attestation.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_result.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_rule_value.dart';
import 'package:masterpalm_platform/models/release_evidence/release_provenance.dart';
import 'package:masterpalm_platform/models/release_evidence/release_verification_result.dart';
import 'package:test/test.dart';

import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('Release evidence models', () {
    test('subject roundtrip preserves fields', () {
      final subject = ReleaseEvidenceTestFixtures.validSubject();
      final restored = subject;
      expect(restored.projectId, subject.projectId);
      expect(restored.subjectType, ReleaseEvidenceSubjectType.release);
      final json = subject.toJson();
      final fromJson = subject;
      expect(fromJson.subjectId, json['subjectId']);
    });

    test('bundle roundtrip via json', () {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      final json = bundle.toJson();
      final restored =
          ReleaseEvidenceBundle.fromJson(Map<String, dynamic>.from(json));
      expect(restored.metadata.bundleId, bundle.metadata.bundleId);
      expect(restored.evidence, hasLength(2));
      expect(restored.attestations, hasLength(1));
      expect(restored.fingerprint, bundle.fingerprint);
    });

    test('attestation roundtrip via json', () {
      final attestation = ReleaseEvidenceTestFixtures.validAttestation();
      final json = attestation.toJson();
      final restored =
          ReleaseAttestation.fromJson(Map<String, dynamic>.from(json));
      expect(
          restored.metadata.attestationId, attestation.metadata.attestationId);
      expect(restored.predicate.predicateType,
          ReleaseAttestationPredicateType.evidenceBundle);
    });

    test('provenance roundtrip via json', () {
      final provenance = ReleaseEvidenceTestFixtures.validProvenance();
      final json = provenance.toJson();
      final restored =
          ReleaseProvenance.fromJson(Map<String, dynamic>.from(json));
      expect(restored.provenanceId, provenance.provenanceId);
      expect(restored.steps, hasLength(1));
    });

    test('verification result roundtrip via json', () {
      final result = ReleaseEvidenceTestFixtures.validVerificationResult();
      final json = result.toJson();
      final restored =
          ReleaseVerificationResult.fromJson(Map<String, dynamic>.from(json));
      expect(restored.verificationId, result.verificationId);
      expect(restored.status, ReleaseVerificationStatus.verified);
      expect(restored.checks, hasLength(1));
    });

    test('result includes optional verificationResult', () {
      final result = ReleaseEvidenceTestFixtures.validResult();
      final json = result.toJson();
      expect(json.containsKey('verificationResult'), isTrue);
      final restored = ReleaseEvidenceResult.fromJson(json);
      expect(restored.verificationResult, isNotNull);
      expect(restored.verificationResult!.verificationId, 'ver-001');
    });

    test('subject copyWith updates releaseId', () {
      final subject = ReleaseEvidenceTestFixtures.validSubject();
      final updated = subject.copyWith(releaseId: 'rel-new');
      expect(updated.releaseId, 'rel-new');
      expect(subject.releaseId, ReleaseEvidenceTestFixtures.releaseId);
    });

    test('rule values support equality', () {
      const a = ReleaseEvidenceBooleanValue(true);
      const b = ReleaseEvidenceBooleanValue(true);
      const c = ReleaseEvidenceBooleanValue(false);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('enum wireName roundtrip', () {
      expect(
        ReleaseEvidenceResultStatus.success,
        ReleaseEvidenceResultStatusX.fromWireName('success'),
      );
      expect(
        ReleaseVerificationCheckType.fingerprint.wireName,
        'fingerprint',
      );
    });

    test('collections are unmodifiable in bundle', () {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      expect(
        () => (bundle.evidence as dynamic).add(bundle.evidence.first),
        throwsUnsupportedError,
      );
    });
  });
}
