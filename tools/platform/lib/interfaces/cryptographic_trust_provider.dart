import '../models/cryptographic_trust/cryptographic_attestation_models.dart';
import '../models/cryptographic_trust/cryptographic_key_reference.dart';
import '../models/cryptographic_trust/cryptographic_signature_envelope.dart';
import '../models/cryptographic_trust/cryptographic_trust_digest.dart';
import '../models/cryptographic_trust/cryptographic_trust_evaluation_request.dart';
import '../models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import '../models/cryptographic_trust/cryptographic_trust_query.dart';
import '../models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import '../cryptographic_trust/interfaces/cryptographic_signer.dart';

/// Public contract for cryptographic trust evaluation and publication.
///
/// Verified results do not authorize release or deployment.
abstract interface class CryptographicTrustProvider {
  Future<CryptographicTrustEvaluationResult> evaluate(
    CryptographicTrustEvaluationRequest request,
  );

  Future<CryptographicTrustEvaluationResult> evaluateAndPublish(
    CryptographicTrustEvaluationRequest request,
  );

  Future<void> publish(CryptographicTrustSnapshot snapshot);

  Future<CryptographicTrustSnapshot?> load(String snapshotId);

  Future<CryptographicTrustSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  });

  Future<List<CryptographicTrustSnapshot>> query(CryptographicTrustQuery query);

  Future<void> invalidate(String snapshotId);

  Future<CryptographicDigest?> computeDigest({
    required List<int> subjectBytes,
    required CryptographicDigest descriptor,
  });

  Future<CryptographicVerificationResult?> verifySignature({
    required CryptographicSignatureEnvelope envelope,
    required List<int> subjectBytes,
    required String projectId,
    String? releaseId,
  });

  Future<List<CryptographicAttestationVerificationResult>> verifyAttestation({
    required CryptographicAttestationStatement attestation,
    required List<CryptographicSignatureVerificationResult> signatureResults,
  });

  Future<CryptographicSigningPrimitiveResult> sign({
    required CryptographicKeyReference keyReference,
    required List<int> digestBytes,
    required CryptographicSignatureEnvelope template,
  });
}
