import '../models/report/report_block.dart';
import '../models/report/report_document.dart';
import '../models/report/report_finding.dart';
import '../models/report/report_metadata.dart';
import '../models/report/report_section.dart';
import '../models/report/report_severity.dart';
import '../models/report/report_table.dart';
import '../models/report/report_type.dart';
import '../report/report_id_factory.dart';
import '../report/report_input.dart';

/// Composes [ReportDocument] from normalized [ReportInput].
class ReportComposer {
  const ReportComposer({ReportIdFactory? idFactory})
      : _idFactory = idFactory ?? const ReportIdFactory();

  final ReportIdFactory _idFactory;

  ReportDocument compose(ReportInput input) {
    final fingerprint =
        _idFactory.fingerprintFromParts(input.fingerprintParts());
    final reportId = _idFactory.create(
      projectId: input.projectId,
      reportType: input.reportType,
      sourceFingerprint: fingerprint,
    );

    final sections = <ReportSection>[];

    switch (input.reportType) {
      case ReportType.architectureSummary:
        if (input.ast != null) sections.add(_astSection(input.ast!));
        if (input.graph != null) sections.add(_graphSection(input.graph!));
        if (input.guardian != null)
          sections.add(_guardianSummarySection(input.guardian!));
      case ReportType.guardianAnalysis:
        if (input.guardian != null) {
          sections.addAll(_guardianFullSections(input.guardian!));
        }
      case ReportType.graphSummary:
        if (input.graph != null) sections.add(_graphSection(input.graph!));
      case ReportType.combinedEngineeringReport:
        if (input.ast != null) sections.add(_astSection(input.ast!));
        if (input.guardian != null) {
          sections.addAll(_guardianFullSections(input.guardian!));
        }
        if (input.graph != null) sections.add(_graphSection(input.graph!));
      case ReportType.metricsSummary:
        if (input.metrics != null)
          sections.add(_metricsSection(input.metrics!));
      case ReportType.historyDiff:
        if (input.history != null)
          sections.add(_historyDiffSection(input.history!));
      case ReportType.engineeringScore:
        if (input.engineeringScore != null)
          sections.add(_engineeringScoreSection(input.engineeringScore!));
      case ReportType.masterPalmEngineeringScore:
        if (input.mes != null) sections.add(_mesSection(input.mes!));
      case ReportType.engineeringDashboard:
        if (input.dashboard != null) {
          sections.add(_dashboardSection(input.dashboard!));
        }
      case ReportType.platformObservability:
        if (input.observability != null) {
          sections.add(_observabilitySection(input.observability!));
        }
      case ReportType.qualityGate:
        if (input.qualityGate != null) {
          sections.add(_qualityGateSection(input.qualityGate!));
        }
      case ReportType.releaseGovernance:
        if (input.releaseGovernance != null) {
          sections.add(_releaseGovernanceSection(input.releaseGovernance!));
        }
      case ReportType.releaseEvidence:
        if (input.releaseEvidence != null) {
          sections.add(_releaseEvidenceSection(input.releaseEvidence!));
        }
      case ReportType.releaseSupplyChain:
        if (input.releaseSupplyChain != null) {
          sections.add(_releaseSupplyChainSection(input.releaseSupplyChain!));
        }
      case ReportType.cicdIntegration:
        if (input.cicdIntegration != null) {
          sections.add(_cicdIntegrationSection(input.cicdIntegration!));
        }
      case ReportType.cryptographicTrust:
        if (input.cryptographicTrust != null) {
          sections
              .addAll(_cryptographicTrustSections(input.cryptographicTrust!));
        }
      case ReportType.persistentArtifacts:
        if (input.persistentArtifacts != null) {
          sections.add(_persistentArtifactsSection(input.persistentArtifacts!));
        }
    }

    sections.sort((a, b) => a.id.compareTo(b.id));

    return ReportDocument(
      metadata: ReportMetadata(
        reportId: reportId,
        reportType: input.reportType,
        reportSchemaVersion: ReportMetadata.currentSchemaVersion,
        projectId: input.projectId,
        generatorVersion: ReportMetadata.defaultGeneratorVersion,
        sourceSnapshotId: input.sourceSnapshotId,
        gitRef: input.gitRef,
        warnings: List<String>.from(input.warnings),
        missingSources: List<String>.from(input.missingOptionalSources),
      ),
      sections: sections,
    );
  }

