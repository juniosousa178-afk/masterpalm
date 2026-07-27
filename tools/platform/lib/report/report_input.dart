import '../models/report/report_type.dart';

/// Normalized AST data for report composition.
class AstReportInputData {
  const AstReportInputData({
    required this.filesAnalyzed,
    required this.totalClasses,
    required this.totalMethods,
    required this.firestoreWrites,
    required this.firestoreReads,
    required this.widgetClasses,
    required this.serviceFiles,
  });

  final int filesAnalyzed;
  final int totalClasses;
  final int totalMethods;
  final int firestoreWrites;
  final int firestoreReads;
  final int widgetClasses;
  final int serviceFiles;
}

/// Normalized Guardian data for report composition.
class GuardianReportInputData {
  const GuardianReportInputData({
    required this.summary,
    required this.decision,
    required this.simulationOnly,
    required this.domains,
    required this.riskOverall,
    required this.violations,
    required this.requiredTests,
    required this.missingTests,
    required this.filesAdded,
    required this.filesModified,
    required this.filesRemoved,
    required this.riskItems,
    required this.recommendations,
    required this.services,
    required this.screens,
    required this.firestoreCollections,
    required this.hiveBoxes,
    required this.foundTests,
    required this.requiredDocumentation,
    required this.methodsChanged,
    required this.classesChanged,
  });

  final String summary;
  final String decision;
  final bool simulationOnly;
  final List<String> domains;
  final String riskOverall;
  final List<Map<String, dynamic>> violations;
  final List<String> requiredTests;
  final List<String> missingTests;
  final List<String> filesAdded;
  final List<String> filesModified;
  final List<String> filesRemoved;
  final List<Map<String, dynamic>> riskItems;
  final List<String> recommendations;
  final List<String> services;
  final List<String> screens;
  final List<String> firestoreCollections;
  final List<String> hiveBoxes;
  final List<String> foundTests;
  final List<String> requiredDocumentation;
  final List<String> methodsChanged;
  final List<String> classesChanged;
}

/// Normalized Graph data for report composition.
class GraphReportInputData {
  const GraphReportInputData({
    required this.nodeCount,
    required this.edgeCount,
    required this.nodeTypes,
    required this.edgeTypes,
    required this.topConnectedNodes,
  });

  final int nodeCount;
  final int edgeCount;
  final Map<String, int> nodeTypes;
  final Map<String, int> edgeTypes;
  final List<String> topConnectedNodes;
}

/// Normalized Metrics data for report composition.
class MetricsReportInputData {
  const MetricsReportInputData({
    required this.snapshotId,
    required this.metricCount,
    required this.availableCount,
    required this.unavailableCount,
    required this.highlights,
  });

  final String snapshotId;
  final int metricCount;
  final int availableCount;
  final int unavailableCount;
  final List<String> highlights;
}

/// Normalized History diff data for report composition.
class HistoryDiffReportInputData {
  const HistoryDiffReportInputData({
    required this.fromSnapshotId,
    required this.toSnapshotId,
    required this.compatibilityStatus,
    required this.totalChanges,
    required this.addedCount,
    required this.removedCount,
    required this.changedCount,
    required this.highlights,
  });

  final String fromSnapshotId;
  final String toSnapshotId;
  final String compatibilityStatus;
  final int totalChanges;
  final int addedCount;
  final int removedCount;
  final int changedCount;
  final List<String> highlights;
}

/// Normalized engineering score data for report composition.
class EngineeringScoreReportInputData {
  const EngineeringScoreReportInputData({
    required this.scoreSnapshotId,
    required this.policyId,
    required this.policyVersion,
    required this.overallScore,
    required this.status,
    required this.confidence,
    required this.coveragePercentage,
    required this.dimensionSummaries,
    required this.limitations,
  });

  final String scoreSnapshotId;
  final String policyId;
  final int policyVersion;
  final double overallScore;
  final String status;
  final String confidence;
  final double coveragePercentage;
  final List<String> dimensionSummaries;
  final List<String> limitations;
}

/// Normalized MES data for report composition.
class MESReportInputData {
  const MESReportInputData({
    required this.mesSnapshotId,
    required this.officialName,
    required this.acronym,
    required this.policyId,
    required this.policyVersion,
    required this.policyStatus,
    required this.mesValue,
    required this.status,
    required this.eligibility,
    required this.confidence,
    required this.policyCoverage,
    required this.evidenceCoverage,
    required this.dimensionSummaries,
    required this.limitations,
    required this.sourceEngineeringScoreSnapshotId,
    this.bandId,
  });

