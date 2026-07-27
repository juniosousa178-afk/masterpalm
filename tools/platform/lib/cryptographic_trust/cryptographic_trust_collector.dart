import '../models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import '../models/cryptographic_trust/cryptographic_attestation_models.dart';
import '../models/cryptographic_trust/cryptographic_key_reference.dart';
import '../models/cryptographic_trust/cryptographic_revocation_record.dart';
import '../models/cryptographic_trust/cryptographic_signature_envelope.dart';
import '../models/cryptographic_trust/cryptographic_transparency_log_reference.dart';
import '../models/cryptographic_trust/cryptographic_trust_anchor.dart';
import '../models/cryptographic_trust/cryptographic_trust_digest.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_fingerprint.dart';
import '../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_operation_message.dart';
import '../models/cryptographic_trust/cryptographic_trust_policy.dart';
import '../models/cryptographic_trust/cryptographic_trust_source_reference.dart';
import '../models/cryptographic_trust/cryptographic_trust_subject.dart';
import '../models/cryptographic_trust/cryptographic_operation_context.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';

/// Result of collecting cryptographic trust material from resolved sources.
class CryptographicTrustCollectionResult {
  const CryptographicTrustCollectionResult({
    required this.material,
    this.conflicts = const [],
  });

  final CollectedCryptographicTrustMaterial material;
  final List<CryptographicTrustOperationMessage> conflicts;
}

/// Collects cryptographic trust material from resolved sources.
///
/// Deduplicates by normative identity and detects fingerprint conflicts.
class CryptographicTrustCollector {
  const CryptographicTrustCollector();