  ReportSection _astSection(AstReportInputData ast) {
    return ReportSection(
      id: 'ast-summary',
      title: 'AST Structural Summary',
      blocks: [
        const HeadingBlock(level: 2, text: 'AST Structural Summary'),
        SummaryBlock(
          text:
              'Files analyzed: ${ast.filesAnalyzed}, classes: ${ast.totalClasses}, methods: ${ast.totalMethods}',
        ),
        TableBlock(
          table: ReportTable(
            columns: const [
              ReportTableColumn(id: 'metric', label: 'Metric'),
              ReportTableColumn(id: 'value', label: 'Value'),
            ],
            rows: [
              ReportTableRow(cells: ['Files analyzed', '${ast.filesAnalyzed}']),
              ReportTableRow(cells: ['Classes', '${ast.totalClasses}']),
              ReportTableRow(cells: ['Methods', '${ast.totalMethods}']),
              ReportTableRow(
                  cells: ['Firestore writes', '${ast.firestoreWrites}']),
              ReportTableRow(
                  cells: ['Firestore reads', '${ast.firestoreReads}']),
              ReportTableRow(cells: ['Widgets', '${ast.widgetClasses}']),
              ReportTableRow(cells: ['Service files', '${ast.serviceFiles}']),
            ],
          ),
        ),
      ],
    );
  }

  ReportSection _metricsSection(MetricsReportInputData metrics) {
    return ReportSection(
      id: 'metrics-summary',
      title: 'Metrics Summary',
      blocks: [
        const HeadingBlock(level: 2, text: 'Metrics Summary'),
        SummaryBlock(
          text:
              'Snapshot ${metrics.snapshotId} — ${metrics.availableCount}/${metrics.metricCount} metrics available',
        ),
        ListBlock(items: _items(metrics.highlights)),
      ],
    );
  }

  ReportSection _historyDiffSection(HistoryDiffReportInputData history) {
    return ReportSection(
      id: 'history-diff-summary',
      title: 'History Diff Summary',
      blocks: [
        const HeadingBlock(level: 2, text: 'History Diff Summary'),
        SummaryBlock(
          text:
              'From ${history.fromSnapshotId} to ${history.toSnapshotId} — compatibility ${history.compatibilityStatus}',
        ),
        TextBlock(
          text:
              'Changes: ${history.totalChanges} (added ${history.addedCount}, removed ${history.removedCount}, changed ${history.changedCount})',
        ),
        ListBlock(items: _items(history.highlights)),
      ],
    );
  }

  ReportSection _engineeringScoreSection(
    EngineeringScoreReportInputData score,
  ) {
    return ReportSection(
      id: 'engineering-score-summary',
      title: 'Engineering Score Summary',
      blocks: [
        const HeadingBlock(level: 2, text: 'Engineering Score Summary'),
        SummaryBlock(
          text:
              'Policy ${score.policyId} v${score.policyVersion} — score ${score.overallScore.toStringAsFixed(2)}',
        ),
        TextBlock(
          text:
              'Status: ${score.status}, confidence: ${score.confidence}, coverage: ${score.coveragePercentage.toStringAsFixed(2)}%',
        ),
        ListBlock(items: _items(score.dimensionSummaries)),
        if (score.limitations.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Limitations'),
          ListBlock(items: _items(score.limitations)),
        ],
      ],
    );
  }

  ReportSection _mesSection(MESReportInputData mes) {
    return ReportSection(
      id: 'mes-summary',
      title: 'MasterPalm Engineering Score',
      blocks: [
        HeadingBlock(
          level: 2,
          text: '${mes.officialName} (${mes.acronym})',
        ),
        SummaryBlock(
          text:
              'Policy ${mes.policyId} v${mes.policyVersion} (${mes.policyStatus}) — MES ${mes.mesValue.toStringAsFixed(2)}',
        ),
        TextBlock(
          text:
              'Status: ${mes.status}, eligibility: ${mes.eligibility}, confidence: ${mes.confidence}',
        ),
        TextBlock(
          text:
              'Coverage: policy ${mes.policyCoverage.toStringAsFixed(2)}%, evidence ${mes.evidenceCoverage.toStringAsFixed(2)}%',
        ),
        if (mes.bandId != null) TextBlock(text: 'Band: ${mes.bandId}'),
        TextBlock(
          text:
              'Source EngineeringScoreSnapshot: ${mes.sourceEngineeringScoreSnapshotId}',
        ),
        ListBlock(items: _items(mes.dimensionSummaries)),
        if (mes.limitations.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Limitations'),
          ListBlock(items: _items(mes.limitations)),
        ],
      ],
    );
  }

