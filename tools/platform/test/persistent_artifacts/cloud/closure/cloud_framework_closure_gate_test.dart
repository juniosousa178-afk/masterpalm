import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  group('CloudFrameworkClosureGateValidator', () {
    const validator = CloudFrameworkClosureGateValidator();

    CloudFrameworkClosureGate readyGate() {
      return const CloudFrameworkClosureGate(
        platformFormatPassed: true,
        platformAnalyzePassed: true,
        platformCloudTestsPassed: true,
        platformPersistentArtifactTestsPassed: true,
        platformFullSuitePassed: true,
        guardianFormatPassed: true,
        guardianAnalyzePassed: true,
        guardianTestsPassed: true,
        guardianTargetedAnalysisPassed: true,
        guardianTargetedAnalysisComplete: true,
        guardianTargetedDeterministic: true,
        guardianTargetedFiles: 772,
        guardianTargetedUnresolved: 0,
        guardianTargetedFingerprint:
            '7ca8d89e21b9b15af0d7f0a6c48f268d099044beac5e34884b0190b6d3463666',
        guardianRepositoryAnalysisStatus: 'repository-findings-attributed',
        repositoryFindingsAttributed: true,
        silentExclusionTestPassed: true,
        cloudBootstrapEmpty: true,
        realCloudBridgeAbsent: true,
        networkAbsent: true,
        sdkAbsent: true,
        credentialsAbsent: true,
        stagingBlocked: true,
        productionBlocked: true,
        admissionStatus: RealCloudAdapterAdmissionStatus.notEvaluated,
        manualApprovalReferencePresent: false,
        realAdapterWorkAuthorized: false,
      );
    }

    test('goWithConditions when all closure checks pass', () {
      final result = validator.validate(readyGate());
      expect(result.allowed, isTrue);
      expect(result.decision, CloudFrameworkClosureDecision.goWithConditions);
      expect(result.blockers, isEmpty);
    });

    test('blocked when realAdapterWorkAuthorized is true', () {
      final gate = CloudFrameworkClosureGate(
        platformFormatPassed: readyGate().platformFormatPassed,
        platformAnalyzePassed: readyGate().platformAnalyzePassed,
        platformCloudTestsPassed: readyGate().platformCloudTestsPassed,
        platformPersistentArtifactTestsPassed:
            readyGate().platformPersistentArtifactTestsPassed,
        platformFullSuitePassed: readyGate().platformFullSuitePassed,
        guardianFormatPassed: readyGate().guardianFormatPassed,
        guardianAnalyzePassed: readyGate().guardianAnalyzePassed,
        guardianTestsPassed: readyGate().guardianTestsPassed,
        guardianTargetedAnalysisPassed:
            readyGate().guardianTargetedAnalysisPassed,
        guardianTargetedAnalysisComplete:
            readyGate().guardianTargetedAnalysisComplete,
        guardianTargetedDeterministic:
            readyGate().guardianTargetedDeterministic,
        guardianTargetedFiles: readyGate().guardianTargetedFiles,
        guardianTargetedUnresolved: readyGate().guardianTargetedUnresolved,
        guardianTargetedFingerprint: readyGate().guardianTargetedFingerprint,
        guardianRepositoryAnalysisStatus:
            readyGate().guardianRepositoryAnalysisStatus,
        repositoryFindingsAttributed: readyGate().repositoryFindingsAttributed,
        silentExclusionTestPassed: readyGate().silentExclusionTestPassed,
        cloudBootstrapEmpty: readyGate().cloudBootstrapEmpty,
        realCloudBridgeAbsent: readyGate().realCloudBridgeAbsent,
        networkAbsent: readyGate().networkAbsent,
        sdkAbsent: readyGate().sdkAbsent,
        credentialsAbsent: readyGate().credentialsAbsent,
        stagingBlocked: readyGate().stagingBlocked,
        productionBlocked: readyGate().productionBlocked,
        admissionStatus: readyGate().admissionStatus,
        manualApprovalReferencePresent:
            readyGate().manualApprovalReferencePresent,
        realAdapterWorkAuthorized: true,
      );
      final result = validator.validate(gate);
      expect(result.allowed, isFalse);
      expect(result.blockers, contains('real-adapter-work-authorized'));
    });

    test('blocked when targeted unresolved > 0', () {
      final gate = CloudFrameworkClosureGate(
        platformFormatPassed: true,
        platformAnalyzePassed: true,
        platformCloudTestsPassed: true,
        platformPersistentArtifactTestsPassed: true,
        platformFullSuitePassed: true,
        guardianFormatPassed: true,
        guardianAnalyzePassed: true,
        guardianTestsPassed: true,
        guardianTargetedAnalysisPassed: true,
        guardianTargetedAnalysisComplete: false,
        guardianTargetedDeterministic: true,
        guardianTargetedFiles: 772,
        guardianTargetedUnresolved: 1,
        guardianTargetedFingerprint: 'x',
        guardianRepositoryAnalysisStatus: 'attributed',
        repositoryFindingsAttributed: true,
        silentExclusionTestPassed: true,
        cloudBootstrapEmpty: true,
        realCloudBridgeAbsent: true,
        networkAbsent: true,
        sdkAbsent: true,
        credentialsAbsent: true,
        stagingBlocked: true,
        productionBlocked: true,
        admissionStatus: RealCloudAdapterAdmissionStatus.notEvaluated,
        manualApprovalReferencePresent: false,
        realAdapterWorkAuthorized: false,
      );
      final result = validator.validate(gate);
      expect(result.allowed, isFalse);
      expect(result.blockers, contains('guardian-targeted-unresolved-imports'));
    });

    test('repository-wide NOGO does not block when targeted clean', () {
      final gate = readyGate().toComparableJson();
      expect(gate['realAdapterWorkAuthorized'], isFalse);
      final result = validator.validate(readyGate());
      expect(result.allowed, isTrue);
    });
  });
}
