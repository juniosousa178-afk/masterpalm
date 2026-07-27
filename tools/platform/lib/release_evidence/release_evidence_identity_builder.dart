import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_evidence/release_verification_result.dart';
import 'release_evidence_canonical_serializer.dart';

/// Builds deterministic release evidence bundle and verification identities.
class ReleaseEvidenceIdentityBuilder {
  const ReleaseEvidenceIdentityBuilder({
    ReleaseEvidenceCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const ReleaseEvidenceCanonicalSerializer();

  final ReleaseEvidenceCanonicalSerializer _serializer;

  String buildBundleId({
    required String projectId,
    required String releaseId,
    required String policyId,
    required int policyVersion,
    required String bundleFingerprint,
    required int schemaVersion,
  }) {
    return 'release-evidence:$projectId:$releaseId:$policyId:$policyVersion:$bundleFingerprint:$schemaVersion';
  }

  String buildBundleIdFromBundle(ReleaseEvidenceBundle bundle) {
    return buildBundleId(
      projectId: bundle.metadata.projectId,
      releaseId: bundle.metadata.releaseId,
      policyId: bundle.metadata.policyId,
      policyVersion: bundle.metadata.policyVersion,
      bundleFingerprint: bundle.fingerprint,
      schemaVersion: bundle.metadata.schemaVersion,
    );
  }

  String fingerprintForBundle(ReleaseEvidenceBundle bundle) {
    return _serializer.bundleFingerprint(bundle);
  }

  String buildVerificationId({
    required String projectId,
    required String releaseId,
    required String policyId,
    required int policyVersion,
    required String verificationFingerprint,
    required int schemaVersion,
  }) {
    return 'release-verification:$projectId:$releaseId:$policyId:$policyVersion:$verificationFingerprint:$schemaVersion';
  }

  String buildVerificationIdFromResult(ReleaseVerificationResult result) {
    return buildVerificationId(
      projectId: result.subject.projectId,
      releaseId: result.subject.releaseId ?? 'unknown',
      policyId: result.policyReference.policyId,
      policyVersion: result.policyReference.policyVersion,
      verificationFingerprint: result.fingerprint,
      schemaVersion: result.schemaVersion,
    );
  }

  String verificationFingerprintForResult(ReleaseVerificationResult result) {
    return _serializer.verificationFingerprint(result);
  }
}