  ReportSection _observabilitySection(ObservabilityReportInputData obs) {
    return ReportSection(
      id: 'platform-observability-summary',
      title: 'Platform Observability',
      blocks: [
        const HeadingBlock(level: 2, text: 'Platform Observability'),
        SummaryBlock(
          text:
              'Snapshot ${obs.telemetrySnapshotId} — status ${obs.status}, compatibility ${obs.compatibility}',
        ),
        TextBlock(
          text:
              'Events: ${obs.eventCount}, operations: ${obs.operationCount}, successes: ${obs.successCount}, failures: ${obs.failureCount}, incomplete: ${obs.incompleteOperationCount}',
        ),
        TextBlock(
          text:
              'Duration total: ${obs.totalDurationMicroseconds}µs, avg: ${obs.averageDurationMicroseconds}µs, min: ${obs.minDurationMicroseconds}µs, max: ${obs.maxDurationMicroseconds}µs',
        ),
        TextBlock(
          text:
              'Coverage: ${obs.eventCoveragePercentage.toStringAsFixed(2)}%, terminal: ${obs.terminalCoveragePercentage.toStringAsFixed(2)}%, conflicts: ${obs.conflictCount}',
        ),
        const HeadingBlock(level: 3, text: 'Components'),
        ListBlock(items: _items(obs.componentSummaries)),
        const HeadingBlock(level: 3, text: 'Operations'),
        ListBlock(items: _items(obs.operationSummaries)),
        const HeadingBlock(level: 3, text: 'Sources'),
        ListBlock(items: _items(obs.sourceSummaries)),
        if (obs.limitations.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Limitations'),
          ListBlock(items: _items(obs.limitations)),
        ],
        if (obs.warnings.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Warnings'),
          ListBlock(items: _items(obs.warnings)),
        ],
        if (obs.errors.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Errors'),
          ListBlock(items: _items(obs.errors)),
        ],
      ],
    );
  }

  ReportSection _qualityGateSection(QualityGateReportInputData gate) {
    return ReportSection(
      id: 'quality-gate-summary',
      title: 'Quality Gate',
      blocks: [
        const HeadingBlock(level: 2, text: 'Quality Gate Executive Summary'),
        SummaryBlock(
          text:
              'Decision ${gate.decision} — policy ${gate.policyId} v${gate.policyVersion}',
        ),
        TextBlock(
          text:
              'Project ${gate.projectId}${gate.commitId != null ? ' @ ${gate.commitId}' : ''}',
        ),
        TextBlock(
          text:
              'Evaluated ${gate.evaluatedRuleCount} rules, failed ${gate.failedRuleCount}, blocking ${gate.blockingFailureCount}',
        ),
        TextBlock(
          text:
              'Coverage required ${gate.requiredRuleCoveragePercentage.toStringAsFixed(2)}%, overall ${gate.overallRuleCoveragePercentage.toStringAsFixed(2)}%',
        ),
        TextBlock(
          text:
              'Eligibility ${gate.eligibility}, compatibility ${gate.compatibility}',
        ),
        if (gate.failedRules.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Failed Rules'),
          ListBlock(items: _items(gate.failedRules)),
        ],
        if (gate.passedRules.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Passed Rules'),
          ListBlock(items: _items(gate.passedRules)),
        ],
        if (gate.unavailableRules.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Unavailable Rules'),
          ListBlock(items: _items(gate.unavailableRules)),
        ],
        if (gate.ruleSetSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Rule Sets'),
          ListBlock(items: _items(gate.ruleSetSummaries)),
        ],
        if (gate.sourceSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Sources'),
          ListBlock(items: _items(gate.sourceSummaries)),
        ],
        if (gate.limitations.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Limitations'),
          ListBlock(items: _items(gate.limitations)),
        ],
        if (gate.warnings.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Warnings'),
          ListBlock(items: _items(gate.warnings)),
        ],
        if (gate.errors.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Errors'),
          ListBlock(items: _items(gate.errors)),
        ],
      ],
    );
  }

