import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';
import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_evidence/release_evidence_bundle_metadata.dart';
import '../models/release_evidence/release_evidence_compatibility.dart';
import '../models/release_evidence/release_evidence_enums.dart';
import '../models/release_evidence/release_evidence_messages.dart';
import '../models/release_evidence/release_evidence_policy.dart';
import '../models/release_evidence/release_evidence_subject.dart';
import '../models/release_governance/release_context.dart';
import '../models/release_governance/release_decision_snapshot.dart';
import '../models/release_governance/release_governance_enums.dart';
import 'release_evidence_canonical_serializer.dart';
import 'release_evidence_collector.dart';
import 'release_evidence_identity_builder.dart';
import 'resolved_release_evidence_sources.dart';

/// Builds descriptive release evidence bundles from collected artifacts.
class ReleaseEvidenceBundleBuilder {
  ReleaseEvidenceBundleBuilder({
    ReleaseEvidenceCanonicalSerializer? serializer,
    ReleaseEvidenceIdentityBuilder? identityBuilder,
  })  : _serializer = serializer ?? const ReleaseEvidenceCanonicalSerializer(),
        _identityBuilder =
            identityBuilder ?? const ReleaseEvidenceIdentityBuilder();

  final ReleaseEvidenceCanonicalSerializer _serializer;
  final ReleaseEvidenceIdentityBuilder _identityBuilder;

