import '../models/dashboard/dashboard_enums.dart';
import '../models/dashboard/dashboard_request.dart';
import '../models/dashboard/dashboard_snapshot.dart';

/// Public contract for dashboard composition and snapshot management.
abstract interface class DashboardProvider {
  Future<DashboardResult> build(DashboardRequest request);

  Future<void> publish(DashboardSnapshot snapshot);

  Future<DashboardSnapshot?> load(String snapshotId);

  Future<DashboardSnapshot?> latest({
    required String projectId,
    String? branch,
  });

  Future<List<DashboardSnapshot>> query(DashboardQuery query);

  Future<void> invalidate(String snapshotId);

  Set<DashboardSectionType> get supportedSections;
}
