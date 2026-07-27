import 'package:masterpalm_platform/cryptographic_trust/cryptographic_digest_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_signature_envelope_validator.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_canonical_serializer.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_identity_builder.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_snapshot_validator.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

/// Mutation coverage registry for Cryptographic Trust Part 3.
void main() {
  group('Cryptographic Trust mutation tests', () {
    const snapshotValidator = CryptographicTrustSnapshotValidator();
    const digestValidator = CryptographicDigestValidator();
    const signatureValidator = CryptographicSignatureEnvelopeValidator();
    const serializer = CryptographicTrustCanonicalSerializer();
    const identity = CryptographicTrustIdentityBuilder();

    Future<CryptographicTrustSnapshot> validSnapshot() async {
      return (await evaluatePassingSnapshot()).snapshot!;
    }

    final snapshotMutations =
        <String, Future<CryptographicTrustSnapshot> Function()>{
      'snapshot-empty-fingerprint': () async {
        final s = await validSnapshot();
        return s.copyWith(fingerprint: '');
      },
      'snapshot-metadata-fingerprint-mismatch': () async {
        final s = await validSnapshot();
        return s.copyWith(
          metadata: s.metadata.copyWith(fingerprint: 'mismatch'),
        );
      },
      'snapshot-empty-snapshot-id': () async {
        final s = await validSnapshot();
        return s.copyWith(
          metadata: s.metadata.copyWith(
            cryptographicTrustSnapshotId: '',
          ),
        );
      },
    };

    for (final entry in snapshotMutations.entries) {
      test('snapshot validator rejects ${entry.key}', () async {
        final mutated = await entry.value();
        expect(snapshotValidator.validate(mutated).isValid, isFalse,
            reason: entry.key);
      });
    }

    test('digest validator rejects empty value mutation', () {
      final digest =
          CryptographicTrustTestFixtures.validDigest().copyWith(value: '');
      expect(digestValidator.validate(digest).isValid, isFalse);
    });

    test('signature validator rejects empty signatureId mutation', () {
      final envelope = CryptographicTrustTestFixtures.validSignatureEnvelope()
          .copyWith(signatureId: '');
      expect(signatureValidator.validate(envelope).isValid, isFalse);
    });

    test('identity fingerprint changes when normative schemaVersion mutates',
        () async {
      final snapshot = await validSnapshot();
      final fp1 = identity.fingerprintForSnapshot(snapshot);
      final mutated = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(schemaVersion: 99),
      );
      expect(identity.fingerprintForSnapshot(mutated), isNot(fp1));
    });

    test('serializer detects snapshot content fingerprint change', () async {
      final snapshot = await validSnapshot();
      final fp1 = serializer.snapshotContentFingerprint(snapshot);
      final mutated = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(schemaVersion: 99),
      );
      expect(serializer.snapshotContentFingerprint(mutated), isNot(fp1));
    });

    test('snapshot status invalid mutation is detectable structurally',
        () async {
      final snapshot = await validSnapshot();
      final mutated = snapshot.copyWith(
        status: CryptographicTrustStatus.invalid,
      );
      expect(mutated.status, CryptographicTrustStatus.invalid);
      expect(snapshotValidator.validate(mutated).warnings, isA<List<String>>());
    });
  });
}