  ReleaseEvidenceBundle build({
    required ReleaseEvidenceEvaluationContext context,
    required ReleaseEvidenceCollectedArtifacts collected,
    required String evaluatedAt,
  }) {
    final request = context.request;
    final policy = context.evidencePolicy;
    final sources = context.sources;
    final releaseContext = request.releaseContext;

    final evidence = List.of(collected.evidence)
      ..sort(
        (a, b) => a.artifactReference.artifactId
            .compareTo(b.artifactReference.artifactId),
      );
    final provenance = List.of(collected.provenance)
      ..sort((a, b) => a.provenanceId.compareTo(b.provenanceId));
    final attestations = List.of(collected.attestations)
      ..sort(
        (a, b) => a.metadata.attestationId.compareTo(b.metadata.attestationId),
      );

    final compatibility = _buildCompatibility(
      policy: policy,
      releaseContext: releaseContext,
      qg: collected.qualityGateSnapshot,
      rg: collected.releaseDecisionSnapshot,
      sources: sources,
    );
    final eligibility = _buildEligibility(
      policy: policy,
      releaseContext: releaseContext,
      collected: collected,
      sources: sources,
    );
    final coverage = _buildCoverage(
      policy: policy,
      collected: collected,
      sources: sources,
    );

    final warnings = <ReleaseEvidenceWarning>[...sources.warnings];
    final errors = <ReleaseEvidenceError>[...sources.errors];
    final limitations = <ReleaseEvidenceLimitation>[
      ...sources.limitations,
      const ReleaseEvidenceLimitation(
        limitationId: 'no-crypto-verification',
        code: ReleaseEvidenceLimitationCode.noCryptographicVerification,
        description: 'Bundle assembly is structural only',
        impact: 'No cryptographic verification performed',
        resolvable: false,
      ),
    ];
    final explanations = <ReleaseEvidenceExplanation>[];
    if (request.includeExplanations) {
      explanations
          .addAll(_buildExplanations(compatibility, eligibility, coverage));
    }

    if (policy.metadata.status == ReleaseEvidencePolicyStatus.deprecated) {
      warnings.add(
        const ReleaseEvidenceWarning(
          warningId: 'deprecated-policy',
          code: ReleaseEvidenceWarningCode.deprecatedPolicy,
          message: 'Evidence policy is deprecated',
          severity: ReleaseEvidenceCollectionRuleSeverity.warning,
        ),
      );
    }

    final policyFingerprint =
        policy.metadata.fingerprint ?? _serializer.policyFingerprint(policy);
    final requestFingerprint = _serializer.requestFingerprint(request);
    final sourceSetFingerprint = _serializer.sourceReferencesFingerprint(
      sources.sourceReferences,
    );

    final subject = ReleaseEvidenceSubject(
      subjectId: 'subject:${releaseContext.releaseId}',
      subjectType: ReleaseEvidenceSubjectType.release,
      projectId: releaseContext.projectId,
      releaseId: releaseContext.releaseId,
      releaseVersion: releaseContext.releaseVersion,
      commitId: releaseContext.commitId,
      branch: releaseContext.branch,
      environment: releaseContext.environment,
    );

    final provisionalFingerprint = _serializer.fingerprintFromString(
      {
        'policy': policyFingerprint,
        'request': requestFingerprint,
        'sources': sourceSetFingerprint,
        'evidenceCount': evidence.length,
      }.toString(),
    );

    final bundleId = _identityBuilder.buildBundleId(
      projectId: releaseContext.projectId,
      releaseId: releaseContext.releaseId,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
      bundleFingerprint: provisionalFingerprint,
      schemaVersion: ReleaseEvidenceBundleMetadata.currentSchemaVersion,
    );

    final metadata = ReleaseEvidenceBundleMetadata(
      bundleId: bundleId,
      projectId: releaseContext.projectId,
      releaseId: releaseContext.releaseId,
      releaseVersion: releaseContext.releaseVersion,
      commitId: releaseContext.commitId,
      environment: releaseContext.environment,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
      policyFingerprint: policyFingerprint,
      schemaVersion: ReleaseEvidenceBundleMetadata.currentSchemaVersion,
      calculationVersion: policy.metadata.calculationVersion,
      canonicalizationVersion: policy.metadata.canonicalizationVersion,
      sourceSetFingerprint: sourceSetFingerprint,
      requestFingerprint: requestFingerprint,
      createdAt: evaluatedAt,
      evaluatedAt: evaluatedAt,
      referenceTime: request.referenceTime,
      evidenceCount: evidence.length,
      attestationCount: attestations.length,
      fingerprint: provisionalFingerprint,
    );

    final bundle = ReleaseEvidenceBundle(
      metadata: metadata,
      subject: subject,
      policyReference: ReleaseEvidencePolicyReference(
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
        policyFingerprint: policyFingerprint,
      ),
      releaseContextReference: ReleaseReleaseContextReference(
        releaseContextId: releaseContext.releaseId,
        projectId: releaseContext.projectId,
        releaseId: releaseContext.releaseId,
        fingerprint: releaseContext.releaseId,
        commitId: releaseContext.commitId,
      ),
      qualityGateReference:
          _qualityGateReference(collected.qualityGateSnapshot),
      releaseDecisionReference:
          _releaseDecisionReference(collected.releaseDecisionSnapshot),
      evidence: evidence,
      provenance: provenance,
      attestations: attestations,
      compatibility: compatibility,
      eligibility: eligibility,
      coverage: coverage,
      explanations: explanations,
      warnings: warnings,
      errors: errors,
      limitations: limitations,
      sourceReferences: sources.sourceReferences,
      fingerprint: provisionalFingerprint,
    );

    final fingerprint = _identityBuilder.fingerprintForBundle(bundle);
    return bundle.copyWith(
      metadata: metadata.copyWith(fingerprint: fingerprint),
      fingerprint: fingerprint,
    );
  }

  ReleaseQualityGateEvidenceReference _qualityGateReference(
    QualityGateSnapshot? snapshot,
  ) {
    if (snapshot == null) {
      return const ReleaseQualityGateEvidenceReference(
        qualityGateSnapshotId: 'unavailable',
        qualityGateFingerprint: 'unavailable',
        policyId: 'unavailable',
        policyVersion: 0,
        decision: 'unavailable',
      );
    }
    return ReleaseQualityGateEvidenceReference(
      qualityGateSnapshotId: snapshot.metadata.qualityGateSnapshotId,
      qualityGateFingerprint: snapshot.metadata.qualityGateFingerprint,
      policyId: snapshot.metadata.policyId,
      policyVersion: snapshot.metadata.policyVersion,
      decision: snapshot.metadata.decision.wireName,
      projectId: snapshot.metadata.projectId,
      commitId: snapshot.metadata.commitId,
    );
  }