  CryptographicTrustCollectionResult collect(
    CryptographicOperationContext context,
  ) {
    final sources = context.sources;
    final request = context.request;
    final conflicts = <CryptographicTrustOperationMessage>[];

    final subjects = <CryptographicTrustSubject>[];
    final digests = <CryptographicDigest>[];
    final keyReferences = <CryptographicKeyReference>[];
    final signatures = <CryptographicSignatureEnvelope>[];
    final attestations = <CryptographicAttestationStatement>[];
    final trustAnchors = <CryptographicTrustAnchorReference>[];
    final policies = <CryptographicTrustPolicy>[];
    final revocations = <CryptographicRevocationRecord>[];
    final transparencyLogReferences = <CryptographicTransparencyLogReference>[];
    final verificationRequests = <CryptographicVerificationRequest>[];

    final subjectTracker = _NormativeIdentityTracker<CryptographicTrustSubject>(
      kind: 'subject',
      idOf: (s) => s.subjectId,
      fingerprintOf: (s) => CryptographicTrustFingerprint.fromComparableJson(
          s.toComparableJson()),
      onConflict: conflicts,
    );
    final digestTracker = _NormativeIdentityTracker<CryptographicDigest>(
      kind: 'digest',
      idOf: (d) => '${d.subjectId}:${d.descriptor.algorithmId}',
      fingerprintOf: (d) => CryptographicTrustFingerprint.fromComparableJson(
          d.toComparableJson()),
      onConflict: conflicts,
    );
    final keyTracker = _NormativeIdentityTracker<CryptographicKeyReference>(
      kind: 'keyReference',
      idOf: (k) => '${k.keyId}:${k.version}',
      fingerprintOf: (k) => CryptographicTrustFingerprint.fromComparableJson(
          k.toComparableJson()),
      onConflict: conflicts,
    );
    final signatureTracker =
        _NormativeIdentityTracker<CryptographicSignatureEnvelope>(
      kind: 'signature',
      idOf: (s) => s.signatureId,
      fingerprintOf: (s) => CryptographicTrustFingerprint.fromComparableJson(
        s.toComparableJson(),
      ),
      onConflict: conflicts,
    );
    final attestationTracker =
        _NormativeIdentityTracker<CryptographicAttestationStatement>(
      kind: 'attestation',
      idOf: (a) => a.attestationId,
      fingerprintOf: (a) => CryptographicTrustFingerprint.fromComparableJson(
        a.toComparableJson(),
      ),
      onConflict: conflicts,
    );
    final anchorTracker =
        _NormativeIdentityTracker<CryptographicTrustAnchorReference>(
      kind: 'trustAnchor',
      idOf: (a) => a.trustAnchorId,
      fingerprintOf: (a) => CryptographicTrustFingerprint.fromComparableJson(
        a.toComparableJson(),
      ),
      onConflict: conflicts,
    );
    final policyTracker = _NormativeIdentityTracker<CryptographicTrustPolicy>(
      kind: 'policy',
      idOf: (p) => '${p.policyId}:v${p.version}',
      fingerprintOf: (p) => CryptographicTrustFingerprint.fromComparableJson(
          p.toComparableJson()),
      onConflict: conflicts,
    );
    final revocationTracker =
        _NormativeIdentityTracker<CryptographicRevocationRecord>(
      kind: 'revocation',
      idOf: (r) => r.revocationId,
      fingerprintOf: (r) => CryptographicTrustFingerprint.fromComparableJson(
        r.toComparableJson(),
      ),
      onConflict: conflicts,
    );
    final transparencyTracker =
        _NormativeIdentityTracker<CryptographicTransparencyLogReference>(
      kind: 'transparencyLogReference',
      idOf: (r) => '${r.logId}:${r.entryId}',
      fingerprintOf: (r) => CryptographicTrustFingerprint.fromComparableJson(
        r.toComparableJson(),
      ),
      onConflict: conflicts,
    );
    final verificationRequestTracker =
        _NormativeIdentityTracker<CryptographicVerificationRequest>(
      kind: 'verificationRequest',
      idOf: (r) => r.requestId,
      fingerprintOf: (r) => CryptographicTrustFingerprint.fromComparableJson(
        r.toComparableJson(),
      ),
      onConflict: conflicts,
    );

    void collectFromVerificationRequest(CryptographicVerificationRequest vr) {
      verificationRequestTracker.add(vr, verificationRequests);
      for (final subject in vr.subjects) {
        subjectTracker.add(subject, subjects);
        if (subject.digest != null) {
          digestTracker.add(subject.digest!, digests);
        }
      }
      for (final signature in vr.signatures) {
        signatureTracker.add(signature, signatures);
        subjectTracker.add(signature.subject, subjects);
        digestTracker.add(signature.subjectDigest, digests);
        keyTracker.add(signature.keyReference, keyReferences);
        if (signature.trustAnchorReference != null) {
          anchorTracker.add(signature.trustAnchorReference!, trustAnchors);
          keyTracker.add(
            signature.trustAnchorReference!.keyReference,
            keyReferences,
          );
        }
      }
      for (final attestation in vr.attestations) {
        attestationTracker.add(attestation, attestations);
        for (final signature in attestation.signatures) {
          signatureTracker.add(signature, signatures);
          digestTracker.add(signature.subjectDigest, digests);
          keyTracker.add(signature.keyReference, keyReferences);
        }
      }
      if (vr.policy != null) {
        policyTracker.add(vr.policy!, policies);
      }
      for (final anchor in vr.trustAnchors) {
        anchorTracker.add(anchor, trustAnchors);
        keyTracker.add(anchor.keyReference, keyReferences);
      }
      for (final revocation in vr.revocations) {
        revocationTracker.add(revocation, revocations);
      }
      for (final reference in vr.transparencyLogReferences) {
        transparencyTracker.add(reference, transparencyLogReferences);
        digestTracker.add(reference.entryDigest, digests);
      }
    }

    if (sources.verificationRequest.isAvailable) {
      collectFromVerificationRequest(
        sources.verificationRequest.resolvedArtifact!,
      );
    }

    if (sources.trustPolicy.isAvailable) {
      policyTracker.add(sources.trustPolicy.resolvedArtifact!, policies);
    } else if (context.policy != null) {
      policyTracker.add(context.policy!, policies);
    }

    final sourceReferences =
        List<CryptographicTrustSourceReference>.from(sources.sourceReferences);

    _sortCollected(
      subjects,
      digests,
      keyReferences,
      signatures,
      attestations,
      trustAnchors,
      policies,
      revocations,
      transparencyLogReferences,
      verificationRequests,
      sourceReferences,
    );

    return CryptographicTrustCollectionResult(
      material: CollectedCryptographicTrustMaterial(
        subjects: subjects,
        digests: digests,
        keyReferences: keyReferences,
        signatures: signatures,
        attestations: attestations,
        trustAnchors: trustAnchors,
        policies: policies,
        revocations: revocations,
        transparencyLogReferences: transparencyLogReferences,
        verificationRequests: verificationRequests,
        sourceReferences: sourceReferences,
        metadata: {
          'evaluationId': request.evaluationId,
          'projectId': request.projectId,
          if (request.releaseId != null) 'releaseId': request.releaseId!,
          'collectedAt': request.requestedAt,
        },
      ),
      conflicts: conflicts,
    );
  }