  ReportSection _releaseGovernanceSection(
    ReleaseGovernanceReportInputData rg,
  ) {
    return ReportSection(
      id: 'release-governance-summary',
      title: 'Release Governance',
      blocks: [
        const HeadingBlock(level: 2, text: 'Executive Summary'),
        SummaryBlock(
          text:
              'Decision ${rg.decision}${rg.resultStatus != null ? ' (${rg.resultStatus})' : ''} — policy ${rg.policyId} v${rg.policyVersion}',
        ),
        const HeadingBlock(level: 2, text: 'Release Context'),
        TextBlock(
          text:
              'Release ${rg.releaseId} v${rg.releaseVersion} @ ${rg.commitId} (${rg.branch})',
        ),
        TextBlock(
          text: 'Environment ${rg.environment}, type ${rg.releaseType}',
        ),
        const HeadingBlock(level: 2, text: 'Policy'),
        TextBlock(text: '${rg.policyId} v${rg.policyVersion}'),
        const HeadingBlock(level: 2, text: 'Decision'),
        TextBlock(text: rg.decision),
        const HeadingBlock(level: 2, text: 'Quality Gate Reference'),
        TextBlock(
          text: '${rg.qualityGateSnapshotId} (fp ${rg.qualityGateFingerprint})',
        ),
        const HeadingBlock(level: 2, text: 'Compatibility'),
        TextBlock(text: rg.compatibility),
        const HeadingBlock(level: 2, text: 'Eligibility'),
        TextBlock(text: rg.eligibility),
        const HeadingBlock(level: 2, text: 'Coverage'),
        TextBlock(
          text:
              'Required ${rg.requiredRuleCoveragePercentage.toStringAsFixed(2)}%, overall ${rg.overallRuleCoveragePercentage.toStringAsFixed(2)}%',
        ),
        if (rg.failedRules.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Rules — Failed'),
          ListBlock(items: _items(rg.failedRules)),
        ],
        if (rg.passedRules.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Rules — Passed'),
          ListBlock(items: _items(rg.passedRules)),
        ],
        if (rg.waivedRules.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Rules — Waived'),
          ListBlock(items: _items(rg.waivedRules)),
        ],
        if (rg.approvalSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Approvals'),
          ListBlock(items: _items(rg.approvalSummaries)),
        ],
        if (rg.pendingApprovals.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Pending Approvals'),
          ListBlock(items: _items(rg.pendingApprovals)),
        ],
        if (rg.rejectedApprovals.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Rejected Approvals'),
          ListBlock(items: _items(rg.rejectedApprovals)),
        ],
        if (rg.waiverSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Waivers'),
          ListBlock(items: _items(rg.waiverSummaries)),
        ],
        if (rg.openConditions.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Conditions'),
          ListBlock(items: _items(rg.openConditions)),
        ],
        if (rg.evidenceSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Evidence'),
          ListBlock(items: _items(rg.evidenceSummaries)),
        ],
        if (rg.sourceSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Sources'),
          ListBlock(items: _items(rg.sourceSummaries)),
        ],
        if (rg.limitations.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Limitations'),
          ListBlock(items: _items(rg.limitations)),
        ],
        if (rg.warnings.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Warnings'),
          ListBlock(items: _items(rg.warnings)),
        ],
        if (rg.errors.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Errors'),
          ListBlock(items: _items(rg.errors)),
        ],
      ],
    );
  }

  ReportSection _releaseEvidenceSection(ReleaseEvidenceReportInputData re) {
    return ReportSection(
      id: 'release-evidence-summary',
      title: 'Release Evidence',
      blocks: [
        const HeadingBlock(level: 2, text: 'Executive Summary'),
        SummaryBlock(
          text:
              'Bundle ${re.bundleId} — eligibility ${re.eligibility}, policy ${re.policyId} v${re.policyVersion}',
        ),
        const HeadingBlock(level: 2, text: 'Release Context'),
        TextBlock(
          text:
              'Release ${re.releaseId} v${re.releaseVersion} @ ${re.commitId}',
        ),
        TextBlock(text: 'Environment ${re.environment}'),
        const HeadingBlock(level: 2, text: 'Coverage'),
        TextBlock(
          text:
              'Evidence ${re.evidenceCoveragePercentage.toStringAsFixed(2)}%, attestations ${re.attestationCoveragePercentage.toStringAsFixed(2)}%, provenance ${re.provenanceCoveragePercentage.toStringAsFixed(2)}%',
        ),
        const HeadingBlock(level: 2, text: 'Quality Gate Reference'),
        TextBlock(
          text: '${re.qualityGateSnapshotId} (${re.qualityGateDecision})',
        ),
        const HeadingBlock(level: 2, text: 'Release Decision Reference'),
        TextBlock(
          text: '${re.releaseDecisionSnapshotId} (${re.releaseDecision})',
        ),
        if (re.evidenceSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Evidence'),
          ListBlock(items: _items(re.evidenceSummaries)),
        ],
        if (re.attestationSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Attestations'),
          ListBlock(items: _items(re.attestationSummaries)),
        ],
        if (re.provenanceSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Provenance'),
          ListBlock(items: _items(re.provenanceSummaries)),
        ],
        if (re.sourceSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Sources'),
          ListBlock(items: _items(re.sourceSummaries)),
        ],
        if (re.limitations.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Limitations'),
          ListBlock(items: _items(re.limitations)),
        ],
        if (re.warnings.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Warnings'),
          ListBlock(items: _items(re.warnings)),
        ],
        if (re.errors.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Errors'),
          ListBlock(items: _items(re.errors)),
        ],
      ],
    );
  }

