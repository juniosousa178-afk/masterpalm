import '../../models/quality_gate/quality_gate_query.dart';
import '../../models/quality_gate/quality_gate_snapshot.dart';

/// Persistence contract for quality gate snapshots.
abstract class QualityGateStore {
  Future<void> save(QualityGateSnapshot snapshot);

  Future<QualityGateSnapshot?> load(String snapshotId);

  Future<bool> exists(String snapshotId);

  Future<QualityGateSnapshot?> latest({
    required String projectId,
    String? policyId,
  });

  Future<List<QualityGateSnapshot>> query(QualityGateQuery query);

  Future<void> invalidate(String snapshotId);

  Future<void> clear();

  Future<int> count();
}