  ReleaseDecisionEvidenceReference _releaseDecisionReference(
    ReleaseDecisionSnapshot? snapshot,
  ) {
    if (snapshot == null) {
      return const ReleaseDecisionEvidenceReference(
        releaseDecisionSnapshotId: 'unavailable',
        releaseDecisionFingerprint: 'unavailable',
        policyId: 'unavailable',
        policyVersion: 0,
        decision: 'unavailable',
      );
    }
    return ReleaseDecisionEvidenceReference(
      releaseDecisionSnapshotId: snapshot.metadata.snapshotId,
      releaseDecisionFingerprint: snapshot.fingerprint,
      policyId: snapshot.metadata.policyId,
      policyVersion: snapshot.metadata.policyVersion,
      decision: snapshot.decision.wireName,
      qualityGateSnapshotId: snapshot.metadata.qualityGateSnapshotId,
      projectId: snapshot.metadata.projectId,
      commitId: snapshot.metadata.commitId,
    );
  }

  ReleaseEvidenceCompatibility _buildCompatibility({
    required ReleaseEvidencePolicy policy,
    required ReleaseContext releaseContext,
    required QualityGateSnapshot? qg,
    required ReleaseDecisionSnapshot? rg,
    required ResolvedReleaseEvidenceSources sources,
  }) {
    final checks = <ReleaseEvidenceCompatibilityCheck>[];
    final compatible = <ReleaseEvidenceType>[];
    final partial = <ReleaseEvidenceType>[];
    final incompatible = <ReleaseEvidenceType>[];
    final unknown = <ReleaseEvidenceType>[];
    final reasons = <String>[];

    void assessSource(
      ReleaseEvidenceType type,
      bool available, {
      bool? projectMatch,
      bool? commitMatch,
    }) {
      if (!available) {
        unknown.add(type);
        reasons.add('$type unavailable');
        return;
      }
      if (projectMatch == false || commitMatch == false) {
        partial.add(type);
        reasons.add('$type partially compatible');
        return;
      }
      compatible.add(type);
    }

    assessSource(
      ReleaseEvidenceType.releaseContext,
      true,
      projectMatch: true,
      commitMatch: true,
    );

    final qgAvailable = qg != null;
    assessSource(
      ReleaseEvidenceType.qualityGate,
      qgAvailable,
      projectMatch:
          qg == null || qg.metadata.projectId == releaseContext.projectId,
      commitMatch: qg == null ||
          qg.metadata.commitId == null ||
          qg.metadata.commitId == releaseContext.commitId,
    );
    if (qgAvailable) {
      final qgSnapshot = qg;
      final qgPolicyOk = policy.compatibilityPolicy.allowedQualityGatePolicyIds
              .contains(qgSnapshot.metadata.policyId) &&
          policy.compatibilityPolicy.allowedQualityGatePolicyVersions
              .contains(qgSnapshot.metadata.policyVersion);
      checks.add(
        ReleaseEvidenceCompatibilityCheck(
          checkId: 'qg-policy',
          checkType: 'qualityGatePolicy',
          status: qgPolicyOk
              ? ReleaseEvidenceCompatibilityStatus.compatible
              : ReleaseEvidenceCompatibilityStatus.incompatible,
          expected:
              policy.compatibilityPolicy.allowedQualityGatePolicyIds.join(','),
          actual: qgSnapshot.metadata.policyId,
        ),
      );
      if (!qgPolicyOk) incompatible.add(ReleaseEvidenceType.qualityGate);
    }

    final rgAvailable = rg != null;
    assessSource(
      ReleaseEvidenceType.releaseGovernance,
      rgAvailable,
      projectMatch:
          rg == null || rg.metadata.projectId == releaseContext.projectId,
      commitMatch:
          rg == null || rg.metadata.commitId == releaseContext.commitId,
    );

    final status = incompatible.isNotEmpty
        ? ReleaseEvidenceCompatibilityStatus.incompatible
        : partial.isNotEmpty
            ? ReleaseEvidenceCompatibilityStatus.partiallyCompatible
            : compatible.isEmpty
                ? ReleaseEvidenceCompatibilityStatus.unknown
                : ReleaseEvidenceCompatibilityStatus.compatible;

    final fingerprint = _serializer.fingerprintFromString(
      {
        'status': status.wireName,
        'compatible': compatible.map((e) => e.wireName).toList(),
        'partial': partial.map((e) => e.wireName).toList(),
        'incompatible': incompatible.map((e) => e.wireName).toList(),
      }.toString(),
    );

    return ReleaseEvidenceCompatibility(
      status: status,
      checks: checks,
      compatibleSources: compatible,
      partiallyCompatibleSources: partial,
      incompatibleSources: incompatible,
      unknownSources: unknown,
      reasons: reasons,
      compatibilityFingerprint: fingerprint,
    );
  }