  ReportSection _releaseSupplyChainSection(
    ReleaseSupplyChainReportInputData rsc,
  ) {
    return ReportSection(
      id: 'release-supply-chain-summary',
      title: 'Release Supply Chain',
      blocks: [
        const HeadingBlock(level: 2, text: 'Executive Summary'),
        SummaryBlock(
          text:
              'Snapshot ${rsc.snapshotId} — compliance ${rsc.complianceStatus}, supply chain ${rsc.supplyChainStatus}',
        ),
        const HeadingBlock(level: 2, text: 'Release Context'),
        TextBlock(text: 'Release ${rsc.releaseId} @ ${rsc.commitId}'),
        TextBlock(
          text: 'Release Evidence ref ${rsc.releaseEvidenceBundleId}',
        ),
        const HeadingBlock(level: 2, text: 'Policies'),
        TextBlock(
          text:
              'Supply chain ${rsc.supplyChainPolicyId} v${rsc.supplyChainPolicyVersion}',
        ),
        TextBlock(
          text:
              'Distribution ${rsc.distributionPolicyId} v${rsc.distributionPolicyVersion}',
        ),
        TextBlock(
          text:
              'Compliance ${rsc.compliancePolicyId} v${rsc.compliancePolicyVersion}',
        ),
        const HeadingBlock(level: 2, text: 'SBOM'),
        TextBlock(
          text:
              'Status ${rsc.sbomStatus}, components ${rsc.sbomComponentCount}, dependencies ${rsc.sbomDependencyCount}',
        ),
        const HeadingBlock(level: 2, text: 'Compliance'),
        TextBlock(
          text:
              'Status ${rsc.complianceStatus}, checks ${rsc.complianceCheckCount}, violations ${rsc.complianceViolationCount}',
        ),
        if (rsc.artifactSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Artifacts'),
          ListBlock(items: _items(rsc.artifactSummaries)),
        ],
        if (rsc.complianceCheckSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Compliance Checks'),
          ListBlock(items: _items(rsc.complianceCheckSummaries)),
        ],
        if (rsc.complianceViolationSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Compliance Violations'),
          ListBlock(items: _items(rsc.complianceViolationSummaries)),
        ],
        if (rsc.limitations.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Limitations'),
          ListBlock(items: _items(rsc.limitations)),
        ],
        if (rsc.warnings.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Warnings'),
          ListBlock(items: _items(rsc.warnings)),
        ],
      ],
    );
  }

  ReportSection _cicdIntegrationSection(CicdIntegrationReportInputData cicd) {
    return ReportSection(
      id: 'cicd-integration-summary',
      title: 'CI/CD Integration',
      blocks: [
        const HeadingBlock(level: 2, text: 'Executive Summary'),
        SummaryBlock(
          text:
              'Snapshot ${cicd.snapshotId} — status ${cicd.snapshotStatus}, execution ${cicd.pipelineExecutionStatus}',
        ),
        const HeadingBlock(level: 2, text: 'Release Context'),
        TextBlock(text: 'Release ${cicd.releaseId}'),
        TextBlock(text: 'Pipeline definition ${cicd.pipelineDefinitionId}'),
        TextBlock(text: 'Pipeline execution ${cicd.pipelineExecutionId}'),
        TextBlock(text: 'Deployment plan ${cicd.deploymentPlanId}'),
        TextBlock(text: 'Release Evidence ref ${cicd.releaseEvidenceBundleId}'),
        TextBlock(
          text: 'Release Supply Chain ref ${cicd.releaseSupplyChainSnapshotId}',
        ),
        const HeadingBlock(level: 2, text: 'Policies'),
        TextBlock(
          text:
              'Pipeline integration ${cicd.pipelineIntegrationPolicyId} v${cicd.pipelineIntegrationPolicyVersion}',
        ),
        TextBlock(
          text:
              'Pipeline execution ${cicd.pipelineExecutionPolicyId} v${cicd.pipelineExecutionPolicyVersion}',
        ),
        TextBlock(
          text:
              'Deployment integration ${cicd.deploymentIntegrationPolicyId} v${cicd.deploymentIntegrationPolicyVersion}',
        ),
        const HeadingBlock(level: 2, text: 'Pipeline'),
        TextBlock(
          text:
              'Stages ${cicd.pipelineStageCount}, execution ${cicd.pipelineExecutionStatus}, outcome ${cicd.executionResultOutcome}',
        ),
        const HeadingBlock(level: 2, text: 'Deployment'),
        TextBlock(
          text:
              'Targets ${cicd.deploymentPlanTargetCount}, result ${cicd.deploymentResultStatus}',
        ),
        if (cicd.sourceSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Sources'),
          ListBlock(items: _items(cicd.sourceSummaries)),
        ],
        if (cicd.stageSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Stages'),
          ListBlock(items: _items(cicd.stageSummaries)),
        ],
        if (cicd.targetSummaries.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Targets'),
          ListBlock(items: _items(cicd.targetSummaries)),
        ],
        if (cicd.limitations.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Limitations'),
          ListBlock(items: _items(cicd.limitations)),
        ],
        if (cicd.warnings.isNotEmpty) ...[
          const HeadingBlock(level: 2, text: 'Warnings'),
          ListBlock(items: _items(cicd.warnings)),
        ],
      ],
    );
  }

