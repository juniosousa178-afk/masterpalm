import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_attestation_models.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_key_reference.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_revocation_record.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_signature_envelope.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_signer_identity.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_transparency_log_reference.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_algorithm_descriptors.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_anchor.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_chain.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_digest.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_identity.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_policy.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_requirement.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_subject.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_verification_models.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust models', () {
    void assertJsonRoundtrip<T>({
      required String label,
      required T original,
      required T Function(Map<String, dynamic>) fromJson,
      required Map<String, dynamic> Function(T) toJson,
    }) {
      test('$label roundtrip via json', () {
        final restored = fromJson(toJson(original));
        expect(restored, equals(original));
      });
    }

    void assertCopyWithChangesField<T>({
      required String label,
      required T original,
      required T updated,
      required dynamic Function(T) readChanged,
      required dynamic expected,
    }) {
      test('$label copyWith updates changed field only', () {
        expect(readChanged(updated), expected);
        expect(updated, isNot(equals(original)));
      });
    }

    assertJsonRoundtrip(
      label: 'CryptographicDigestDescriptor',
      original: CryptographicTrustTestFixtures.validDigestDescriptor(),
      fromJson: CryptographicDigestDescriptor.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'CryptographicSignatureDescriptor',
      original: CryptographicTrustTestFixtures.validSignatureDescriptor(),
      fromJson: CryptographicSignatureDescriptor.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'CryptographicDigest',
      original: CryptographicTrustTestFixtures.validDigest(),
      fromJson: CryptographicDigest.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'CryptographicKeyReference',
      original: CryptographicTrustTestFixtures.validKeyReference(),
      fromJson: CryptographicKeyReference.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'CryptographicTrustSubject',
      original: CryptographicTrustTestFixtures.validSubject(),
      fromJson: CryptographicTrustSubject.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'CryptographicSignerIdentity',
      original: CryptographicTrustTestFixtures.validSignerIdentity(),
      fromJson: CryptographicSignerIdentity.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'CryptographicTrustAnchorReference',
      original: CryptographicTrustTestFixtures.validTrustAnchorReference(),
      fromJson: CryptographicTrustAnchorReference.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'CryptographicSignatureEnvelope',
      original: CryptographicTrustTestFixtures.validSignatureEnvelope(),
      fromJson: CryptographicSignatureEnvelope.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'CryptographicAttestationStatement',
      original: CryptographicTrustTestFixtures.validAttestationStatement(),
      fromJson: CryptographicAttestationStatement.fromJson,
      toJson: (v) => v.toJson(),
    );
    test('CryptographicTrustPolicy roundtrip via json', () {
      final policy = CryptographicTrustTestFixtures.validPolicy();
      final restored = CryptographicTrustPolicy.fromJson(policy.toJson());
      expect(restored.policyId, policy.policyId);
      expect(restored.toComparableJson(), equals(policy.toComparableJson()));
    });
    assertJsonRoundtrip(
      label: 'CryptographicVerificationResult',
      original: CryptographicTrustTestFixtures.validVerificationResult(),
      fromJson: CryptographicVerificationResult.fromJson,
      toJson: (v) => v.toJson(),
    );

    test('CryptographicTrustSnapshot roundtrip preserves comparable json', () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      final restored = CryptographicTrustSnapshot.fromJson(snapshot.toJson());
      expect(restored.fingerprint, snapshot.fingerprint);
      expect(restored.toComparableJson(), equals(snapshot.toComparableJson()));
    });

    assertCopyWithChangesField(
      label: 'CryptographicDigest',
      original: CryptographicTrustTestFixtures.validDigest(),
      updated: CryptographicTrustTestFixtures.validDigest().copyWith(
          value:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
      readChanged: (v) => v.value,
      expected:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );

    assertCopyWithChangesField(
      label: 'CryptographicTrustSubject',
      original: CryptographicTrustTestFixtures.validSubject(),
      updated: CryptographicTrustTestFixtures.validSubject()
          .copyWith(artifactType: 'container'),
      readChanged: (v) => v.artifactType,
      expected: 'container',
    );

    test('CryptographicDigest comparable json stable for json roundtrip', () {
      final a = CryptographicTrustTestFixtures.validDigest();
      final b = CryptographicDigest.fromJson(a.toJson());
      expect(a.toComparableJson(), equals(b.toComparableJson()));
    });

    test('CryptographicKeyReference usage list is immutable from json', () {
      final restored = CryptographicKeyReference.fromJson(
        CryptographicTrustTestFixtures.validKeyReference().toJson(),
      );
      expect(
        () => restored.usage.add(CryptographicKeyUsage.encrypt),
        throwsUnsupportedError,
      );
    });

    test('CryptographicDigest metadata preserved in json roundtrip', () {
      final digest = CryptographicTrustTestFixtures.validDigest();
      final restored = CryptographicDigest.fromJson(digest.toJson());
      expect(restored.metadata['projectId'],
          CryptographicTrustTestFixtures.projectId);
    });

    test(
        'CryptographicSignerIdentity displayName excluded from comparable json',
        () {
      final identity = CryptographicTrustTestFixtures.validSignerIdentity();
      expect(identity.toComparableJson().containsKey('displayName'), isFalse);
      expect(identity.toJson().containsKey('displayName'), isTrue);
    });

    test('CryptographicDigest createdAt excluded from comparable json', () {
      final digest = CryptographicTrustTestFixtures.validDigest();
      expect(digest.toComparableJson().containsKey('createdAt'), isFalse);
    });

    test(
        'CryptographicSignatureEnvelope signedAt excluded from comparable json',
        () {
      final envelope = CryptographicTrustTestFixtures.validSignatureEnvelope();
      expect(envelope.toComparableJson().containsKey('signedAt'), isFalse);
      expect(envelope.toComparableJson().containsKey('expiresAt'), isFalse);
    });

    test(
        'CryptographicTrustSnapshot metadata timestamps excluded from comparable',
        () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      final comparable = snapshot.metadata.toComparableJson();
      expect(comparable.containsKey('createdAt'), isFalse);
      expect(comparable.containsKey('fingerprint'), isFalse);
    });

    test('CryptographicTrustSourceReference metadata excluded from comparable',
        () {
      final source = CryptographicTrustTestFixtures.validSourceReference();
      expect(source.toComparableJson().containsKey('metadata'), isFalse);
      expect(source.toJson().containsKey('metadata'), isTrue);
    });

    test('CryptographicAttestationPredicate metadata excluded from comparable',
        () {
      final predicate =
          CryptographicTrustTestFixtures.validAttestationPredicate();
      expect(predicate.toComparableJson().containsKey('metadata'), isFalse);
    });

    test('CryptographicTrustChain preserves nested structure in json', () {
      final chain = CryptographicTrustTestFixtures.validTrustChain();
      final restored = CryptographicTrustChain.fromJson(chain.toJson());
      expect(restored.leafKey.keyId, chain.leafKey.keyId);
      expect(
          restored.trustAnchor.trustAnchorId, chain.trustAnchor.trustAnchorId);
      expect(restored.intermediateReferences, hasLength(1));
    });

    test('CryptographicTrustIdentity roundtrip via json', () {
      final identity = CryptographicTrustTestFixtures.validIdentity(
        fingerprint: CryptographicTrustTestFixtures.sha256Placeholder,
      );
      final restored = CryptographicTrustIdentity.fromJson(identity.toJson());
      expect(restored, equals(identity));
    });

    test('CryptographicValidationResult roundtrip via json', () {
      final result = CryptographicTrustTestFixtures.validValidationResult();
      final restored = CryptographicValidationResult.fromJson(result.toJson());
      expect(restored, equals(result));
    });

    test('CryptographicVerificationIssue roundtrip via json', () {
      const issue = CryptographicVerificationIssue(
        code: 'CT_SAMPLE',
        severity: CryptographicIssueSeverity.warning,
        path: 'sample',
        message: 'sample issue',
      );
      final restored = CryptographicVerificationIssue.fromJson(issue.toJson());
      expect(restored, equals(issue));
    });

    test('CryptographicRevocationRecord optional issuer preserved', () {
      final record = CryptographicTrustTestFixtures.validRevocationRecord();
      final restored = CryptographicRevocationRecord.fromJson(record.toJson());
      expect(restored.issuerIdentity, isNotNull);
    });

    test('CryptographicTransparencyLogReference roundtrip via json', () {
      final reference =
          CryptographicTrustTestFixtures.validTransparencyLogReference();
      final restored =
          CryptographicTransparencyLogReference.fromJson(reference.toJson());
      expect(restored, equals(reference));
    });

    test('CryptographicTrustRequirement roundtrip via json', () {
      final requirement = CryptographicTrustTestFixtures.validRequirement();
      final restored =
          CryptographicTrustRequirement.fromJson(requirement.toJson());
      expect(restored.requirementId, requirement.requirementId);
      expect(
        restored.toComparableJson(),
        equals(requirement.toComparableJson()),
      );
    });

    test(
        'CryptographicVerificationRequest requestedAt excluded from comparable',
        () {
      final request = CryptographicTrustTestFixtures.validVerificationRequest();
      expect(request.toComparableJson().containsKey('requestedAt'), isFalse);
    });
  });
}