  ReleaseEvidenceEligibility _buildEligibility({
    required ReleaseEvidencePolicy policy,
    required ReleaseContext releaseContext,
    required ReleaseEvidenceCollectedArtifacts collected,
    required ResolvedReleaseEvidenceSources sources,
  }) {
    final missing = <ReleaseEvidenceType>[];
    final incompatible = <ReleaseEvidenceType>[];
    final reasons = <String>[];
    final eligibility = policy.eligibilityPolicy;

    if (eligibility.requireReleaseContext) {
      reasons.add('release context present');
    }
    if (eligibility.requireQualityGate &&
        collected.qualityGateSnapshot == null) {
      missing.add(ReleaseEvidenceType.qualityGate);
      reasons.add('quality gate missing');
    }
    if (eligibility.requireReleaseDecision &&
        collected.releaseDecisionSnapshot == null) {
      missing.add(ReleaseEvidenceType.releaseGovernance);
      reasons.add('release decision missing');
    }
    if (eligibility.supportedEnvironments.isNotEmpty &&
        !eligibility.supportedEnvironments
            .contains(releaseContext.environment)) {
      incompatible.add(ReleaseEvidenceType.releaseContext);
      reasons.add('environment not supported by policy');
    }
    if (eligibility.supportedReleaseTypes.isNotEmpty &&
        !eligibility.supportedReleaseTypes
            .contains(releaseContext.releaseType)) {
      incompatible.add(ReleaseEvidenceType.releaseContext);
      reasons.add('release type not supported by policy');
    }

    final normativeCount = collected.evidence
        .where((e) => e.evidenceRole == ReleaseEvidenceRole.normative)
        .length;
    if (eligibility.requireNormativeEvidence &&
        normativeCount < eligibility.minimumNormativeEvidenceCount) {
      reasons.add('insufficient normative evidence');
    }

    final status = missing.isNotEmpty || incompatible.isNotEmpty
        ? (missing.isNotEmpty
            ? ReleaseEvidenceEligibilityStatus.ineligible
            : ReleaseEvidenceEligibilityStatus.partiallyEligible)
        : ReleaseEvidenceEligibilityStatus.eligible;

    final fingerprint = _serializer.fingerprintFromString(
      {
        'status': status.wireName,
        'missing': missing.map((e) => e.wireName).toList(),
      }.toString(),
    );

    return ReleaseEvidenceEligibility(
      status: status,
      reasons: reasons,
      missingSources: missing,
      incompatibleSources: incompatible,
      eligibilityFingerprint: fingerprint,
    );
  }

