import '../../interfaces/cryptographic_trust_provider.dart';
import '../../models/cryptographic_trust/cryptographic_attestation_models.dart';
import '../../models/cryptographic_trust/cryptographic_key_reference.dart';
import '../../models/cryptographic_trust/cryptographic_signature_envelope.dart';
import '../../models/cryptographic_trust/cryptographic_trust_digest.dart';
import '../../models/cryptographic_trust/cryptographic_trust_evaluation_request.dart';
import '../../models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import '../../models/cryptographic_trust/cryptographic_trust_query.dart';
import '../../models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import '../../models/cryptographic_trust/cryptographic_verification_models.dart';
import '../../models/observability/telemetry_attributes.dart';
import '../../models/observability/telemetry_enums.dart';
import '../../cryptographic_trust/interfaces/cryptographic_signer.dart';
import 'telemetry_instrumentation.dart';

/// Observable decorator for [CryptographicTrustProvider].
///
/// Emits sanitized telemetry only — no payloads, digests, signature values, or keys.
class ObservableCryptographicTrustProvider
    implements CryptographicTrustProvider {
  ObservableCryptographicTrustProvider({
    required CryptographicTrustProvider delegate,
    required TelemetryInstrumentation instrumentation,
  })  : _delegate = delegate,
        _instrumentation = instrumentation;

  final CryptographicTrustProvider _delegate;
  final TelemetryInstrumentation _instrumentation;

  @override
  Future<CryptographicTrustEvaluationResult> evaluate(
    CryptographicTrustEvaluationRequest request,
  ) {
    return _instrumentation.observe(
      component: TelemetryComponent.cryptographicTrust,
      operation: TelemetryOperation.evaluate,
      projectId: request.projectId,
      action: () => _delegate.evaluate(request),
      resultingArtifactIds: (result) {
        final id = result.snapshot?.metadata.cryptographicTrustSnapshotId;
        return id == null ? const [] : [id];
      },
    );
  }

  @override
  Future<CryptographicTrustEvaluationResult> evaluateAndPublish(
    CryptographicTrustEvaluationRequest request,
  ) {
    return _instrumentation.observe(
      component: TelemetryComponent.cryptographicTrust,
      operation: TelemetryOperation.evaluate,
      projectId: request.projectId,
      action: () => _delegate.evaluateAndPublish(request),
      resultingArtifactIds: (result) {
        final id = result.snapshot?.metadata.cryptographicTrustSnapshotId;
        return id == null ? const [] : [id];
      },
    );
  }

  @override
  Future<void> publish(CryptographicTrustSnapshot snapshot) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.cryptographicTrust,
      operation: TelemetryOperation.publish,
      projectId: snapshot.metadata.projectId,
      action: () => _delegate.publish(snapshot),
    );
  }

  @override
  Future<CryptographicTrustSnapshot?> load(String snapshotId) {
    return _instrumentation.observe(
      component: TelemetryComponent.cryptographicTrust,
      operation: TelemetryOperation.load,
      action: () => _delegate.load(snapshotId),
      resultingArtifactIds: (snapshot) {
        return snapshot == null
            ? const []
            : [snapshot.metadata.cryptographicTrustSnapshotId];
      },
    );
  }

  @override
  Future<CryptographicTrustSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) {
    return _instrumentation.observe(
      component: TelemetryComponent.cryptographicTrust,
      operation: TelemetryOperation.latest,
      projectId: projectId,
      action: () => _delegate.latest(
        projectId: projectId,
        releaseId: releaseId,
        policyId: policyId,
      ),
      resultingArtifactIds: (snapshot) {
        return snapshot == null
            ? const []
            : [snapshot.metadata.cryptographicTrustSnapshotId];
      },
    );
  }

  @override
  Future<List<CryptographicTrustSnapshot>> query(
    CryptographicTrustQuery query,
  ) {
    return _instrumentation.observe(
      component: TelemetryComponent.cryptographicTrust,
      operation: TelemetryOperation.query,
      projectId: query.projectId,
      action: () => _delegate.query(query),
    );
  }

  @override
  Future<void> invalidate(String snapshotId) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.cryptographicTrust,
      operation: TelemetryOperation.invalidate,
      action: () => _delegate.invalidate(snapshotId),
    );
  }

  @override
  Future<CryptographicDigest?> computeDigest({
    required List<int> subjectBytes,
    required CryptographicDigest descriptor,
  }) {
    return _instrumentation.observe(
      component: TelemetryComponent.cryptographicTrust,
      operation: TelemetryOperation.validate,
      attributes: [
        TelemetryStringAttribute(
          key: 'algorithmId',
          stringValue: descriptor.descriptor.algorithmId,
          classification: TelemetryAttributeClassification.internal,
        ),
      ],
      action: () => _delegate.computeDigest(
        subjectBytes: subjectBytes,
        descriptor: descriptor,
      ),
    );
  }

  @override
  Future<CryptographicVerificationResult?> verifySignature({
    required CryptographicSignatureEnvelope envelope,
    required List<int> subjectBytes,
    required String projectId,
    String? releaseId,
  }) {
    return _instrumentation.observe(
      component: TelemetryComponent.cryptographicTrust,
      operation: TelemetryOperation.validate,
      projectId: projectId,
      attributes: [
        TelemetryStringAttribute(
          key: 'signatureId',
          stringValue: envelope.signatureId,
          classification: TelemetryAttributeClassification.internal,
        ),
        TelemetryStringAttribute(
          key: 'algorithmId',
          stringValue: envelope.signatureDescriptor.algorithmId,
          classification: TelemetryAttributeClassification.internal,
        ),
      ],
      action: () => _delegate.verifySignature(
        envelope: envelope,
        subjectBytes: subjectBytes,
        projectId: projectId,
        releaseId: releaseId,
      ),
      resultingArtifactIds: (result) {
        if (result == null) return const [];
        return [result.verificationId];
      },
    );
  }

  @override
  Future<List<CryptographicAttestationVerificationResult>> verifyAttestation({
    required CryptographicAttestationStatement attestation,
    required List<CryptographicSignatureVerificationResult> signatureResults,
  }) {
    return _instrumentation.observe(
      component: TelemetryComponent.cryptographicTrust,
      operation: TelemetryOperation.validate,
      attributes: [
        TelemetryStringAttribute(
          key: 'attestationId',
          stringValue: attestation.attestationId,
          classification: TelemetryAttributeClassification.internal,
        ),
        TelemetryCountAttribute(
          key: 'signatureResultCount',
          count: signatureResults.length,
          classification: TelemetryAttributeClassification.internal,
        ),
      ],
      action: () => _delegate.verifyAttestation(
        attestation: attestation,
        signatureResults: signatureResults,
      ),
    );
  }

  @override
  Future<CryptographicSigningPrimitiveResult> sign({
    required CryptographicKeyReference keyReference,
    required List<int> digestBytes,
    required CryptographicSignatureEnvelope template,
  }) {
    return _instrumentation.observe(
      component: TelemetryComponent.cryptographicTrust,
      operation: TelemetryOperation.evaluate,
      attributes: [
        TelemetryStringAttribute(
          key: 'keyId',
          stringValue: keyReference.keyId,
          classification: TelemetryAttributeClassification.internal,
        ),
        TelemetryStringAttribute(
          key: 'algorithmId',
          stringValue: keyReference.algorithmId,
          classification: TelemetryAttributeClassification.internal,
        ),
        TelemetryStringAttribute(
          key: 'signatureId',
          stringValue: template.signatureId,
          classification: TelemetryAttributeClassification.internal,
        ),
      ],
      action: () => _delegate.sign(
        keyReference: keyReference,
        digestBytes: digestBytes,
        template: template,
      ),
    );
  }
}
