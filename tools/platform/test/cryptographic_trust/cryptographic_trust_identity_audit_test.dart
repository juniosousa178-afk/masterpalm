import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_canonical_serializer.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_identity_builder.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust identity audit', () {
    const serializer = CryptographicTrustCanonicalSerializer();
    const identity = CryptographicTrustIdentityBuilder();

    Future<dynamic> passingSnapshot() async {
      return (await evaluatePassingSnapshot()).snapshot!;
    }

    test('snapshot fingerprint excludes snapshotId and temporal metadata',
        () async {
      final snapshot = await passingSnapshot();
      final fp1 = serializer.snapshotContentFingerprint(snapshot);
      final mutated = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(
          cryptographicTrustSnapshotId: 'different-id',
          createdAt: '2099-01-01T00:00:00.000Z',
          evaluatedAt: '2099-01-01T00:00:00.000Z',
        ),
      );
      expect(serializer.snapshotContentFingerprint(mutated), fp1);
    });

    test('snapshot fingerprint changes when normative schemaVersion changes',
        () async {
      final snapshot = await passingSnapshot();
      final fp1 = serializer.snapshotFingerprint(snapshot);
      final mutated = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(schemaVersion: 99),
      );
      expect(serializer.snapshotFingerprint(mutated), isNot(fp1));
    });

    test('cryptographicTrustId includes normative fingerprint components',
        () async {
      final snapshot = await passingSnapshot();
      final id = identity.buildCryptographicTrustIdFromSnapshot(snapshot);
      expect(id, contains(snapshot.metadata.projectId));
      expect(id, contains(snapshot.fingerprint));
    });

    test('digest fingerprint is stable for same normative content', () {
      final d = CryptographicTrustTestFixtures.validDigest();
      final fp1 = serializer.digestFingerprint(d);
      final fp2 = serializer.digestFingerprint(d);
      expect(fp1, fp2);
      expect(fp1, isNotEmpty);
    });

    test('signature comparable excludes signedAt timestamp', () {
      final envelope = CryptographicTrustTestFixtures.validSignatureEnvelope();
      expect(envelope.toComparableJson().containsKey('signedAt'), isFalse);
      expect(envelope.toJson().containsKey('signedAt'), isTrue);
    });

    test('verification result comparable excludes verifiedAt', () {
      final result = CryptographicTrustTestFixtures.validVerificationResult();
      expect(result.toComparableJson().containsKey('verifiedAt'), isFalse);
    });

    test('identity builder fingerprintForSnapshot matches serializer',
        () async {
      final snapshot = await passingSnapshot();
      expect(
        identity.fingerprintForSnapshot(snapshot),
        serializer.snapshotContentFingerprint(snapshot),
      );
    });

    test(
        'transient metadata mutation matrix does not change content fingerprint',
        () async {
      final snapshot = await passingSnapshot();
      final baseline = serializer.snapshotContentFingerprint(snapshot);
      final transientMutations = [
        snapshot.copyWith(
          metadata: snapshot.metadata.copyWith(
            cryptographicTrustSnapshotId: 'transient-id-1',
          ),
        ),
        snapshot.copyWith(
          metadata: snapshot.metadata.copyWith(
            createdAt: '2000-01-01T00:00:00.000Z',
            evaluatedAt: '2000-01-01T00:00:00.000Z',
          ),
        ),
      ];
      for (final mutated in transientMutations) {
        expect(serializer.snapshotContentFingerprint(mutated), baseline);
      }
    });

    test('normative metadata mutation matrix changes fingerprint', () async {
      final snapshot = await passingSnapshot();
      final baseline = serializer.snapshotFingerprint(snapshot);
      final normativeMutations = [
        snapshot.copyWith(status: CryptographicTrustStatus.untrusted),
        snapshot.copyWith(
          metadata: snapshot.metadata.copyWith(schemaVersion: 99),
        ),
      ];
      for (final mutated in normativeMutations) {
        expect(serializer.snapshotFingerprint(mutated), isNot(baseline));
      }
    });
  });
}
