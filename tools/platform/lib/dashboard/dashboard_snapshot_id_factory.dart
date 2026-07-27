import '../models/dashboard/dashboard_snapshot.dart';

/// Deterministic dashboard snapshot ID factory.
class DashboardSnapshotIdFactory {
  const DashboardSnapshotIdFactory();

  String create({
    required String projectId,
    required String queryFingerprint,
    required String dashboardFingerprint,
    int schemaVersion = DashboardMetadata.currentSchemaVersion,
  }) {
    return 'dashboard:$projectId:$queryFingerprint:$dashboardFingerprint:$schemaVersion';
  }
}