  final String mesSnapshotId;
  final String officialName;
  final String acronym;
  final String policyId;
  final int policyVersion;
  final String policyStatus;
  final double mesValue;
  final String status;
  final String eligibility;
  final String confidence;
  final double policyCoverage;
  final double evidenceCoverage;
  final List<String> dimensionSummaries;
  final List<String> limitations;
  final String sourceEngineeringScoreSnapshotId;
  final String? bandId;
}

/// Normalized dashboard data for report composition.
class DashboardReportInputData {
  const DashboardReportInputData({
    required this.dashboardSnapshotId,
    required this.status,
    required this.freshness,
    required this.compatibility,
    required this.sectionSummaries,
    required this.sourceSummaries,
    required this.limitations,
    this.projectBranch,
    this.projectGitRef,
  });

  final String dashboardSnapshotId;
  final String status;
  final String freshness;
  final String compatibility;
  final List<String> sectionSummaries;
  final List<String> sourceSummaries;
  final List<String> limitations;
  final String? projectBranch;
  final String? projectGitRef;
}

/// Normalized observability data for report composition.
class ObservabilityReportInputData {
  const ObservabilityReportInputData({
    required this.telemetrySnapshotId,
    required this.status,
    required this.compatibility,
    required this.eventCount,
    required this.operationCount,
    required this.successCount,
    required this.failureCount,
    required this.incompleteOperationCount,
    required this.totalDurationMicroseconds,
    required this.averageDurationMicroseconds,
    required this.minDurationMicroseconds,
    required this.maxDurationMicroseconds,
    required this.eventCoveragePercentage,
    required this.terminalCoveragePercentage,
    required this.conflictCount,
    required this.componentSummaries,
    required this.operationSummaries,
    required this.sourceSummaries,
    required this.limitations,
    required this.warnings,
    required this.errors,
    this.projectId,
    this.correlationId,
  });

  final String telemetrySnapshotId;
  final String status;
  final String compatibility;
  final int eventCount;
  final int operationCount;
  final int successCount;
  final int failureCount;
  final int incompleteOperationCount;
  final int totalDurationMicroseconds;
  final int averageDurationMicroseconds;
  final int minDurationMicroseconds;
  final int maxDurationMicroseconds;
  final double eventCoveragePercentage;
  final double terminalCoveragePercentage;
  final int conflictCount;
  final List<String> componentSummaries;
  final List<String> operationSummaries;
  final List<String> sourceSummaries;
  final List<String> limitations;
  final List<String> warnings;
  final List<String> errors;
  final String? projectId;
  final String? correlationId;
}

/// Normalized quality gate data for report composition.
class QualityGateReportInputData {
  const QualityGateReportInputData({
    required this.qualityGateSnapshotId,
    required this.qualityGateFingerprint,
    required this.decision,
    required this.policyId,
    required this.policyVersion,
    required this.projectId,
    required this.eligibility,
    required this.compatibility,
    required this.evaluatedRuleCount,
    required this.failedRuleCount,
    required this.blockingFailureCount,
    required this.requiredRuleCoveragePercentage,
    required this.overallRuleCoveragePercentage,
    required this.failedRules,
    required this.passedRules,
    required this.unavailableRules,
    required this.ruleSetSummaries,
    required this.sourceSummaries,
    required this.limitations,
    required this.warnings,
    required this.errors,
    this.commitId,
  });

  final String qualityGateSnapshotId;
  final String qualityGateFingerprint;
  final String decision;
  final String policyId;
  final int policyVersion;
  final String projectId;
  final String? commitId;
  final String eligibility;
  final String compatibility;
  final int evaluatedRuleCount;
  final int failedRuleCount;
  final int blockingFailureCount;
  final double requiredRuleCoveragePercentage;
  final double overallRuleCoveragePercentage;
  final List<String> failedRules;
  final List<String> passedRules;
  final List<String> unavailableRules;
  final List<String> ruleSetSummaries;
  final List<String> sourceSummaries;
  final List<String> limitations;
  final List<String> warnings;
  final List<String> errors;
}

