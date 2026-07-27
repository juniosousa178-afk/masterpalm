import '../../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../../models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import '../report_input.dart';

/// Converts [CryptographicTrustSnapshot] into sanitized report input data.
///
/// Consumes an existing snapshot only — never executes evaluate or sign.
/// Verified status does not authorize release.
class CryptographicTrustReportSource {
  const CryptographicTrustReportSource();

  CryptographicTrustReportInputData fromSnapshot(
    CryptographicTrustSnapshot snapshot,
  ) {
    final meta = snapshot.metadata;

    final subjectSummaries = snapshot.subjects
        .map((s) => '${s.subjectId}:${s.subjectType.wireName}')
        .toList();

    final digestSummaries = snapshot.digests
        .map(
          (d) => '${d.subjectId}:${d.descriptor.algorithmId}@${d.encoding}',
        )
        .toList();

    final signatureSummaries = snapshot.signatures
        .map(
          (s) =>
              '${s.signatureId}:${s.signatureDescriptor.algorithmId}:${s.keyReference.keyId}',
        )
        .toList();

    final attestationSummaries = snapshot.attestations
        .map((a) => '${a.attestationId}:${a.attestationType.wireName}')
        .toList();

    final trustAnchorSummaries = snapshot.trustAnchors
        .map(
          (a) =>
              '${a.trustAnchorId}:${a.trustLevel.wireName}:${a.status.wireName}',
        )
        .toList();

    final trustChainSummaries = snapshot.trustChains
        .map(
          (c) =>
              '${c.trustChainId}:${c.status.wireName}:intermediates=${c.intermediateReferences.length}',
        )
        .toList();

    final verificationSummaries = snapshot.verificationResults
        .map(
          (v) =>
              '${v.verificationId}:${v.status.wireName}:${v.trustLevel.wireName}',
        )
        .toList();

    final policySummaries = snapshot.trustPolicies
        .map((p) => '${p.policyId}@${p.version}:${p.status.wireName}')
        .toList();

    final revocationSummaries = snapshot.revocations
        .map(
          (r) => '${r.revocationId}:${r.subjectType.wireName}:${r.subjectId}',
        )
        .toList();

    final transparencySummaries = snapshot.transparencyLogReferences
        .map(
          (t) => '${t.logId}:${t.entryId}:${t.status.wireName}',
        )
        .toList();

    final issueSummaries = snapshot.verificationResults
        .expand((v) => v.issues)
        .map((i) => '${i.code}:${i.severity.wireName}:${i.path}')
        .toList();

    final sourceSummaries = snapshot.sourceReferences
        .map(
          (r) => '${r.sourceType.wireName}:${r.sourceId}',
        )
        .toList();

    return CryptographicTrustReportInputData(
      snapshotId: meta.cryptographicTrustSnapshotId,
      fingerprint: snapshot.fingerprint,
      projectId: meta.projectId,
      releaseId: meta.releaseId ?? '',
      snapshotStatus: snapshot.status.wireName,
      subjectCount: snapshot.subjects.length,
      digestCount: snapshot.digests.length,
      signatureCount: snapshot.signatures.length,
      attestationCount: snapshot.attestations.length,
      trustAnchorCount: snapshot.trustAnchors.length,
      trustChainCount: snapshot.trustChains.length,
      verificationResultCount: snapshot.verificationResults.length,
      policyCount: snapshot.trustPolicies.length,
      revocationCount: snapshot.revocations.length,
      transparencyReferenceCount: snapshot.transparencyLogReferences.length,
      issueCount: issueSummaries.length,
      sourceReferenceCount: snapshot.sourceReferences.length,
      subjectSummaries: subjectSummaries,
      digestSummaries: digestSummaries,
      signatureSummaries: signatureSummaries,
      attestationSummaries: attestationSummaries,
      trustAnchorSummaries: trustAnchorSummaries,
      trustChainSummaries: trustChainSummaries,
      verificationSummaries: verificationSummaries,
      policySummaries: policySummaries,
      revocationSummaries: revocationSummaries,
      transparencySummaries: transparencySummaries,
      issueSummaries: issueSummaries,
      sourceSummaries: sourceSummaries,
      limitations: [
        'verified-does-not-authorize-release',
        ...meta.limitations,
        ...snapshot.limitations,
      ],
      warnings: snapshot.warnings,
    );
  }

  CryptographicTrustReportInputData fromMap(Map<String, dynamic> json) {
    return fromSnapshot(CryptographicTrustSnapshot.fromJson(json));
  }
}
