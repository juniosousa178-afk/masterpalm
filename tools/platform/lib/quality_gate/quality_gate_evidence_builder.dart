import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_evidence.dart';
import '../models/quality_gate/quality_gate_policy.dart';
import '../models/quality_gate/quality_gate_rule_value.dart';
import 'quality_gate_canonical_serializer.dart';
import 'resolved_quality_gate_sources.dart';

/// Builds deterministic evidence records for rule evaluations.
class QualityGateEvidenceBuilder {
  const QualityGateEvidenceBuilder({
    QualityGateCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const QualityGateCanonicalSerializer();

  final QualityGateCanonicalSerializer _serializer;

  QualityGateEvidence build({
    required QualityGateRule rule,
    required QualityGateTargetResolution resolution,
    required QualityGateRuleStatus observedStatus,
    required String explanation,
    QualityGateRuleValue? expectedValue,
  }) {
    final sourceRef = resolution.sourceReference;
    final sourceType = sourceRef?.sourceType ?? QualityGateSourceType.metrics;
    final artifactId = sourceRef?.resolvedId ?? 'unavailable';
    final sourceFingerprint = sourceRef?.fingerprint ?? 'unavailable';

    final evidenceBody = QualityGateEvidence(
      evidenceId: '',
      evidenceType: resolution.evidenceType,
      sourceType: sourceType,
      sourceArtifactId: artifactId,
      sourceFingerprint: sourceFingerprint,
      sourcePolicyId: sourceRef?.policyId,
      sourcePolicyVersion: sourceRef?.policyVersion,
      target: rule.target,
      selector: rule.selector,
      operator: rule.operator,
      actualValue: resolution.actualValue,
      expectedValue: expectedValue ?? rule.expectedValue,
      observedStatus: observedStatus,
      sourceReference: QualityGateEvidenceReference(
        artifactType: sourceType.wireName,
        artifactId: artifactId,
        fingerprint: sourceFingerprint,
        schemaVersion: sourceRef?.schemaVersion ?? 0,
        calculationVersion: sourceRef?.calculationVersion,
        policyId: sourceRef?.policyId,
        policyVersion: sourceRef?.policyVersion,
        projectId: sourceRef?.projectId,
        commitId: sourceRef?.commitId,
        branch: sourceRef?.branch,
      ),
      explanation: explanation,
      limitations: resolution.limitations.map((l) => l.description).toList(),
    );

    final fingerprint = _serializer.evidenceFingerprint(evidenceBody);
    return QualityGateEvidence(
      evidenceId: 'qge:${rule.ruleId}:$artifactId:$fingerprint',
      evidenceType: evidenceBody.evidenceType,
      sourceType: evidenceBody.sourceType,
      sourceArtifactId: evidenceBody.sourceArtifactId,
      sourceFingerprint: evidenceBody.sourceFingerprint,
      sourcePolicyId: evidenceBody.sourcePolicyId,
      sourcePolicyVersion: evidenceBody.sourcePolicyVersion,
      target: evidenceBody.target,
      selector: evidenceBody.selector,
      operator: evidenceBody.operator,
      actualValue: evidenceBody.actualValue,
      expectedValue: evidenceBody.expectedValue,
      observedStatus: evidenceBody.observedStatus,
      sourceReference: evidenceBody.sourceReference,
      explanation: evidenceBody.explanation,
      limitations: evidenceBody.limitations,
    );
  }

  List<QualityGateEvidence> buildUnavailable({
    required QualityGateRule rule,
    required QualityGateRuleStatus observedStatus,
    required String explanation,
    QualityGateEvidenceType evidenceType = QualityGateEvidenceType.unavailable,
  }) {
    final evidence = build(
      rule: rule,
      resolution: QualityGateTargetResolution(
        status: QualityGateTargetResolutionStatus.unavailable,
        evidenceType: evidenceType,
      ),
      observedStatus: observedStatus,
      explanation: explanation,
    );
    return [evidence];
  }
}
