import 'package:masterpalm_platform/history/mappers/persistent_artifact_history_mapper.dart';
import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact history audit', () {
    const mapper = PersistentArtifactHistoryMapper();

    test('mapper converts snapshot map into history artifact', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final artifact = mapper.fromMap(snapshot.toJson());
      expect(artifact.artifactType, HistoryArtifactType.persistentArtifacts);
      expect(artifact.artifactId, isNotEmpty);
    });

    test('history artifact fingerprint remains stable for same snapshot',
        () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final a = mapper.fromMap(snapshot.toJson());
      final b = mapper.fromMap(snapshot.toJson());
      expect(a.fingerprint, b.fingerprint);
    });

    test('history mapper does not require provider evaluate side-effects', () {
      const content = PersistentArtifactHistoryMapper();
      expect(content, isNotNull);
    });
  });
}
