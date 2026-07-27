import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_evidence/release_evidence_query.dart';
import '../models/release_evidence/release_evidence_request.dart';
import '../models/release_evidence/release_evidence_result.dart';

/// Public contract for release evidence collection and publication.
abstract interface class ReleaseEvidenceProvider {
  Future<ReleaseEvidenceResult> evaluate(ReleaseEvidenceRequest request);

  Future<ReleaseEvidenceResult> evaluateAndPublish(
    ReleaseEvidenceRequest request,
  );

  Future<void> publish(ReleaseEvidenceBundle bundle);

  Future<ReleaseEvidenceBundle?> load(String bundleId);

  Future<ReleaseEvidenceBundle?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  });

  Future<List<ReleaseEvidenceBundle>> query(ReleaseEvidenceQuery query);

  Future<void> invalidate(String bundleId);
}
