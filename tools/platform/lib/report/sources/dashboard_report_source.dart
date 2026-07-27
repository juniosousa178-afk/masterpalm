import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../report_input.dart';

/// Converts [DashboardSnapshot] into [DashboardReportInputData].
class DashboardReportSource {
  const DashboardReportSource();

  DashboardReportInputData fromSnapshot(DashboardSnapshot snapshot) {
    final sectionSummaries = snapshot.sections
        .map(
          (s) =>
              '${s.type.wireName}: ${s.widgets.length} widgets (${s.availability.wireName})',
        )
        .toList();

    final sourceSummaries = snapshot.sourceReferences
        .map(
          (r) =>
              '${r.sourceType.wireName}:${r.artifactId} [${r.resolutionMode.wireName}]',
        )
        .toList();

    return DashboardReportInputData(
      dashboardSnapshotId: snapshot.metadata.dashboardSnapshotId,
      status: snapshot.metadata.status.wireName,
      freshness: snapshot.metadata.freshness.wireName,
      compatibility: snapshot.metadata.compatibility.wireName,
      sectionSummaries: sectionSummaries,
      sourceSummaries: sourceSummaries,
      limitations: snapshot.limitations.map((l) => l.message).toList(),
      projectBranch: snapshot.metadata.branch,
      projectGitRef: snapshot.metadata.gitRef,
    );
  }

  DashboardReportInputData fromMap(Map<String, dynamic> json) {
    return fromSnapshot(DashboardSnapshot.fromJson(json));
  }
}
