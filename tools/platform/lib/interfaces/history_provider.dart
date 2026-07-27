import '../models/history/history_diff.dart';
import '../models/history/history_request.dart';
import '../models/history/history_snapshot.dart';

/// Public contract for historical snapshot management.
abstract interface class HistoryProvider {
  Future<HistoryResult> capture(HistoryRequest request);

  Future<void> publish(HistorySnapshot snapshot);

  Future<HistorySnapshot?> loadById(String snapshotId);

  Future<List<HistorySnapshot>> list(HistoryQuery query);

  Future<HistorySnapshot?> latest({required String projectId});

  Future<HistoryDiff> compare({
    required String fromSnapshotId,
    required String toSnapshotId,
  });

  Future<void> remove(String snapshotId);
}
