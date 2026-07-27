import 'dart:convert';

import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_fingerprint.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_subject.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust serialization audit', () {
    final aggregates = <String, Map<String, dynamic> Function()>{
      'CryptographicDigest': () =>
          CryptographicTrustTestFixtures.validDigest().toJson(),
      'CryptographicTrustSubject': () =>
          CryptographicTrustTestFixtures.validSubject().toJson(),
      'CryptographicSignatureEnvelope': () =>
          CryptographicTrustTestFixtures.validSignatureEnvelope().toJson(),
      'CryptographicAttestationStatement': () =>
          CryptographicTrustTestFixtures.validAttestationStatement().toJson(),
      'CryptographicTrustSnapshot': () =>
          CryptographicTrustTestFixtures.validSnapshot().toJson(),
      'CryptographicVerificationResult': () =>
          CryptographicTrustTestFixtures.validVerificationResult().toJson(),
      'CryptographicValidationResult': () =>
          CryptographicTrustTestFixtures.validValidationResult().toJson(),
    };

    for (final entry in aggregates.entries) {
      test('${entry.key} json keys are non-empty', () {
        expect(entry.value().keys, isNotEmpty);
      });
    }

    test('fingerprint stable across repeated comparable serialization', () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      final fps = List.generate(
        5,
        (_) => CryptographicTrustFingerprint.fromComparableJson(
          snapshot.toComparableJson(),
        ),
      );
      expect(fps.toSet(), hasLength(1));
    });

    test('comparable json excludes transient digest createdAt', () {
      final digest = CryptographicTrustTestFixtures.validDigest();
      final comparable = digest.toComparableJson();
      final full = digest.toJson();
      expect(comparable.containsKey('createdAt'), isFalse);
      expect(full.containsKey('createdAt'), isTrue);
    });

    test('comparable json excludes signature envelope timestamps', () {
      final envelope = CryptographicTrustTestFixtures.validSignatureEnvelope();
      expect(envelope.toComparableJson().containsKey('signedAt'), isFalse);
      expect(envelope.toJson().containsKey('signedAt'), isTrue);
    });

    test('comparable json excludes verification result verifiedAt', () {
      final result = CryptographicTrustTestFixtures.validVerificationResult();
      expect(result.toComparableJson().containsKey('verifiedAt'), isFalse);
      expect(result.toJson().containsKey('verifiedAt'), isTrue);
    });

    test(
        'comparable json excludes snapshot metadata timestamps and fingerprint',
        () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      final comparable = snapshot.metadata.toComparableJson();
      expect(comparable.containsKey('createdAt'), isFalse);
      expect(comparable.containsKey('evaluatedAt'), isFalse);
      expect(comparable.containsKey('fingerprint'), isFalse);
      expect(comparable.containsKey('cryptographicTrustSnapshotId'), isFalse);
    });

    test('map order independence for digest metadata comparable json', () {
      final digestA = CryptographicTrustTestFixtures.validDigest().copyWith(
        metadata: const {'b': '2', 'a': '1'},
      );
      final digestB = CryptographicTrustTestFixtures.validDigest().copyWith(
        metadata: const {'a': '1', 'b': '2'},
      );
      expect(
        jsonEncode(digestA.toComparableJson()),
        jsonEncode(digestB.toComparableJson()),
      );
    });

    test('map order independence for attestation predicate claims', () {
      final predicateA =
          CryptographicTrustTestFixtures.validAttestationPredicate().copyWith(
        claims: const {'z': 'last', 'a': 'first'},
      );
      final predicateB =
          CryptographicTrustTestFixtures.validAttestationPredicate().copyWith(
        claims: const {'a': 'first', 'z': 'last'},
      );
      expect(
        jsonEncode(predicateA.toComparableJson()),
        jsonEncode(predicateB.toComparableJson()),
      );
    });

    test('snapshot comparable json sorts subjects by subjectId', () {
      final subjectA = CryptographicTrustTestFixtures.validSubject();
      final subjectB = subjectA.copyWith(subjectId: 'subject-art-000');
      final snapshot = CryptographicTrustTestFixtures.validSnapshot().copyWith(
        subjects: [subjectA, subjectB],
      );
      final comparableSubjects =
          snapshot.toComparableJson()['subjects'] as List<dynamic>;
      expect(
        comparableSubjects.first['subjectId'],
        'subject-art-000',
      );
    });

    test('validation result comparable json sorts issues by code', () {
      final result = CryptographicValidationResult(
        isValid: false,
        issues: const [
          CryptographicValidationIssue(
            code: 'CT_Z',
            path: 'z',
            severity: CryptographicIssueSeverity.warning,
            message: 'z',
          ),
          CryptographicValidationIssue(
            code: 'CT_A',
            path: 'a',
            severity: CryptographicIssueSeverity.warning,
            message: 'a',
          ),
        ],
      );
      final comparableIssues =
          result.toComparableJson()['issues'] as List<dynamic>;
      expect(comparableIssues.first['code'], 'CT_A');
    });

    test('json roundtrip preserves nested subject digest', () {
      final subject = CryptographicTrustTestFixtures.validSubject();
      final restored = CryptographicTrustSubject.fromJson(subject.toJson());
      expect(restored.digest?.subjectId, subject.digest?.subjectId);
    });

    test('json encode/decode roundtrip for snapshot is stable', () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      final encoded = jsonEncode(snapshot.toJson());
      final decoded = CryptographicTrustSnapshot.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(decoded.fingerprint, snapshot.fingerprint);
      expect(decoded.subjects.length, snapshot.subjects.length);
    });
  });
}