/// Normalized release governance data for report composition.
class ReleaseGovernanceReportInputData {
  const ReleaseGovernanceReportInputData({
    required this.snapshotId,
    required this.fingerprint,
    required this.decision,
    required this.policyId,
    required this.policyVersion,
    required this.projectId,
    required this.releaseId,
    required this.releaseVersion,
    required this.commitId,
    required this.branch,
    required this.environment,
    required this.releaseType,
    required this.qualityGateSnapshotId,
    required this.qualityGateFingerprint,
    required this.compatibility,
    required this.eligibility,
    required this.requiredRuleCoveragePercentage,
    required this.overallRuleCoveragePercentage,
    required this.failedRules,
    required this.passedRules,
    required this.waivedRules,
    required this.approvalSummaries,
    required this.pendingApprovals,
    required this.rejectedApprovals,
    required this.waiverSummaries,
    required this.activeWaivers,
    required this.invalidWaivers,
    required this.openConditions,
    required this.evidenceSummaries,
    required this.sourceSummaries,
    required this.limitations,
    required this.warnings,
    required this.errors,
    this.resultStatus,
  });

  final String snapshotId;
  final String fingerprint;
  final String decision;
  final String? resultStatus;
  final String policyId;
  final int policyVersion;
  final String projectId;
  final String releaseId;
  final String releaseVersion;
  final String commitId;
  final String branch;
  final String environment;
  final String releaseType;
  final String qualityGateSnapshotId;
  final String qualityGateFingerprint;
  final String compatibility;
  final String eligibility;
  final double requiredRuleCoveragePercentage;
  final double overallRuleCoveragePercentage;
  final List<String> failedRules;
  final List<String> passedRules;
  final List<String> waivedRules;
  final List<String> approvalSummaries;
  final List<String> pendingApprovals;
  final List<String> rejectedApprovals;
  final List<String> waiverSummaries;
  final List<String> activeWaivers;
  final List<String> invalidWaivers;
  final List<String> openConditions;
  final List<String> evidenceSummaries;
  final List<String> sourceSummaries;
  final List<String> limitations;
  final List<String> warnings;
  final List<String> errors;
}

/// Normalized release evidence data for report composition.
class ReleaseEvidenceReportInputData {
  const ReleaseEvidenceReportInputData({
    required this.bundleId,
    required this.fingerprint,
    required this.policyId,
    required this.policyVersion,
    required this.projectId,
    required this.releaseId,
    required this.releaseVersion,
    required this.commitId,
    required this.environment,
    required this.compatibility,
    required this.eligibility,
    required this.evidenceCount,
    required this.attestationCount,
    required this.evidenceCoveragePercentage,
    required this.attestationCoveragePercentage,
    required this.provenanceCoveragePercentage,
    required this.qualityGateSnapshotId,
    required this.qualityGateDecision,
    required this.releaseDecisionSnapshotId,
    required this.releaseDecision,
    required this.evidenceSummaries,
    required this.attestationSummaries,
    required this.provenanceSummaries,
    required this.sourceSummaries,
    required this.limitations,
    required this.warnings,
    required this.errors,
  });

  final String bundleId;
  final String fingerprint;
  final String policyId;
  final int policyVersion;
  final String projectId;
  final String releaseId;
  final String releaseVersion;
  final String commitId;
  final String environment;
  final String compatibility;
  final String eligibility;
  final int evidenceCount;
  final int attestationCount;
  final double evidenceCoveragePercentage;
  final double attestationCoveragePercentage;
  final double provenanceCoveragePercentage;
  final String qualityGateSnapshotId;
  final String qualityGateDecision;
  final String releaseDecisionSnapshotId;
  final String releaseDecision;
  final List<String> evidenceSummaries;
  final List<String> attestationSummaries;
  final List<String> provenanceSummaries;
  final List<String> sourceSummaries;
  final List<String> limitations;
  final List<String> warnings;
  final List<String> errors;
}

/// Typed release supply chain input for report generation.
class ReleaseSupplyChainReportInputData {
  const ReleaseSupplyChainReportInputData({
    required this.snapshotId,
    required this.fingerprint,
    required this.projectId,
    required this.releaseId,
    required this.commitId,
    required this.releaseEvidenceBundleId,
    required this.supplyChainPolicyId,
    required this.supplyChainPolicyVersion,
    required this.distributionPolicyId,
    required this.distributionPolicyVersion,
    required this.compliancePolicyId,
    required this.compliancePolicyVersion,
    required this.supplyChainStatus,
    required this.sbomStatus,
    required this.sbomComponentCount,
    required this.sbomDependencyCount,
    required this.complianceStatus,
    required this.complianceCheckCount,
    required this.complianceViolationCount,
    required this.artifactCount,
    required this.artifactSummaries,
    required this.complianceCheckSummaries,
    required this.complianceViolationSummaries,
    required this.limitations,
    required this.warnings,
  });

