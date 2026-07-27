import '../models/score/score_policy.dart';
import '../models/score/score_request.dart';
import '../models/score/score_snapshot.dart';

/// Public contract for engineering score management.
abstract interface class ScoreProvider {
  Future<ScoreResult> calculate(ScoreRequest request);

  Future<void> publish(EngineeringScoreSnapshot snapshot);

  Future<EngineeringScoreSnapshot?> load({required String snapshotId});

  Future<EngineeringScoreSnapshot?> latest({
    required String projectId,
    String? policyId,
  });

  Future<void> invalidate(String snapshotId);

  Set<String> get supportedPolicyIds;

  ScorePolicy? getPolicy(String policyId);
}
