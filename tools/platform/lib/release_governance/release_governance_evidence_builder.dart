import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_evidence.dart';
import '../models/release_governance/release_governance_policy.dart';
import '../models/release_governance/release_governance_rule_value.dart';
import 'release_governance_canonical_serializer.dart';
import 'resolved_release_governance_sources.dart';

/// Builds deterministic evidence records for rule evaluations.
class ReleaseGovernanceEvidenceBuilder {
  const ReleaseGovernanceEvidenceBuilder({
    ReleaseGovernanceCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const ReleaseGovernanceCanonicalSerializer();

  final ReleaseGovernanceCanonicalSerializer _serializer;

  ReleaseGovernanceEvidence build({
    required ReleaseGovernanceRule rule,
    required ReleaseGovernanceTargetResolution resolution,
    required ReleaseGovernanceRuleStatus observedStatus,
    required String referenceTime,
    required String explanation,
    ReleaseGovernanceRuleValue? expectedValue,
  }) {
    final sourceRef = resolution.sourceReference;
    final artifactId = sourceRef?.resolvedId ?? 'unavailable';
    final sourceFingerprint = sourceRef?.fingerprint ?? 'unavailable';

    final evidenceBody = ReleaseGovernanceEvidence(
      evidenceId: '',
      evidenceType: resolution.evidenceType,
      sourceArtifactId: artifactId,
      sourceFingerprint: sourceFingerprint,
      sourceType: sourceRef?.sourceType.wireName,
      ruleId: rule.ruleId,
      observedValue: resolution.actualValue,
      expectedValue: expectedValue ?? rule.expectedValue,
      status: observedStatus.wireName,
      observedAt: referenceTime,
      reference: sourceRef,
      fingerprint: '',
    );

    final fingerprint = _serializer.evidenceFingerprint(evidenceBody);
    return ReleaseGovernanceEvidence(
      evidenceId: 'rge:${rule.ruleId}:$artifactId:$fingerprint',
      evidenceType: evidenceBody.evidenceType,
      sourceArtifactId: evidenceBody.sourceArtifactId,
      sourceFingerprint: evidenceBody.sourceFingerprint,
      sourceType: evidenceBody.sourceType,
      ruleId: evidenceBody.ruleId,
      observedValue: evidenceBody.observedValue,
      expectedValue: evidenceBody.expectedValue,
      status: evidenceBody.status,
      observedAt: evidenceBody.observedAt,
      reference: evidenceBody.reference,
      fingerprint: fingerprint,
      limitations: resolution.limitations.map((l) => l.description).toList(),
    );
  }

  List<ReleaseGovernanceEvidence> buildUnavailable({
    required ReleaseGovernanceRule rule,
    required ReleaseGovernanceRuleStatus observedStatus,
    required String referenceTime,
    required String explanation,
    ReleaseGovernanceEvidenceType evidenceType =
        ReleaseGovernanceEvidenceType.unavailable,
  }) {
    return [
      build(
        rule: rule,
        resolution: ReleaseGovernanceTargetResolution(
          status: ReleaseGovernanceTargetResolutionStatus.unavailable,
          evidenceType: evidenceType,
        ),
        observedStatus: observedStatus,
        referenceTime: referenceTime,
        explanation: explanation,
      ),
    ];
  }
}
