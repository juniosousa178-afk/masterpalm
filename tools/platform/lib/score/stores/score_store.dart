import '../../models/score/score_snapshot.dart';

/// Persistence contract for engineering score snapshots.
abstract interface class ScoreStore {
  Future<void> save(EngineeringScoreSnapshot snapshot);

  Future<EngineeringScoreSnapshot?> load(String snapshotId);

  Future<List<EngineeringScoreSnapshot>> listAll();

  Future<EngineeringScoreSnapshot?> latest({
    required String projectId,
    String? policyId,
  });

  Future<bool> exists(String snapshotId);

  Future<void> delete(String snapshotId);
}
