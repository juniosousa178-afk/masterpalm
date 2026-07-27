import '../dashboard/dashboard_canonical_serializer.dart';
import '../dashboard/dashboard_engine.dart';
import '../dashboard/dashboard_registry.dart';
import '../dashboard/stores/dashboard_store.dart';
import '../interfaces/dashboard_provider.dart';
import '../models/dashboard/dashboard_enums.dart';
import '../models/dashboard/dashboard_request.dart';
import '../models/dashboard/dashboard_snapshot.dart';

/// Platform implementation of [DashboardProvider].
class PlatformDashboardProvider implements DashboardProvider {
  PlatformDashboardProvider({
    required DashboardEngine engine,
    required DashboardStore store,
    required DashboardRegistry registry,
    DashboardCanonicalSerializer? serializer,
  })  : _engine = engine,
        _store = store,
        _registry = registry,
        _serializer = serializer ?? const DashboardCanonicalSerializer();

  final DashboardEngine _engine;
  final DashboardStore _store;
  final DashboardRegistry _registry;
  final DashboardCanonicalSerializer _serializer;

  @override
  Set<DashboardSectionType> get supportedSections =>
      _registry.builders.map((b) => b.sectionType).toSet();

  @override
  Future<DashboardResult> build(DashboardRequest request) async {
    final result = await _engine.build(request);
    if (result.snapshot == null) return result;

    final existing =
        await _store.load(result.snapshot!.metadata.dashboardSnapshotId);
    if (existing != null) {
      final same = _serializer.canonicalizeSnapshot(existing) ==
          _serializer.canonicalizeSnapshot(result.snapshot!);
      return DashboardResult(
        status: result.status,
        snapshot: existing,
        warnings: result.warnings,
        errors: result.errors,
        idempotent: same,
      );
    }

    await _store.save(result.snapshot!);
    final saved =
        await _store.load(result.snapshot!.metadata.dashboardSnapshotId);
    return DashboardResult(
      status: result.status,
      snapshot: saved ?? result.snapshot,
      warnings: result.warnings,
      errors: result.errors,
    );
  }

  @override
  Future<void> publish(DashboardSnapshot snapshot) async {
    await _store.save(snapshot);
  }

  @override
  Future<DashboardSnapshot?> load(String snapshotId) {
    return _store.load(snapshotId);
  }

  @override
  Future<DashboardSnapshot?> latest({
    required String projectId,
    String? branch,
  }) {
    return _store.latest(projectId: projectId, branch: branch);
  }

  @override
  Future<List<DashboardSnapshot>> query(DashboardQuery query) {
    return _store.query(query);
  }

  @override
  Future<void> invalidate(String snapshotId) async {
    await _store.delete(snapshotId);
  }
}
