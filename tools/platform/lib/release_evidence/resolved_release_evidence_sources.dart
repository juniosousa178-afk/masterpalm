import '../models/quality_gate/quality_gate_snapshot.dart';
import '../models/release_evidence/release_attestation_policy.dart';
import '../models/release_evidence/release_attestation_set.dart';
import '../models/release_evidence/release_evidence_enums.dart';
import '../models/release_evidence/release_evidence_messages.dart';
import '../models/release_evidence/release_evidence_policy.dart';
import '../models/release_evidence/release_evidence_reference.dart';
import '../models/release_evidence/release_evidence_request.dart';
import '../models/release_evidence/release_evidence_result.dart';
import '../models/release_evidence/release_provenance.dart';
import '../models/release_evidence/release_verification_policy.dart';
import '../models/release_governance/release_context.dart';
import '../models/release_governance/release_decision_snapshot.dart';

/// Availability state for a resolved release evidence source wrapper.
enum ResolvedReleaseEvidenceSourceState {
  available,
  unavailable,
  notRequested,
  resolutionFailed,
}

/// Wrapper for a resolved source artifact with explicit availability.
class ResolvedReleaseEvidenceSource<T> {
  const ResolvedReleaseEvidenceSource({
    required this.sourceType,
    required this.resolutionMode,
    required this.state,
    this.requestedId,
    this.resolvedArtifact,
    this.resolvedId,
    this.fingerprint,
    this.projectId,
    this.commitId,
    this.policyId,
    this.policyVersion,
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
  });

  final ReleaseEvidenceType sourceType;
  final ReleaseEvidenceSourceResolutionMode resolutionMode;
  final ResolvedReleaseEvidenceSourceState state;
  final String? requestedId;
  final T? resolvedArtifact;
  final String? resolvedId;
  final String? fingerprint;
  final String? projectId;
  final String? commitId;
  final String? policyId;
  final int? policyVersion;
  final List<ReleaseEvidenceWarning> warnings;
  final List<ReleaseEvidenceError> errors;
  final List<ReleaseEvidenceLimitation> limitations;

  bool get isAvailable =>
      state == ResolvedReleaseEvidenceSourceState.available &&
      resolvedArtifact != null;
}

/// Container for all resolved release evidence sources.
class ResolvedReleaseEvidenceSources {
  const ResolvedReleaseEvidenceSources({
    required this.releaseContext,
    required this.qualityGateSnapshot,
    required this.releaseDecisionSnapshot,
    required this.evidencePolicy,
    required this.attestationPolicy,
    required this.verificationPolicy,
    required this.evidenceReferences,
    required this.attestationSet,
    required this.provenance,
    required this.sourceReferences,
    required this.resolutionSummary,
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
    this.compatibilityHints = const [],
  });

  final ResolvedReleaseEvidenceSource<ReleaseContext> releaseContext;
  final ResolvedReleaseEvidenceSource<QualityGateSnapshot> qualityGateSnapshot;
  final ResolvedReleaseEvidenceSource<ReleaseDecisionSnapshot>
      releaseDecisionSnapshot;
  final ResolvedReleaseEvidenceSource<ReleaseEvidencePolicy> evidencePolicy;
  final ResolvedReleaseEvidenceSource<ReleaseAttestationPolicy>
      attestationPolicy;
  final ResolvedReleaseEvidenceSource<ReleaseVerificationPolicy>
      verificationPolicy;
  final ResolvedReleaseEvidenceSource<List<ReleaseEvidenceReference>>
      evidenceReferences;
  final ResolvedReleaseEvidenceSource<ReleaseAttestationSet> attestationSet;
  final ResolvedReleaseEvidenceSource<List<ReleaseProvenance>> provenance;
  final List<ReleaseEvidenceSourceReference> sourceReferences;
  final ReleaseEvidenceSourceResolutionSummary resolutionSummary;
  final List<ReleaseEvidenceWarning> warnings;
  final List<ReleaseEvidenceError> errors;
  final List<ReleaseEvidenceLimitation> limitations;
  final List<String> compatibilityHints;

  List<ResolvedReleaseEvidenceSource<dynamic>> get allSources => [
        releaseContext,
        qualityGateSnapshot,
        releaseDecisionSnapshot,
        evidencePolicy,
        attestationPolicy,
        verificationPolicy,
        evidenceReferences,
        attestationSet,
        provenance,
      ];
}

/// Evaluation context passed through the release evidence pipeline.
class ReleaseEvidenceEvaluationContext {
  const ReleaseEvidenceEvaluationContext({
    required this.request,
    required this.sources,
    required this.evidencePolicy,
    this.attestationPolicy,
    this.verificationPolicy,
  });

  final ReleaseEvidenceRequest request;
  final ResolvedReleaseEvidenceSources sources;
  final ReleaseEvidencePolicy evidencePolicy;
  final ReleaseAttestationPolicy? attestationPolicy;
  final ReleaseVerificationPolicy? verificationPolicy;
}