  List<ReportSection> _cryptographicTrustSections(
    CryptographicTrustReportInputData trust,
  ) {
    return [
      ReportSection(
        id: 'cryptographic-trust-summary',
        title: 'Cryptographic Trust Summary',
        blocks: [
          const HeadingBlock(level: 2, text: 'Executive Summary'),
          SummaryBlock(
            text:
                'Snapshot ${trust.snapshotId} — status ${trust.snapshotStatus}. Verified does not authorize release.',
          ),
          TextBlock(text: 'Project ${trust.projectId}'),
          TextBlock(text: 'Release ${trust.releaseId}'),
          TextBlock(text: 'Fingerprint ${trust.fingerprint}'),
          const HeadingBlock(level: 2, text: 'Counts'),
          TextBlock(
            text:
                'Subjects ${trust.subjectCount}, digests ${trust.digestCount}, signatures ${trust.signatureCount}, attestations ${trust.attestationCount}',
          ),
          TextBlock(
            text:
                'Trust anchors ${trust.trustAnchorCount}, chains ${trust.trustChainCount}, policies ${trust.policyCount}',
          ),
          TextBlock(
            text:
                'Revocations ${trust.revocationCount}, transparency refs ${trust.transparencyReferenceCount}, issues ${trust.issueCount}',
          ),
          if (trust.limitations.isNotEmpty) ...[
            const HeadingBlock(level: 2, text: 'Limitations'),
            ListBlock(items: _items(trust.limitations)),
          ],
          if (trust.warnings.isNotEmpty) ...[
            const HeadingBlock(level: 2, text: 'Warnings'),
            ListBlock(items: _items(trust.warnings)),
          ],
        ],
      ),
      _cryptographicTrustListSection(
        id: 'cryptographic-trust-subjects',
        title: 'Subjects',
        summaries: trust.subjectSummaries,
        count: trust.subjectCount,
      ),
      _cryptographicTrustListSection(
        id: 'cryptographic-trust-digests',
        title: 'Digests',
        summaries: trust.digestSummaries,
        count: trust.digestCount,
      ),
      _cryptographicTrustListSection(
        id: 'cryptographic-trust-signatures',
        title: 'Signatures',
        summaries: trust.signatureSummaries,
        count: trust.signatureCount,
      ),
      _cryptographicTrustListSection(
        id: 'cryptographic-trust-attestations',
        title: 'Attestations',
        summaries: trust.attestationSummaries,
        count: trust.attestationCount,
      ),
      _cryptographicTrustListSection(
        id: 'cryptographic-trust-anchors',
        title: 'Trust Anchors',
        summaries: trust.trustAnchorSummaries,
        count: trust.trustAnchorCount,
      ),
      _cryptographicTrustListSection(
        id: 'cryptographic-trust-chains',
        title: 'Trust Chains',
        summaries: trust.trustChainSummaries,
        count: trust.trustChainCount,
      ),
      _cryptographicTrustListSection(
        id: 'cryptographic-trust-verification',
        title: 'Verification',
        summaries: trust.verificationSummaries,
        count: trust.verificationResultCount,
      ),
      _cryptographicTrustListSection(
        id: 'cryptographic-trust-policies',
        title: 'Policies',
        summaries: trust.policySummaries,
        count: trust.policyCount,
      ),
      _cryptographicTrustListSection(
        id: 'cryptographic-trust-revocations',
        title: 'Revocations',
        summaries: trust.revocationSummaries,
        count: trust.revocationCount,
      ),
      _cryptographicTrustListSection(
        id: 'cryptographic-trust-transparency',
        title: 'Transparency',
        summaries: trust.transparencySummaries,
        count: trust.transparencyReferenceCount,
      ),
      _cryptographicTrustListSection(
        id: 'cryptographic-trust-issues',
        title: 'Issues',
        summaries: trust.issueSummaries,
        count: trust.issueCount,
      ),
      _cryptographicTrustListSection(
        id: 'cryptographic-trust-sources',
        title: 'Source References',
        summaries: trust.sourceSummaries,
        count: trust.sourceReferenceCount,
      ),
    ];
  }

