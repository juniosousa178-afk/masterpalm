import 'dart:io';

import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_digest.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_fingerprint.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_chain.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust conceptual boundaries', () {
    test('domain fingerprint is not a cryptographic signature', () {
      final envelope = CryptographicTrustTestFixtures.validSignatureEnvelope();
      final domainFingerprint =
          CryptographicTrustFingerprint.fromComparableJson(
        envelope.toComparableJson(),
      );
      expect(domainFingerprint, isNot(equals(envelope.signatureValue)));
      expect(domainFingerprint, hasLength(64));
      expect(envelope.signatureValue, isNot(hasLength(64)));
    });

    test('digest presence does not imply trust level', () {
      final digest = CryptographicTrustTestFixtures.validDigest();
      expect(digest, isA<CryptographicDigest>());
      expect(digest.toJson().keys, isNot(contains('trustLevel')));
    });

    test('signature envelope presence does not imply verified status', () {
      final envelope = CryptographicTrustTestFixtures.validSignatureEnvelope();
      expect(envelope.signatureValue, isNotEmpty);
      expect(envelope.toJson().containsKey('verificationStatus'), isFalse);
      expect(envelope.toJson().containsKey('verified'), isFalse);
    });

    test('verified verification status does not authorize release', () {
      final result = CryptographicTrustTestFixtures.validVerificationResult();
      expect(result.status, CryptographicVerificationStatus.verified);
      expect(result.toJson().containsKey('releaseAuthorized'), isFalse);
      expect(result.metadata.containsKey('releaseAuthorized'), isFalse);
      expect(
        result.metadata['limitations'],
        contains('no-release-authorization'),
      );
    });

    test('attestation statement does not prove claim truth', () {
      final attestation =
          CryptographicTrustTestFixtures.validAttestationStatement();
      expect(attestation.predicate.claims, isNotEmpty);
      expect(attestation.toJson().containsKey('claimVerified'), isFalse);
      expect(attestation.toJson().containsKey('truthValue'), isFalse);
    });

    test('attestation predicate claims are data only', () {
      final predicate =
          CryptographicTrustTestFixtures.validAttestationPredicate();
      expect(predicate.claims['builder'], 'ci-pipeline');
      expect(predicate.toJson().containsKey('evaluated'), isFalse);
    });

    test('trust anchor reference does not imply valid certificate chain', () {
      final chain = CryptographicTrustTestFixtures.validTrustChain();
      expect(chain.trustAnchor.trustAnchorId, isNotEmpty);
      expect(chain.status, isNot(CryptographicTrustStatus.trusted));
      expect(chain.issues, isNotEmpty);
    });

    test('trust chain presence preserves structural issues without auto-trust',
        () {
      final chain = CryptographicTrustTestFixtures.validTrustChain();
      final restored = CryptographicTrustChain.fromJson(chain.toJson());
      expect(restored.issues, hasLength(chain.issues.length));
      expect(restored.status, CryptographicTrustStatus.provisional);
    });

    test('release governance domain remains separate from cryptographic trust',
        () {
      final releaseGovernanceDir =
          Directory(p.join('lib', 'release_governance'));
      expect(releaseGovernanceDir.existsSync(), isTrue);
      final ctReferences = releaseGovernanceDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('cryptographic_trust'))
          .toList();
      expect(ctReferences, isEmpty);
    });

    test('cryptographic trust models do not import release governance', () {
      final ctDir = Directory(p.join('lib', 'models', 'cryptographic_trust'));
      final imports = ctDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('release_governance'))
          .toList();
      expect(imports, isEmpty);
    });

    test('snapshot limitations document no release authorization', () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      expect(
        snapshot.limitations.any((l) => l.contains('no-release-authorization')),
        isTrue,
      );
      expect(
        snapshot.metadata.limitations.any(
          (l) => l.contains('no-release-authorization'),
        ),
        isTrue,
      );
    });

    test('attestation subject does not carry authorization flags', () {
      final subject = CryptographicTrustTestFixtures.validAttestationSubject();
      expect(subject.toJson().containsKey('releaseAuthorized'), isFalse);
    });
  });
}
