import '../../models/dashboard/dashboard_request.dart';
import '../../models/dashboard/dashboard_snapshot.dart';

/// Contract for dashboard snapshot persistence.
abstract class DashboardStore {
  Future<void> save(DashboardSnapshot snapshot);

  Future<DashboardSnapshot?> load(String snapshotId);

  Future<bool> exists(String snapshotId);

  Future<DashboardSnapshot?> latest({
    required String projectId,
    String? branch,
  });

  Future<List<DashboardSnapshot>> query(DashboardQuery query);

  Future<void> delete(String snapshotId);
}