  final String snapshotId;
  final String fingerprint;
  final String projectId;
  final String releaseId;
  final String commitId;
  final String releaseEvidenceBundleId;
  final String supplyChainPolicyId;
  final int supplyChainPolicyVersion;
  final String distributionPolicyId;
  final int distributionPolicyVersion;
  final String compliancePolicyId;
  final int compliancePolicyVersion;
  final String supplyChainStatus;
  final String sbomStatus;
  final int sbomComponentCount;
  final int sbomDependencyCount;
  final String complianceStatus;
  final int complianceCheckCount;
  final int complianceViolationCount;
  final int artifactCount;
  final List<String> artifactSummaries;
  final List<String> complianceCheckSummaries;
  final List<String> complianceViolationSummaries;
  final List<String> limitations;
  final List<String> warnings;
}

class CicdIntegrationReportInputData {
  const CicdIntegrationReportInputData({
    required this.snapshotId,
    required this.fingerprint,
    required this.projectId,
    required this.releaseId,
    required this.pipelineDefinitionId,
    required this.pipelineExecutionId,
    required this.deploymentPlanId,
    required this.releaseEvidenceBundleId,
    required this.releaseSupplyChainSnapshotId,
    required this.pipelineIntegrationPolicyId,
    required this.pipelineIntegrationPolicyVersion,
    required this.pipelineExecutionPolicyId,
    required this.pipelineExecutionPolicyVersion,
    required this.deploymentIntegrationPolicyId,
    required this.deploymentIntegrationPolicyVersion,
    required this.snapshotStatus,
    required this.pipelineStageCount,
    required this.pipelineExecutionStatus,
    required this.executionResultOutcome,
    required this.deploymentPlanTargetCount,
    required this.deploymentResultStatus,
    required this.sourceReferenceCount,
    required this.sourceSummaries,
    required this.stageSummaries,
    required this.targetSummaries,
    required this.limitations,
    required this.warnings,
  });

  final String snapshotId;
  final String fingerprint;
  final String projectId;
  final String releaseId;
  final String pipelineDefinitionId;
  final String pipelineExecutionId;
  final String deploymentPlanId;
  final String releaseEvidenceBundleId;
  final String releaseSupplyChainSnapshotId;
  final String pipelineIntegrationPolicyId;
  final int pipelineIntegrationPolicyVersion;
  final String pipelineExecutionPolicyId;
  final int pipelineExecutionPolicyVersion;
  final String deploymentIntegrationPolicyId;
  final int deploymentIntegrationPolicyVersion;
  final String snapshotStatus;
  final int pipelineStageCount;
  final String pipelineExecutionStatus;
  final String executionResultOutcome;
  final int deploymentPlanTargetCount;
  final String deploymentResultStatus;
  final int sourceReferenceCount;
  final List<String> sourceSummaries;
  final List<String> stageSummaries;
  final List<String> targetSummaries;
  final List<String> limitations;
  final List<String> warnings;
}

class CryptographicTrustReportInputData {
  const CryptographicTrustReportInputData({
    required this.snapshotId,
    required this.fingerprint,
    required this.projectId,
    required this.releaseId,
    required this.snapshotStatus,
    required this.subjectCount,
    required this.digestCount,
    required this.signatureCount,
    required this.attestationCount,
    required this.trustAnchorCount,
    required this.trustChainCount,
    required this.verificationResultCount,
    required this.policyCount,
    required this.revocationCount,
    required this.transparencyReferenceCount,
    required this.issueCount,
    required this.sourceReferenceCount,
    required this.subjectSummaries,
    required this.digestSummaries,
    required this.signatureSummaries,
    required this.attestationSummaries,
    required this.trustAnchorSummaries,
    required this.trustChainSummaries,
    required this.verificationSummaries,
    required this.policySummaries,
    required this.revocationSummaries,
    required this.transparencySummaries,
    required this.issueSummaries,
    required this.sourceSummaries,
    required this.limitations,
    required this.warnings,
  });

  final String snapshotId;
  final String fingerprint;
  final String projectId;
  final String releaseId;
  final String snapshotStatus;
  final int subjectCount;
  final int digestCount;
  final int signatureCount;
  final int attestationCount;
  final int trustAnchorCount;
  final int trustChainCount;
  final int verificationResultCount;
  final int policyCount;
  final int revocationCount;
  final int transparencyReferenceCount;
  final int issueCount;
  final int sourceReferenceCount;
  final List<String> subjectSummaries;
  final List<String> digestSummaries;
  final List<String> signatureSummaries;
  final List<String> attestationSummaries;
  final List<String> trustAnchorSummaries;
  final List<String> trustChainSummaries;
  final List<String> verificationSummaries;
  final List<String> policySummaries;
  final List<String> revocationSummaries;
  final List<String> transparencySummaries;
  final List<String> issueSummaries;
  final List<String> sourceSummaries;
  final List<String> limitations;
  final List<String> warnings;
}

