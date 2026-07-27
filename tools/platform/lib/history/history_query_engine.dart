import '../models/history/history_request.dart';
import '../models/history/history_snapshot.dart';

/// Applies in-memory filters to history snapshots.
class HistoryQueryEngine {
  const HistoryQueryEngine();

  List<HistorySnapshot> apply(
    List<HistorySnapshot> snapshots,
    HistoryQuery query,
  ) {
    var result = snapshots
        .where((s) => s.metadata.projectId == query.projectId)
        .toList();

    if (query.snapshotIds != null && query.snapshotIds!.isNotEmpty) {
      result = result
          .where(
              (s) => query.snapshotIds!.contains(s.metadata.historySnapshotId))
          .toList();
    }
    if (query.gitRef != null) {
      result = result.where((s) => s.metadata.gitRef == query.gitRef).toList();
    }
    if (query.branch != null) {
      result = result.where((s) => s.metadata.branch == query.branch).toList();
    }
    if (query.status != null) {
      result = result.where((s) => s.metadata.status == query.status).toList();
    }
    if (query.tags != null && query.tags!.isNotEmpty) {
      result = result
          .where((s) => query.tags!.every(s.metadata.tags.contains))
          .toList();
    }
    if (query.artifactTypes != null && query.artifactTypes!.isNotEmpty) {
      result = result
          .where(
            (s) => query.artifactTypes!.every(
              (type) => s.metadata.artifactTypes.contains(type),
            ),
          )
          .toList();
    }
    if (query.createdFrom != null) {
      result = result
          .where((s) => s.metadata.createdAt.compareTo(query.createdFrom!) >= 0)
          .toList();
    }
    if (query.createdTo != null) {
      result = result
          .where((s) => s.metadata.createdAt.compareTo(query.createdTo!) <= 0)
          .toList();
    }

    result.sort((a, b) {
      final createdCmp = a.metadata.createdAt.compareTo(b.metadata.createdAt);
      if (createdCmp != 0) {
        return query.descending ? -createdCmp : createdCmp;
      }
      final idCmp =
          a.metadata.historySnapshotId.compareTo(b.metadata.historySnapshotId);
      return query.descending ? -idCmp : idCmp;
    });

    if (query.limit != null &&
        query.limit! > 0 &&
        result.length > query.limit!) {
      result = result.take(query.limit!).toList();
    }

    return result;
  }
}
