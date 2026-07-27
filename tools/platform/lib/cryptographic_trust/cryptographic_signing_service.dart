import 'dart:convert';

import '../models/cryptographic_trust/cryptographic_key_reference.dart';
import '../models/cryptographic_trust/cryptographic_signature_envelope.dart';
import '../models/cryptographic_trust/cryptographic_trust_algorithm_descriptors.dart';
import '../models/cryptographic_trust/cryptographic_trust_digest.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_subject.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import 'cryptographic_algorithm_registry.dart';
import 'interfaces/cryptographic_signer.dart';
import 'interfaces/cryptographic_signing_key_provider.dart';

/// Result of a signing operation — never exposes private key material.
class CryptographicSigningServiceResult {
  const CryptographicSigningServiceResult({
    required this.outcome,
    this.envelope,
    this.issues = const [],
    this.message,
  });

  final CryptographicPrimitiveOutcome outcome;
  final CryptographicSignatureEnvelope? envelope;
  final List<CryptographicVerificationIssue> issues;
  final String? message;
}

/// Signs digests using registered signers and a signing key provider.
///
/// Returns unavailable when no signer or signing key is configured.
class CryptographicSigningService {
  CryptographicSigningService({
    required CryptographicAlgorithmRegistry algorithmRegistry,
    CryptographicSigningKeyProvider? signingKeyProvider,
  })  : _algorithmRegistry = algorithmRegistry,
        _signingKeyProvider = signingKeyProvider;

  final CryptographicAlgorithmRegistry _algorithmRegistry;
  final CryptographicSigningKeyProvider? _signingKeyProvider;

  Future<CryptographicSigningServiceResult> signDigest({
    required List<int> digestBytes,
    required CryptographicDigest subjectDigest,
    required CryptographicTrustSubject subject,
    required CryptographicSignatureDescriptor signatureDescriptor,
    required CryptographicKeyReference keyReference,
    required String signatureId,
    String? signedAt,
    String? expiresAt,
  }) async {
    if (_signingKeyProvider == null) {
      return const CryptographicSigningServiceResult(
        outcome: CryptographicPrimitiveOutcome.unavailable,
        message: 'no signing key provider configured',
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_SIGNING_UNAVAILABLE',
            severity: CryptographicIssueSeverity.error,
            path: 'signingKeyProvider',
            message: 'No signing key provider configured',
          ),
        ],
      );
    }

    final signer = _algorithmRegistry.resolveSigner(
      algorithmId: signatureDescriptor.algorithmId,
      keyType: signatureDescriptor.keyType,
      format: signatureDescriptor.format,
    );
    if (signer == null) {
      return CryptographicSigningServiceResult(
        outcome: CryptographicPrimitiveOutcome.unsupported,
        message: 'no signer registered for ${signatureDescriptor.algorithmId}',
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_SIGNING_UNSUPPORTED',
            severity: CryptographicIssueSeverity.error,
            path: 'signatureDescriptor.algorithmId',
            message:
                'No signer registered for ${signatureDescriptor.algorithmId}',
            signatureId: signatureId,
            subjectId: subject.subjectId,
          ),
        ],
      );
    }

    final keyResolution =
        _signingKeyProvider!.resolveSigningHandle(keyReference);
    if (keyResolution.outcome != CryptographicPrimitiveOutcome.valid ||
        keyResolution.handle == null) {
      return CryptographicSigningServiceResult(
        outcome: keyResolution.outcome,
        message: keyResolution.message ?? 'signing key unavailable',
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_SIGNING_KEY_UNAVAILABLE',
            severity: CryptographicIssueSeverity.error,
            path: 'keyReference',
            message: keyResolution.message ?? 'Signing key unavailable',
            signatureId: signatureId,
            subjectId: subject.subjectId,
          ),
        ],
      );
    }

    final primitive = await signer.signDigest(
      digestBytes: digestBytes,
      signingKeyHandle: keyResolution.handle!,
      descriptor: signatureDescriptor,
      signatureId: signatureId,
      subjectId: subject.subjectId,
    );

    if (primitive.outcome != CryptographicPrimitiveOutcome.valid ||
        primitive.signatureBytes == null) {
      return CryptographicSigningServiceResult(
        outcome: primitive.outcome,
        message: primitive.message,
        issues: [
          CryptographicVerificationIssue(
            code: 'CT_SIGNING_FAILED',
            severity: CryptographicIssueSeverity.error,
            path: 'signDigest',
            message: primitive.message ?? 'Signing failed',
            signatureId: signatureId,
            subjectId: subject.subjectId,
          ),
        ],
      );
    }

    return CryptographicSigningServiceResult(
      outcome: CryptographicPrimitiveOutcome.valid,
      envelope: CryptographicSignatureEnvelope(
        signatureId: signatureId,
        subject: subject,
        subjectDigest: subjectDigest,
        signatureDescriptor: signatureDescriptor,
        signatureValue: base64Encode(primitive.signatureBytes!),
        signatureEncoding: 'base64',
        keyReference: keyReference,
        signedAt: signedAt,
        expiresAt: expiresAt,
      ),
    );
  }

  /// Provider-facing adapter returning primitive result without exposing keys.
  Future<CryptographicSigningPrimitiveResult> sign({
    required CryptographicKeyReference keyReference,
    required List<int> digestBytes,
    required CryptographicSignatureEnvelope template,
  }) async {
    final result = await signDigest(
      digestBytes: digestBytes,
      subjectDigest: template.subjectDigest,
      subject: template.subject,
      signatureDescriptor: template.signatureDescriptor,
      keyReference: keyReference,
      signatureId: template.signatureId,
      signedAt: template.signedAt,
      expiresAt: template.expiresAt,
    );
    return CryptographicSigningPrimitiveResult(
      outcome: result.outcome,
      envelope: result.envelope,
      signatureBytes: result.envelope == null
          ? null
          : base64Decode(result.envelope!.signatureValue),
      message: result.message,
    );
  }
}
