import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_enums.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_fingerprint.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_infrastructure_snapshot.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_test_fixtures.dart';

void main() {
  group('Persistent Artifact determinism audit', () {
    test('snapshot fingerprint identical across 5 serialization runs', () {
      final snapshot = PersistentArtifactTestFixtures.validSnapshot();
      final fingerprints = List.generate(
        5,
        (_) => PersistentArtifactFingerprint.fromComparableJson(
          snapshot.toComparableJson(),
        ),
      );
      expect(fingerprints.toSet(), hasLength(1));
    });

    test('snapshot comparable json stable after json roundtrip', () {
      final snapshot = PersistentArtifactTestFixtures.validSnapshot();
      final restored =
          PersistentArtifactInfrastructureSnapshot.fromJson(snapshot.toJson());
      expect(restored.toComparableJson(), equals(snapshot.toComparableJson()));
    });

    test('snapshot fingerprint stable across 5 roundtrips', () {
      final snapshot = PersistentArtifactTestFixtures.validSnapshot();
      final fingerprints = List.generate(5, (_) {
        final restored = PersistentArtifactInfrastructureSnapshot.fromJson(
            snapshot.toJson());
        return PersistentArtifactFingerprint.fromComparableJson(
          restored.toComparableJson(),
        );
      });
      expect(fingerprints.toSet(), hasLength(1));
    });

    test('snapshot equality stable across 5 roundtrips', () {
      final snapshot = PersistentArtifactTestFixtures.validSnapshot();
      final equalities = List.generate(5, (_) {
        final restored = PersistentArtifactInfrastructureSnapshot.fromJson(
            snapshot.toJson());
        return restored == snapshot;
      });
      expect(equalities.every((e) => e), isTrue);
    });

    test('snapshot hashCode stable across 5 reads of identity', () {
      final identity =
          PersistentArtifactTestFixtures.validInfrastructureIdentity();
      final hashCodes = List.generate(5, (_) => identity.hashCode);
      expect(hashCodes.toSet(), hasLength(1));
    });

    test('version hashCode changes when transient createdAt changes', () {
      final base = PersistentArtifactTestFixtures.validVersion();
      final changed = base.copyWith(createdAt: '2026-07-23T12:00:00.000Z');
      expect(base.hashCode, isNot(changed.hashCode));
    });

    test('version comparable fingerprint stable when only createdAt changes',
        () {
      final base = PersistentArtifactTestFixtures.validVersion();
      final changed = base.copyWith(createdAt: '2026-07-23T12:00:00.000Z');
      final fpBase = PersistentArtifactFingerprint.fromComparableJson(
        base.toComparableJson(),
      );
      final fpChanged = PersistentArtifactFingerprint.fromComparableJson(
        changed.toComparableJson(),
      );
      expect(fpBase, fpChanged);
    });

    test('manifest comparable fingerprint stable when createdAt changes', () {
      final base = PersistentArtifactTestFixtures.validManifest();
      final changed = base.copyWith(createdAt: '2026-07-23T12:00:00.000Z');
      final fpBase = PersistentArtifactFingerprint.fromComparableJson(
        base.toComparableJson(),
      );
      final fpChanged = PersistentArtifactFingerprint.fromComparableJson(
        changed.toComparableJson(),
      );
      expect(fpBase, fpChanged);
    });

    test(
        'snapshot comparable fingerprint stable when operational timestamps change',
        () {
      final base = PersistentArtifactTestFixtures.validSnapshot();
      final changed = base.copyWith(
        createdAt: '2026-07-23T12:00:00.000Z',
        evaluatedAt: '2026-07-23T13:00:00.000Z',
        publishedAt: '2026-07-23T14:00:00.000Z',
      );
      final fpBase = PersistentArtifactFingerprint.fromComparableJson(
        base.toComparableJson(),
      );
      final fpChanged = PersistentArtifactFingerprint.fromComparableJson(
        changed.toComparableJson(),
      );
      expect(fpBase, fpChanged);
    });

    test('normative content fingerprint change alters comparable fingerprint',
        () {
      final base = PersistentArtifactTestFixtures.validContentDescriptor();
      final changed = base.copyWith(
        contentFingerprint:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      final fpBase = PersistentArtifactFingerprint.fromComparableJson(
        base.toComparableJson(),
      );
      final fpChanged = PersistentArtifactFingerprint.fromComparableJson(
        changed.toComparableJson(),
      );
      expect(fpBase, isNot(fpChanged));
    });

    test('normative metadata change alters comparable fingerprint', () {
      final base = PersistentArtifactTestFixtures.validSubject().copyWith(
        metadata: const {'note': 'first'},
      );
      final changed = base.copyWith(metadata: const {'note': 'second'});
      expect(
        PersistentArtifactFingerprint.fromComparableJson(
            base.toComparableJson()),
        isNot(
          PersistentArtifactFingerprint.fromComparableJson(
            changed.toComparableJson(),
          ),
        ),
      );
    });

    test('map order does not affect subject comparable fingerprint', () {
      final subjectA = PersistentArtifactTestFixtures.validSubject().copyWith(
        metadata: const {'z': '1', 'a': '2'},
      );
      final subjectB = PersistentArtifactTestFixtures.validSubject().copyWith(
        metadata: const {'a': '2', 'z': '1'},
      );
      expect(
        PersistentArtifactFingerprint.fromComparableJson(
          subjectA.toComparableJson(),
        ),
        PersistentArtifactFingerprint.fromComparableJson(
          subjectB.toComparableJson(),
        ),
      );
    });

    test('snapshot subjects list order does not affect comparable json', () {
      final subjectA = PersistentArtifactTestFixtures.validSubject();
      final subjectB = subjectA.copyWith(subjectId: 'subject-pa-000');
      final snapshotA = PersistentArtifactTestFixtures.validSnapshot().copyWith(
        subjects: [subjectA, subjectB],
      );
      final snapshotB = PersistentArtifactTestFixtures.validSnapshot().copyWith(
        subjects: [subjectB, subjectA],
      );
      expect(
        snapshotA.toComparableJson(),
        equals(snapshotB.toComparableJson()),
      );
    });

    test('integrity verifiedAt change does not affect comparable fingerprint',
        () {
      final base = PersistentArtifactTestFixtures.validIntegrityRecord();
      final changed = base.copyWith(verifiedAt: '2026-07-23T12:00:00.000Z');
      expect(
        PersistentArtifactFingerprint.fromComparableJson(
            base.toComparableJson()),
        PersistentArtifactFingerprint.fromComparableJson(
          changed.toComparableJson(),
        ),
      );
    });

    test(
        'publication metadata transient change does not affect comparable when absent',
        () {
      final base = PersistentArtifactTestFixtures.validPublication();
      final changed = base.copyWith(publishedAt: '2026-07-23T12:00:00.000Z');
      expect(
        PersistentArtifactFingerprint.fromComparableJson(
            base.toComparableJson()),
        PersistentArtifactFingerprint.fromComparableJson(
          changed.toComparableJson(),
        ),
      );
    });
  });
}
