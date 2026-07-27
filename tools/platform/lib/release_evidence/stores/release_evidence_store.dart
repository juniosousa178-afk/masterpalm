import '../../models/release_evidence/release_evidence_bundle.dart';
import '../../models/release_evidence/release_evidence_query.dart';

/// Persistence contract for release evidence bundles.
abstract class ReleaseEvidenceStore {
  Future<void> save(ReleaseEvidenceBundle bundle);

  Future<ReleaseEvidenceBundle?> load(String bundleId);

  Future<bool> exists(String bundleId);

  Future<ReleaseEvidenceBundle?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  });

  Future<List<ReleaseEvidenceBundle>> query(ReleaseEvidenceQuery query);

  Future<void> invalidate(String bundleId);

  Future<void> clear();

  Future<int> count();
}
