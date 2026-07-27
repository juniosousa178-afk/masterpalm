import '../../models/mes/mes_snapshot.dart';

/// Persistence contract for MES snapshots.
abstract class MESStore {
  Future<void> save(MESSnapshot snapshot);

  Future<MESSnapshot?> load(String snapshotId);

  Future<List<MESSnapshot>> listAll();

  Future<MESSnapshot?> latest({
    required String projectId,
    int? policyVersion,
  });

  Future<bool> exists(String snapshotId);

  Future<void> delete(String snapshotId);
}