  ReportSection _cryptographicTrustListSection({
    required String id,
    required String title,
    required List<String> summaries,
    required int count,
  }) {
    return ReportSection(
      id: id,
      title: title,
      blocks: [
        TextBlock(text: 'Count: $count'),
        if (summaries.isNotEmpty)
          ListBlock(items: _items(summaries))
        else
          const TextBlock(text: 'No entries'),
      ],
    );
  }

  ReportSection _dashboardSection(DashboardReportInputData dashboard) {
    return ReportSection(
      id: 'engineering-dashboard-summary',
      title: 'Engineering Dashboard',
      blocks: [
        const HeadingBlock(level: 2, text: 'Engineering Dashboard'),
        SummaryBlock(
          text:
              'Snapshot ${dashboard.dashboardSnapshotId} — status ${dashboard.status}',
        ),
        TextBlock(
          text:
              'Freshness: ${dashboard.freshness}, compatibility: ${dashboard.compatibility}',
        ),
        if (dashboard.projectBranch != null)
          TextBlock(text: 'Branch: ${dashboard.projectBranch}'),
        if (dashboard.projectGitRef != null)
          TextBlock(text: 'Git ref: ${dashboard.projectGitRef}'),
        const HeadingBlock(level: 3, text: 'Sections'),
        ListBlock(items: _items(dashboard.sectionSummaries)),
        const HeadingBlock(level: 3, text: 'Sources'),
        ListBlock(items: _items(dashboard.sourceSummaries)),
        if (dashboard.limitations.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Limitations'),
          ListBlock(items: _items(dashboard.limitations)),
        ],
      ],
    );
  }

  ReportSection _persistentArtifactsSection(
    PersistentArtifactReportInputData data,
  ) {
    return ReportSection(
      id: 'persistent-artifacts-summary',
      title: 'Persistent Artifacts',
      blocks: [
        const HeadingBlock(level: 2, text: 'Persistent Artifacts'),
        SummaryBlock(
          text:
              'Snapshot ${data.snapshotId} — status ${data.status} (declarative boundaries).',
        ),
        TextBlock(text: 'Project ${data.projectId}, release ${data.releaseId}'),
        TextBlock(
          text:
              'Subjects ${data.subjectCount}, sources ${data.sourceCount}, policies ${data.policyCount}, operations ${data.operationCount}',
        ),
        if (data.limitations.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Limitations'),
          ListBlock(items: _items(data.limitations)),
        ],
        if (data.warnings.isNotEmpty) ...[
          const HeadingBlock(level: 3, text: 'Warnings'),
          ListBlock(items: _items(data.warnings)),
        ],
      ],
    );
  }

  ReportSection _graphSection(GraphReportInputData graph) {
    return ReportSection(
      id: 'graph-summary',
      title: 'Graph Summary',
      blocks: [
        const HeadingBlock(level: 2, text: 'Graph Summary'),
        TextBlock(
          text: 'Nodes: ${graph.nodeCount}, edges: ${graph.edgeCount}',
        ),
        ListBlock(
          items: graph.topConnectedNodes.isEmpty
              ? const ['Nenhum nó altamente conectado']
              : graph.topConnectedNodes
                  .map((n) => 'Highly connected: $n')
                  .toList(),
        ),
      ],
    );
  }

  List<String> _items(List<String> items) =>
      items.isEmpty ? const ['(nenhum)'] : items;

  ReportSection _guardianSummarySection(GuardianReportInputData guardian) {
    return ReportSection(
      id: 'guardian-summary',
      title: 'Guardian Summary',
      blocks: [
        const HeadingBlock(level: 2, text: 'Guardian Summary'),
        SummaryBlock(text: guardian.summary),
        DecisionBlock(
          decision: guardian.decision,
          simulationOnly: guardian.simulationOnly,
        ),
      ],
    );
  }

