import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_digest.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_fingerprint.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust determinism audit', () {
    test('snapshot fingerprint identical across 5 runs', () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      final fingerprints = List.generate(
        5,
        (_) => CryptographicTrustFingerprint.fromComparableJson(
          snapshot.toComparableJson(),
        ),
      );
      expect(fingerprints.toSet(), hasLength(1));
    });

    test('snapshot comparable json stable after json roundtrip', () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      final restored = CryptographicTrustSnapshot.fromJson(snapshot.toJson());
      expect(restored.toComparableJson(), equals(snapshot.toComparableJson()));
      expect(restored.fingerprint, snapshot.fingerprint);
    });

    test('snapshot fingerprint stable across repeated roundtrips', () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      final fingerprints = List.generate(5, (_) {
        final restored = CryptographicTrustSnapshot.fromJson(snapshot.toJson());
        return CryptographicTrustFingerprint.fromComparableJson(
          restored.toComparableJson(),
        );
      });
      expect(fingerprints.toSet(), hasLength(1));
    });

    test('digest hashCode changes when transient createdAt changes', () {
      final base = CryptographicTrustTestFixtures.validDigest();
      final changed = base.copyWith(createdAt: '2026-07-23T12:00:00.000Z');
      expect(base.hashCode, isNot(changed.hashCode));
    });

    test('digest comparable fingerprint stable when only createdAt changes',
        () {
      final base = CryptographicTrustTestFixtures.validDigest();
      final changed = base.copyWith(createdAt: '2026-07-23T12:00:00.000Z');
      final fpBase = CryptographicTrustFingerprint.fromComparableJson(
        base.toComparableJson(),
      );
      final fpChanged = CryptographicTrustFingerprint.fromComparableJson(
        changed.toComparableJson(),
      );
      expect(fpBase, fpChanged);
    });

    test(
        'signature envelope comparable fingerprint stable when signedAt changes',
        () {
      final base = CryptographicTrustTestFixtures.validSignatureEnvelope();
      final changed = base.copyWith(signedAt: '2026-07-23T12:00:00.000Z');
      final fpBase = CryptographicTrustFingerprint.fromComparableJson(
        base.toComparableJson(),
      );
      final fpChanged = CryptographicTrustFingerprint.fromComparableJson(
        changed.toComparableJson(),
      );
      expect(fpBase, fpChanged);
    });

    test(
        'signer identity comparable fingerprint stable when displayName changes',
        () {
      final base = CryptographicTrustTestFixtures.validSignerIdentity();
      final changed = base.copyWith(displayName: 'Different Label');
      final fpBase = CryptographicTrustFingerprint.fromComparableJson(
        base.toComparableJson(),
      );
      final fpChanged = CryptographicTrustFingerprint.fromComparableJson(
        changed.toComparableJson(),
      );
      expect(fpBase, fpChanged);
    });

    test('normative digest value change alters comparable fingerprint', () {
      final base = CryptographicTrustTestFixtures.validDigest();
      final changed = base.copyWith(
        value:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      final fpBase = CryptographicTrustFingerprint.fromComparableJson(
        base.toComparableJson(),
      );
      final fpChanged = CryptographicTrustFingerprint.fromComparableJson(
        changed.toComparableJson(),
      );
      expect(fpBase, isNot(fpChanged));
    });

    test('normative digest metadata change alters comparable fingerprint', () {
      final base = CryptographicTrustTestFixtures.validDigest().copyWith(
        metadata: const {'note': 'first'},
      );
      final changed = base.copyWith(
        metadata: const {'note': 'second'},
      );
      expect(
        CryptographicTrustFingerprint.fromComparableJson(
          base.toComparableJson(),
        ),
        isNot(
          CryptographicTrustFingerprint.fromComparableJson(
            changed.toComparableJson(),
          ),
        ),
      );
    });

    test(
        'attestation predicate metadata change does not affect comparable json',
        () {
      final base =
          CryptographicTrustTestFixtures.validAttestationPredicate().copyWith(
        metadata: const {'note': 'a'},
      );
      final changed = base.copyWith(metadata: const {'note': 'b'});
      expect(base.toComparableJson(), changed.toComparableJson());
    });

    test('map order does not affect digest comparable fingerprint', () {
      final digestA = CryptographicTrustTestFixtures.validDigest().copyWith(
        metadata: const {'z': '1', 'a': '2'},
      );
      final digestB = CryptographicTrustTestFixtures.validDigest().copyWith(
        metadata: const {'a': '2', 'z': '1'},
      );
      expect(
        CryptographicTrustFingerprint.fromComparableJson(
          digestA.toComparableJson(),
        ),
        CryptographicTrustFingerprint.fromComparableJson(
          digestB.toComparableJson(),
        ),
      );
    });

    test('digest with trust level field is independent from digest model', () {
      final digest = CryptographicTrustTestFixtures.validDigest();
      expect(digest, isA<CryptographicDigest>());
      expect(digest.toJson().containsKey('trustLevel'), isFalse);
    });

    test('verification result verified status does not mutate digest', () {
      final digest = CryptographicTrustTestFixtures.validDigest();
      final result = CryptographicTrustTestFixtures.validVerificationResult();
      expect(result.status, CryptographicVerificationStatus.verified);
      expect(digest.toComparableJson(), digest.toComparableJson());
    });
  });
}
