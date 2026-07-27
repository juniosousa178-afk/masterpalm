import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/release_evidence/release_evidence_enums.dart';
import '../../models/release_governance/release_governance_enums.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

/// Builds dashboard release evidence section from optional injected bundle.
///
/// Consumes published bundle only — never executes evaluate.
class ReleaseEvidenceSectionBuilder implements DashboardSectionBuilder {
  const ReleaseEvidenceSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.releaseEvidence;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final bundle = context.sources.releaseEvidence ??
        context.request.releaseEvidenceBundle;
    if (bundle == null) {
      return buildSection(
        type: sectionType,
        title: 'Release Evidence',
        order: 130,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('releaseEvidence.status', 'Release Evidence')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['Release Evidence bundle unavailable'],
      );
    }

    return buildSection(
      type: sectionType,
      title: 'Release Evidence',
      order: 130,
      availability: DashboardAvailability.available,
      widgets: [
        statusWidget(
          widgetId: 'releaseEvidence.eligibility',
          title: 'Eligibility',
          status: bundle.eligibility.status.wireName,
        ),
        statusWidget(
          widgetId: 'releaseEvidence.release',
          title: 'Release',
          status:
              '${bundle.metadata.releaseId}@${bundle.metadata.releaseVersion}',
          order: 1,
        ),
        statusWidget(
          widgetId: 'releaseEvidence.environment',
          title: 'Environment',
          status: bundle.metadata.environment.wireName,
          order: 2,
        ),
        scalarWidget(
          widgetId: 'releaseEvidence.policy-version',
          title: 'Policy version',
          value: bundle.metadata.policyVersion.toDouble(),
          order: 3,
        ),
        scalarWidget(
          widgetId: 'releaseEvidence.evidence-count',
          title: 'Evidence count',
          value: bundle.metadata.evidenceCount.toDouble(),
          order: 4,
        ),
        scalarWidget(
          widgetId: 'releaseEvidence.attestation-count',
          title: 'Attestation count',
          value: bundle.metadata.attestationCount.toDouble(),
          order: 5,
        ),
        percentageWidget(
          widgetId: 'releaseEvidence.evidence-coverage',
          title: 'Evidence coverage',
          value: bundle.coverage.evidenceCoveragePercentage,
          order: 6,
        ),
        percentageWidget(
          widgetId: 'releaseEvidence.attestation-coverage',
          title: 'Attestation coverage',
          value: bundle.coverage.attestationCoveragePercentage,
          order: 7,
        ),
        statusWidget(
          widgetId: 'releaseEvidence.qualityGate',
          title: 'Quality Gate ref',
          status: bundle.qualityGateReference.qualityGateSnapshotId,
          order: 8,
        ),
        statusWidget(
          widgetId: 'releaseEvidence.releaseDecision',
          title: 'Release Decision ref',
          status: bundle.releaseDecisionReference.releaseDecisionSnapshotId,
          order: 9,
        ),
        statusWidget(
          widgetId: 'releaseEvidence.compatibility',
          title: 'Compatibility',
          status: bundle.compatibility.status.wireName,
          order: 10,
        ),
      ],
      limitations: bundle.limitations.map((l) => l.description).toList(),
    );
  }
}
