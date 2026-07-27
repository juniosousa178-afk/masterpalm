import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_enums.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_models.dart'
    show PersistentArtifactCloudIssue;

/// Documental closure gate for Sprint 05.3.2 cloud framework.
///
/// Does not authorize adapter work, staging, production, SDK or release.
class CloudFrameworkClosureGate {
  const CloudFrameworkClosureGate({
    required this.platformFormatPassed,
    required this.platformAnalyzePassed,
    required this.platformCloudTestsPassed,
    required this.platformPersistentArtifactTestsPassed,
    required this.platformFullSuitePassed,
    required this.guardianFormatPassed,
    required this.guardianAnalyzePassed,
    required this.guardianTestsPassed,
    required this.guardianTargetedAnalysisPassed,
    required this.guardianTargetedAnalysisComplete,
    required this.guardianTargetedDeterministic,
    required this.guardianTargetedFiles,
    required this.guardianTargetedUnresolved,
    required this.guardianTargetedFingerprint,
    required this.guardianRepositoryAnalysisStatus,
    required this.repositoryFindingsAttributed,
    required this.silentExclusionTestPassed,
    required this.cloudBootstrapEmpty,
    required this.realCloudBridgeAbsent,
    required this.networkAbsent,
    required this.sdkAbsent,
    required this.credentialsAbsent,
    required this.stagingBlocked,
    required this.productionBlocked,
    required this.admissionStatus,
    required this.manualApprovalReferencePresent,
    required this.realAdapterWorkAuthorized,
    this.issues = const [],
    this.decision = CloudFrameworkClosureDecision.notReady,
    this.metadata = const {},
  });

  final bool platformFormatPassed;
  final bool platformAnalyzePassed;
  final bool platformCloudTestsPassed;
  final bool platformPersistentArtifactTestsPassed;
  final bool platformFullSuitePassed;
  final bool guardianFormatPassed;
  final bool guardianAnalyzePassed;
  final bool guardianTestsPassed;
  final bool guardianTargetedAnalysisPassed;
  final bool guardianTargetedAnalysisComplete;
  final bool guardianTargetedDeterministic;
  final int guardianTargetedFiles;
  final int guardianTargetedUnresolved;
  final String guardianTargetedFingerprint;
  final String guardianRepositoryAnalysisStatus;
  final bool repositoryFindingsAttributed;
  final bool silentExclusionTestPassed;
  final bool cloudBootstrapEmpty;
  final bool realCloudBridgeAbsent;
  final bool networkAbsent;
  final bool sdkAbsent;
  final bool credentialsAbsent;
  final bool stagingBlocked;
  final bool productionBlocked;
  final RealCloudAdapterAdmissionStatus admissionStatus;
  final bool manualApprovalReferencePresent;
  final bool realAdapterWorkAuthorized;
  final List<PersistentArtifactCloudIssue> issues;
  final CloudFrameworkClosureDecision decision;
  final Map<String, String> metadata;

  Map<String, dynamic> toComparableJson() => {
        'platformFormatPassed': platformFormatPassed,
        'platformAnalyzePassed': platformAnalyzePassed,
        'platformCloudTestsPassed': platformCloudTestsPassed,
        'platformPersistentArtifactTestsPassed':
            platformPersistentArtifactTestsPassed,
        'platformFullSuitePassed': platformFullSuitePassed,
        'guardianFormatPassed': guardianFormatPassed,
        'guardianAnalyzePassed': guardianAnalyzePassed,
        'guardianTestsPassed': guardianTestsPassed,
        'guardianTargetedAnalysisPassed': guardianTargetedAnalysisPassed,
        'guardianTargetedAnalysisComplete': guardianTargetedAnalysisComplete,
        'guardianTargetedDeterministic': guardianTargetedDeterministic,
        'guardianTargetedFiles': guardianTargetedFiles,
        'guardianTargetedUnresolved': guardianTargetedUnresolved,
        'guardianTargetedFingerprint': guardianTargetedFingerprint,
        'guardianRepositoryAnalysisStatus': guardianRepositoryAnalysisStatus,
        'repositoryFindingsAttributed': repositoryFindingsAttributed,
        'silentExclusionTestPassed': silentExclusionTestPassed,
        'cloudBootstrapEmpty': cloudBootstrapEmpty,
        'realCloudBridgeAbsent': realCloudBridgeAbsent,
        'networkAbsent': networkAbsent,
        'sdkAbsent': sdkAbsent,
        'credentialsAbsent': credentialsAbsent,
        'stagingBlocked': stagingBlocked,
        'productionBlocked': productionBlocked,
        'admissionStatus': admissionStatus.wireName,
        'manualApprovalReferencePresent': manualApprovalReferencePresent,
        'realAdapterWorkAuthorized': realAdapterWorkAuthorized,
        'decision': decision.wireName,
        if (issues.isNotEmpty)
          'issues': issues.map((e) => e.toComparableJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };
}

enum CloudFrameworkClosureDecision {
  notReady,
  blocked,
  goWithConditions,
}

extension CloudFrameworkClosureDecisionX on CloudFrameworkClosureDecision {
  String get wireName => name;
}
