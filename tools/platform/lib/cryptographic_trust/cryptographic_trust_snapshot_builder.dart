import '../models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import '../models/cryptographic_trust/cryptographic_operation_context.dart';
import '../models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import 'cryptographic_trust_engine.dart';
import 'cryptographic_trust_identity_builder.dart';

/// Result of snapshot assembly.
class CryptographicTrustSnapshotBuildResult {
  const CryptographicTrustSnapshotBuildResult({
    required this.snapshot,
    this.warnings = const [],
    this.limitations = const [],
  });

  final CryptographicTrustSnapshot snapshot;
  final List<String> warnings;
  final List<String> limitations;
}

/// Builds immutable cryptographic trust snapshots from engine output.
class CryptographicTrustSnapshotBuilder {
  CryptographicTrustSnapshotBuilder({
    CryptographicTrustIdentityBuilder? identityBuilder,
  }) : _identityBuilder =
            identityBuilder ?? const CryptographicTrustIdentityBuilder();

  final CryptographicTrustIdentityBuilder _identityBuilder;

  CryptographicTrustSnapshotBuildResult build({
    required CryptographicOperationContext context,
    required CollectedCryptographicTrustMaterial material,
    required CryptographicTrustEngineResult engineResult,
    required String evaluatedAt,
    String? publishedAt,
  }) {
    final request = context.request;
    final policy = context.policy;
    final verificationResult = engineResult.verificationResult;

    final subjectsFp = _identityBuilder.subjectsFingerprint(material);
    final signaturesFp = _identityBuilder.signaturesFingerprint(material);
    final attestationsFp = _identityBuilder.attestationsFingerprint(material);
    final policiesFp = _identityBuilder.policiesFingerprint(material);
    final chainsFp = _identityBuilder.trustChainsFingerprint(
      material.copyWith(trustChains: engineResult.trustChains),
    );
    final verificationFp =
        _identityBuilder.verificationFingerprintForResult(verificationResult);

    final limitations = <String>[
      ...engineResult.limitations,
      'snapshot-assembly-only',
      'no-release-authorization',
    ];

    final provisional = CryptographicTrustSnapshot(
      metadata: CryptographicTrustSnapshotMetadata(
        cryptographicTrustSnapshotId: 'provisional',
        projectId: request.projectId,
        releaseId: request.releaseId,
        schemaVersion: CryptographicTrustSnapshotMetadata.currentSchemaVersion,
        canonicalizationVersion:
            CryptographicTrustSnapshotMetadata.currentCanonicalizationVersion,
        createdAt: evaluatedAt,
        evaluatedAt: evaluatedAt,
        publishedAt: publishedAt,
        fingerprint: 'provisional',
        status: engineResult.snapshotStatus,
        subjectsFingerprint: subjectsFp.isEmpty ? null : subjectsFp,
        signaturesFingerprint: signaturesFp.isEmpty ? null : signaturesFp,
        attestationsFingerprint: attestationsFp.isEmpty ? null : attestationsFp,
        policiesFingerprint: policiesFp.isEmpty ? null : policiesFp,
        trustChainsFingerprint: chainsFp.isEmpty ? null : chainsFp,
        verificationFingerprint: verificationFp,
        limitations: limitations,
      ),
      fingerprint: 'provisional',
      status: engineResult.snapshotStatus,
      subjects: material.subjects,
      digests: material.digests,
      keyReferences: material.keyReferences,
      signatures: material.signatures,
      attestations: material.attestations,
      trustAnchors: material.trustAnchors,
      trustChains: engineResult.trustChains,
      trustPolicies: policy == null
          ? material.policies
          : [
              policy,
              ...material.policies.where((p) => p.policyId != policy.policyId)
            ],
      verificationRequests: material.verificationRequests.isNotEmpty
          ? material.verificationRequests
          : [request.verificationRequest],
      verificationResults: [verificationResult],
      revocations: material.revocations,
      transparencyLogReferences: material.transparencyLogReferences,
      sourceReferences: material.sourceReferences,
      warnings: engineResult.warnings,
      limitations: limitations,
      metadataMap: request.metadata,
    );

    final fingerprint = _identityBuilder.fingerprintForSnapshot(
      provisional,
    );
    final snapshotId = _identityBuilder.buildSnapshotId(
      projectId: request.projectId,
      releaseId: request.releaseId ?? 'unknown',
      snapshotFingerprint: fingerprint,
    );

    final identity = _identityBuilder.buildIdentity(
      snapshot: provisional.copyWith(
        fingerprint: fingerprint,
        metadata: provisional.metadata.copyWith(
          cryptographicTrustSnapshotId: snapshotId,
          fingerprint: fingerprint,
        ),
      ),
      material: material.copyWith(trustChains: engineResult.trustChains),
      verificationResult: verificationResult,
    );

    final snapshot = provisional.copyWith(
      metadata: provisional.metadata.copyWith(
        cryptographicTrustSnapshotId: snapshotId,
        fingerprint: fingerprint,
      ),
      fingerprint: fingerprint,
      identity: identity,
    );

    return CryptographicTrustSnapshotBuildResult(
      snapshot: snapshot,
      warnings: engineResult.warnings,
      limitations: limitations,
    );
  }
}