  void _sortCollected(
    List<CryptographicTrustSubject> subjects,
    List<CryptographicDigest> digests,
    List<CryptographicKeyReference> keyReferences,
    List<CryptographicSignatureEnvelope> signatures,
    List<CryptographicAttestationStatement> attestations,
    List<CryptographicTrustAnchorReference> trustAnchors,
    List<CryptographicTrustPolicy> policies,
    List<CryptographicRevocationRecord> revocations,
    List<CryptographicTransparencyLogReference> transparencyLogReferences,
    List<CryptographicVerificationRequest> verificationRequests,
    List<CryptographicTrustSourceReference> sourceReferences,
  ) {
    subjects.sort((a, b) => a.subjectId.compareTo(b.subjectId));
    digests.sort((a, b) {
      final subject = a.subjectId.compareTo(b.subjectId);
      if (subject != 0) return subject;
      return a.descriptor.algorithmId.compareTo(b.descriptor.algorithmId);
    });
    keyReferences.sort((a, b) {
      final key = a.keyId.compareTo(b.keyId);
      if (key != 0) return key;
      return a.version.compareTo(b.version);
    });
    signatures.sort((a, b) => a.signatureId.compareTo(b.signatureId));
    attestations.sort((a, b) => a.attestationId.compareTo(b.attestationId));
    trustAnchors.sort((a, b) => a.trustAnchorId.compareTo(b.trustAnchorId));
    policies.sort((a, b) {
      final id = a.policyId.compareTo(b.policyId);
      if (id != 0) return id;
      return a.version.compareTo(b.version);
    });
    revocations.sort((a, b) => a.revocationId.compareTo(b.revocationId));
    transparencyLogReferences.sort((a, b) {
      final log = a.logId.compareTo(b.logId);
      if (log != 0) return log;
      return a.entryId.compareTo(b.entryId);
    });
    verificationRequests.sort((a, b) => a.requestId.compareTo(b.requestId));
    sourceReferences.sort((a, b) => a.sourceId.compareTo(b.sourceId));
  }
}

class _NormativeIdentityTracker<T> {
  _NormativeIdentityTracker({
    required this.kind,
    required this.idOf,
    required this.fingerprintOf,
    required this.onConflict,
  });

  final String kind;
  final String Function(T value) idOf;
  final String Function(T value) fingerprintOf;
  final List<CryptographicTrustOperationMessage> onConflict;
  final Map<String, String> _seenFingerprints = {};

  void add(T value, List<T> target) {
    final id = idOf(value);
    final fingerprint = fingerprintOf(value);
    final existing = _seenFingerprints[id];
    if (existing == null) {
      _seenFingerprints[id] = fingerprint;
      target.add(value);
      return;
    }
    if (existing == fingerprint) {
      return;
    }
    onConflict.add(
      CryptographicTrustOperationMessage(
        messageId: 'conflict-$kind-$id',
        code: 'fingerprint-mismatch',
        message:
            'Normative identity conflict for $kind $id: fingerprints differ',
        severity: CryptographicIssueSeverity.error,
        operation: CryptographicTrustOperation.collect,
        conflictType: CryptographicTrustConflictType.fingerprintMismatch,
        metadata: {
          'kind': kind,
          'identityId': id,
          'existingFingerprint': existing,
          'incomingFingerprint': fingerprint,
        },
      ),
    );
  }
}
