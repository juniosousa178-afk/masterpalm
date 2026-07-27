import 'package:masterpalm_platform/history/mappers/cryptographic_trust_history_mapper.dart';
import 'package:masterpalm_platform/models/history/history_artifact_type.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust history audit', () {
    const mapper = CryptographicTrustHistoryMapper();

    test('maps snapshot to history artifact with fingerprint', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final artifact = mapper.fromMap(snapshot.toJson());
      expect(artifact.artifactType, HistoryArtifactType.cryptographicTrust);
      expect(artifact.fingerprint, isNotEmpty);
      expect(
          artifact.artifactId, snapshot.metadata.cryptographicTrustSnapshotId);
    });

    test('compare detects status change', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final mutated = snapshot.copyWith(
        status: CryptographicTrustTestFixtures.validSnapshot().status,
      );
      final changes = mapper.compare(snapshot, mutated);
      expect(changes, isA<List<dynamic>>());
    });

    test('history artifact payload preserves snapshot json', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final artifact = mapper.fromMap(snapshot.toJson());
      expect(artifact.payload.data.containsKey('fingerprint'), isTrue);
    });

    test('fixture snapshot maps without evaluation', () {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      final artifact = mapper.fromMap(snapshot.toJson());
      expect(artifact.schemaVersion, snapshot.metadata.schemaVersion);
    });
  });
}
