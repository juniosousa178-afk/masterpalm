import '../models/quality_gate/quality_gate_query.dart';
import '../models/quality_gate/quality_gate_request.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';

/// Public contract for quality gate evaluation and publication.
abstract interface class QualityGateProvider {
  Future<QualityGateResult> evaluate(QualityGateRequest request);

  Future<QualityGateResult> evaluateAndPublish(QualityGateRequest request);

  Future<void> publish(QualityGateSnapshot snapshot);

  Future<QualityGateSnapshot?> load(String snapshotId);

  Future<QualityGateSnapshot?> latest({
    required String projectId,
    String? policyId,
  });

  Future<List<QualityGateSnapshot>> query(QualityGateQuery query);

  Future<void> invalidate(String snapshotId);
}