  ReleaseEvidenceCoverage _buildCoverage({
    required ReleaseEvidencePolicy policy,
    required ReleaseEvidenceCollectedArtifacts collected,
    required ResolvedReleaseEvidenceSources sources,
  }) {
    final requiredEvidence = policy.requiredEvidenceTypes.length;
    final presentEvidence = collected.evidence.length;
    final validEvidence = collected.evidence
        .where(
          (e) =>
              e.availability == ReleaseEvidenceAvailabilityStatus.available &&
              e.compatibility == ReleaseEvidenceCompatibilityStatus.compatible,
        )
        .length;
    final normativeEvidence = collected.evidence
        .where((e) => e.evidenceRole == ReleaseEvidenceRole.normative)
        .length;
    final supportingEvidence = collected.evidence
        .where((e) => e.evidenceRole == ReleaseEvidenceRole.supporting)
        .length;

    final requiredAttestations =
        policy.attestationRequirements.where((r) => r.required).length;
    final presentAttestations = collected.attestations.length;
    final validAttestations = collected.attestations
        .where(
          (a) =>
              a.status == ReleaseAttestationStatus.active ||
              a.status == ReleaseAttestationStatus.issued,
        )
        .length;

    final provenanceRequired =
        policy.requiredEvidenceTypes.contains(ReleaseEvidenceType.provenance)
            ? 1
            : 0;
    final provenancePresent = collected.provenance.length;

    final availableSources =
        sources.allSources.where((s) => s.isAvailable).length;
    final totalSources = sources.allSources
        .where(
          (s) => s.state != ResolvedReleaseEvidenceSourceState.notRequested,
        )
        .length;

    final evidenceCoverage = _percentage(validEvidence, requiredEvidence);
    final attestationCoverage =
        _percentage(validAttestations, requiredAttestations);
    final provenanceCoverage =
        _percentage(provenancePresent, provenanceRequired, zeroDefault: 100);
    final sourceCoverage = _percentage(availableSources, totalSources);

    final fingerprint = _serializer.fingerprintFromString(
      {
        'evidence': evidenceCoverage,
        'attestation': attestationCoverage,
        'provenance': provenanceCoverage,
        'source': sourceCoverage,
      }.toString(),
    );

    return ReleaseEvidenceCoverage(
      requiredEvidenceCount: requiredEvidence,
      presentEvidenceCount: presentEvidence,
      validEvidenceCount: validEvidence,
      invalidEvidenceCount: presentEvidence - validEvidence,
      unavailableEvidenceCount: collected.evidence
          .where(
            (e) =>
                e.availability == ReleaseEvidenceAvailabilityStatus.unavailable,
          )
          .length,
      incompatibleEvidenceCount: collected.evidence
          .where(
            (e) =>
                e.compatibility ==
                ReleaseEvidenceCompatibilityStatus.incompatible,
          )
          .length,
      expiredEvidenceCount: 0,
      normativeEvidenceCount: normativeEvidence,
      supportingEvidenceCount: supportingEvidence,
      requiredAttestationCount: requiredAttestations,
      presentAttestationCount: presentAttestations,
      validAttestationCount: validAttestations,
      invalidAttestationCount: presentAttestations - validAttestations,
      expiredAttestationCount: collected.attestations
          .where((a) => a.status == ReleaseAttestationStatus.expired)
          .length,
      unverifiedAttestationCount: collected.attestations
          .where((a) => a.status == ReleaseAttestationStatus.unverified)
          .length,
      provenanceRequiredCount: provenanceRequired,
      provenancePresentCount: provenancePresent,
      evidenceCoveragePercentage: evidenceCoverage,
      attestationCoveragePercentage: attestationCoverage,
      provenanceCoveragePercentage: provenanceCoverage,
      sourceCoveragePercentage: sourceCoverage,
      fingerprint: fingerprint,
    );
  }

  List<ReleaseEvidenceExplanation> _buildExplanations(
    ReleaseEvidenceCompatibility compatibility,
    ReleaseEvidenceEligibility eligibility,
    ReleaseEvidenceCoverage coverage,
  ) {
    return [
      ReleaseEvidenceExplanation(
        explanationId: 'compat-${compatibility.compatibilityFingerprint}',
        type: ReleaseEvidenceExplanationType.compatibility,
        summary: 'Compatibility: ${compatibility.status.wireName}',
        detail: compatibility.reasons.join('; '),
        templateId: 'compatibility-summary',
        compatibilityExplanation: compatibility.status.wireName,
      ),
      ReleaseEvidenceExplanation(
        explanationId: 'elig-${eligibility.eligibilityFingerprint}',
        type: ReleaseEvidenceExplanationType.eligibility,
        summary: 'Eligibility: ${eligibility.status.wireName}',
        detail: eligibility.reasons.join('; '),
        templateId: 'eligibility-summary',
        eligibilityExplanation: eligibility.status.wireName,
      ),
      ReleaseEvidenceExplanation(
        explanationId: 'coverage-${coverage.fingerprint}',
        type: ReleaseEvidenceExplanationType.evidenceAccepted,
        summary:
            'Coverage: evidence ${coverage.evidenceCoveragePercentage}%, attestations ${coverage.attestationCoveragePercentage}%',
        detail: 'Source coverage ${coverage.sourceCoveragePercentage}%',
        templateId: 'coverage-summary',
      ),
    ];
  }

  double _percentage(int numerator, int denominator, {double zeroDefault = 0}) {
    if (denominator <= 0) return zeroDefault;
    final value = (numerator / denominator) * 100;
    if (value < 0) return 0;
    if (value > 100) return 100;
    return double.parse(value.toStringAsFixed(2));
  }
}
