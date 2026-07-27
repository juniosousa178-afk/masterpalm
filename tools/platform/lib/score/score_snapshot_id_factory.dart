import '../models/score/score_snapshot.dart';
import 'score_canonical_serializer.dart';

/// Deterministic score snapshot identity factory.
class ScoreSnapshotIdFactory {
  const ScoreSnapshotIdFactory({ScoreCanonicalSerializer? serializer})
      : _serializer = serializer ?? const ScoreCanonicalSerializer();

  final ScoreCanonicalSerializer _serializer;

  String create({
    required String projectId,
    required String policyId,
    required int policyVersion,
    required String scoreFingerprint,
    int schemaVersion = ScoreMetadata.currentSchemaVersion,
  }) {
    return 'score:$projectId:$policyId:$policyVersion:$scoreFingerprint:$schemaVersion';
  }

  ScoreCanonicalSerializer get serializer => _serializer;
}
