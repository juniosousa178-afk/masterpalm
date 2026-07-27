import '../../models/history/history_change_type.dart';
import '../../models/history/history_compatibility.dart';
import '../../models/history/history_diff.dart';
import '../report_input.dart';

/// Converts [HistoryDiff] into [HistoryDiffReportInputData].
class HistoryDiffReportSource {
  const HistoryDiffReportSource();

  HistoryDiffReportInputData fromDiff(HistoryDiff diff) {
    final highlights = diff.changes
        .where((c) => c.changeType.name != 'artifactUnchanged')
        .take(20)
        .map(
          (c) =>
              '${c.changeType.wireName}: ${c.subjectId}${c.description != null ? ' (${c.description})' : ''}',
        )
        .toList();

    return HistoryDiffReportInputData(
      fromSnapshotId: diff.fromSnapshotId,
      toSnapshotId: diff.toSnapshotId,
      compatibilityStatus: diff.compatibility.status.wireName,
      totalChanges: diff.summary.totalChanges,
      addedCount: diff.summary.addedCount,
      removedCount: diff.summary.removedCount,
      changedCount: diff.summary.changedCount,
      highlights: highlights,
    );
  }

  HistoryDiffReportInputData fromMap(Map<String, dynamic> json) {
    return fromDiff(HistoryDiff.fromJson(json));
  }
}