  List<ReportSection> _guardianFullSections(GuardianReportInputData g) {
    return [
      ReportSection(
        id: 'guardian-overview',
        title: 'Guardian Report',
        blocks: [
          const HeadingBlock(level: 1, text: 'Guardian Report'),
          const HeadingBlock(level: 2, text: 'Resumo'),
          SummaryBlock(text: g.summary),
          DecisionBlock(decision: g.decision, simulationOnly: g.simulationOnly),
          TextBlock(text: 'Decisão: ${g.decision.toUpperCase()}'),
          TextBlock(text: 'Modo simulação: ${g.simulationOnly}'),
        ],
      ),
      ReportSection(
        id: 'guardian-files',
        title: 'Arquivos alterados',
        blocks: [
          const HeadingBlock(level: 2, text: 'Arquivos alterados'),
          const HeadingBlock(level: 3, text: 'Adicionados'),
          ListBlock(items: _items(g.filesAdded)),
          const HeadingBlock(level: 3, text: 'Modificados'),
          ListBlock(items: _items(g.filesModified)),
          const HeadingBlock(level: 3, text: 'Removidos'),
          ListBlock(items: _items(g.filesRemoved)),
        ],
      ),
      ReportSection(
        id: 'guardian-impact',
        title: 'Impacto',
        blocks: [
          const HeadingBlock(level: 2, text: 'Áreas impactadas'),
          ListBlock(items: _items(g.domains)),
          const HeadingBlock(level: 2, text: 'Serviços'),
          ListBlock(items: _items(g.services)),
          const HeadingBlock(level: 2, text: 'Telas'),
          ListBlock(items: _items(g.screens.take(20).toList())),
          const HeadingBlock(level: 2, text: 'Collections Firestore'),
          ListBlock(items: _items(g.firestoreCollections)),
          const HeadingBlock(level: 2, text: 'Boxes Hive'),
          ListBlock(items: _items(g.hiveBoxes)),
        ],
      ),
      ReportSection(
        id: 'guardian-risk',
        title: 'Risco',
        blocks: [
          const HeadingBlock(level: 2, text: 'Risco por item'),
          TableBlock(
            table: ReportTable(
              columns: const [
                ReportTableColumn(id: 'file', label: 'Ficheiro'),
                ReportTableColumn(id: 'level', label: 'Nível'),
                ReportTableColumn(id: 'reason', label: 'Motivo'),
              ],
              rows: g.riskItems
                  .map(
                    (item) => ReportTableRow(
                      cells: [
                        item['file']?.toString() ?? '',
                        item['level']?.toString() ?? '',
                        item['reason']?.toString() ?? '',
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
      ReportSection(
        id: 'guardian-violations',
        title: 'Violações',
        blocks: [
          const HeadingBlock(level: 2, text: 'Violações de regras'),
          ...g.violations.map((v) {
            return FindingBlock(
              finding: ReportFinding(
                code: v['code']?.toString() ?? 'UNKNOWN',
                message: v['message']?.toString() ?? '',
                severity: _mapSeverity(v['severity']?.toString()),
                source: v['file']?.toString(),
                details: {
                  if (v['evidence'] != null)
                    'evidence': v['evidence'].toString(),
                  if (v['required_action'] != null)
                    'required_action': v['required_action'].toString(),
                },
              ),
            );
          }),
        ],
      ),
      ReportSection(
        id: 'guardian-tests',
        title: 'Testes',
        blocks: [
          const HeadingBlock(level: 2, text: 'Testes obrigatórios'),
          ListBlock(items: _items(g.requiredTests)),
          const HeadingBlock(level: 2, text: 'Testes encontrados'),
          ListBlock(items: _items(g.foundTests.take(30).toList())),
          const HeadingBlock(level: 2, text: 'Testes ausentes'),
          ListBlock(
            items: g.missingTests.isEmpty
                ? const ['Nenhum ausente identificado']
                : g.missingTests,
          ),
        ],
      ),
      ReportSection(
        id: 'guardian-docs',
        title: 'Documentação',
        blocks: [
          const HeadingBlock(level: 2, text: 'Documentação obrigatória'),
          ListBlock(items: _items(g.requiredDocumentation)),
          const HeadingBlock(level: 2, text: 'Recomendações'),
          ListBlock(items: _items(g.recommendations)),
          const HeadingBlock(level: 2, text: 'Decisão'),
          TextBlock(text: g.decision.toUpperCase()),
        ],
      ),
    ];
  }

  ReportSeverity _mapSeverity(String? value) {
    switch (value) {
      case 'blocking':
        return ReportSeverity.critical;
      case 'red':
        return ReportSeverity.high;
      case 'yellow':
        return ReportSeverity.medium;
      case 'info':
        return ReportSeverity.info;
      default:
        return ReportSeverity.low;
    }
  }
}
