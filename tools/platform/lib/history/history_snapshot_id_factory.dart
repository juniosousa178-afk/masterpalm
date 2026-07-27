import '../models/history/history_metadata.dart';
import 'history_canonical_serializer.dart';

/// Deterministic history snapshot identity factory.
class HistorySnapshotIdFactory {
  const HistorySnapshotIdFactory({
    HistoryCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const HistoryCanonicalSerializer();

  final HistoryCanonicalSerializer _serializer;

  String create({
    required String projectId,
    required String snapshotFingerprint,
    int schemaVersion = HistoryMetadata.currentSchemaVersion,
  }) {
    return 'history:$projectId:$snapshotFingerprint:$schemaVersion';
  }

  HistoryCanonicalSerializer get serializer => _serializer;
}
