import '../../models/history/history_snapshot.dart';

/// Persistence contract for historical snapshots.
abstract interface class HistoryStore {
  Future<void> save(HistorySnapshot snapshot);

  Future<HistorySnapshot?> load(String snapshotId);

  Future<List<HistorySnapshot>> listAll();

  Future<HistorySnapshot?> latest(String projectId);

  Future<bool> exists(String snapshotId);

  Future<void> delete(String snapshotId);
}