class PersistentArtifactReportInputData {
  const PersistentArtifactReportInputData({
    required this.snapshotId,
    required this.projectId,
    required this.releaseId,
    required this.status,
    required this.subjectCount,
    required this.sourceCount,
    required this.policyCount,
    required this.operationCount,
    this.limitations = const [],
    this.warnings = const [],
  });

  final String snapshotId;
  final String projectId;
  final String releaseId;
  final String status;
  final int subjectCount;
  final int sourceCount;
  final int policyCount;
  final int operationCount;
  final List<String> limitations;
  final List<String> warnings;
}

/// Combined typed input for report generation.
class ReportInput {
  const ReportInput({
    required this.projectId,
    required this.reportType,
    this.ast,
    this.guardian,
    this.graph,
    this.metrics,
    this.history,
    this.engineeringScore,
    this.mes,
    this.dashboard,
    this.observability,
    this.qualityGate,
    this.releaseGovernance,
    this.releaseEvidence,
    this.releaseSupplyChain,
    this.cicdIntegration,
    this.cryptographicTrust,
    this.persistentArtifacts,
    this.warnings = const [],
    this.missingOptionalSources = const [],
    this.sourceSnapshotId,
    this.gitRef,
  });

  final String projectId;
  final ReportType reportType;
  final AstReportInputData? ast;
  final GuardianReportInputData? guardian;
  final GraphReportInputData? graph;
  final MetricsReportInputData? metrics;
  final HistoryDiffReportInputData? history;
  final EngineeringScoreReportInputData? engineeringScore;
  final MESReportInputData? mes;
  final DashboardReportInputData? dashboard;
  final ObservabilityReportInputData? observability;
  final QualityGateReportInputData? qualityGate;
  final ReleaseGovernanceReportInputData? releaseGovernance;
  final ReleaseEvidenceReportInputData? releaseEvidence;
  final ReleaseSupplyChainReportInputData? releaseSupplyChain;
  final CicdIntegrationReportInputData? cicdIntegration;
  final CryptographicTrustReportInputData? cryptographicTrust;
  final PersistentArtifactReportInputData? persistentArtifacts;
  final List<String> warnings;
  final List<String> missingOptionalSources;
  final String? sourceSnapshotId;
  final String? gitRef;

  List<String> fingerprintParts() {
    return [
      projectId,
      reportType.wireName,
      if (ast != null) 'ast:${ast!.filesAnalyzed}:${ast!.totalClasses}',
      if (guardian != null)
        'guardian:${guardian!.decision}:${guardian!.violations.length}',
      if (graph != null) 'graph:${graph!.nodeCount}:${graph!.edgeCount}',
      if (metrics != null)
        'metrics:${metrics!.metricCount}:${metrics!.availableCount}',
      if (history != null)
        'history:${history!.fromSnapshotId}:${history!.toSnapshotId}',
      if (engineeringScore != null)
        'score:${engineeringScore!.policyId}:${engineeringScore!.overallScore}',
      if (mes != null) 'mes:${mes!.policyId}:${mes!.mesValue}',
      if (dashboard != null)
        'dashboard:${dashboard!.dashboardSnapshotId}:${dashboard!.status}',
      if (observability != null)
        'observability:${observability!.telemetrySnapshotId}:${observability!.status}',
      if (qualityGate != null)
        'qualityGate:${qualityGate!.qualityGateSnapshotId}:${qualityGate!.decision}',
      if (releaseGovernance != null)
        'releaseGovernance:${releaseGovernance!.snapshotId}:${releaseGovernance!.decision}',
      if (releaseEvidence != null)
        'releaseEvidence:${releaseEvidence!.bundleId}:${releaseEvidence!.eligibility}',
      if (releaseSupplyChain != null)
        'releaseSupplyChain:${releaseSupplyChain!.snapshotId}:${releaseSupplyChain!.complianceStatus}',
      if (cicdIntegration != null)
        'cicdIntegration:${cicdIntegration!.snapshotId}:${cicdIntegration!.snapshotStatus}',
      if (cryptographicTrust != null)
        'cryptographicTrust:${cryptographicTrust!.snapshotId}:${cryptographicTrust!.snapshotStatus}',
      if (persistentArtifacts != null)
        'persistentArtifacts:${persistentArtifacts!.snapshotId}:${persistentArtifacts!.status}',
    ];
  }
}
