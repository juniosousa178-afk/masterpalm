import '../models/mes/mes_policy.dart';
import '../models/mes/mes_request.dart';
import '../models/mes/mes_snapshot.dart';

/// Public contract for official MES operations.
abstract interface class MESProvider {
  Future<MESResult> calculate(MESRequest request);

  Future<void> publish(MESSnapshot snapshot);

  Future<MESSnapshot?> load(String snapshotId);

  Future<MESSnapshot?> latest({
    required String projectId,
    int? policyVersion,
  });

  Future<MESEligibility> checkEligibility(MESRequest request);

  Future<void> invalidate(String snapshotId);

  Set<String> get supportedPolicyIds;

  MESPolicy? getPolicy(String policyId, {int? policyVersion});

  MESPolicy? getCandidatePolicy();

  MESPolicy? getActivePolicy();
}
