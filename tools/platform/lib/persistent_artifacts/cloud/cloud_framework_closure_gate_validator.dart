import 'cloud_framework_closure_gate.dart';

/// Pure validator for [CloudFrameworkClosureGate].
class CloudFrameworkClosureGateValidator {
  const CloudFrameworkClosureGateValidator();

  CloudFrameworkClosureValidationResult validate(
      CloudFrameworkClosureGate gate) {
    final blockers = <String>[];

    if (!gate.guardianTargetedAnalysisPassed) {
      blockers.add('guardian-targeted-analysis-not-passed');
    }
    if (!gate.guardianTargetedAnalysisComplete) {
      blockers.add('guardian-targeted-analysis-incomplete');
    }
    if (gate.guardianTargetedUnresolved > 0) {
      blockers.add('guardian-targeted-unresolved-imports');
    }
    if (!gate.guardianTargetedDeterministic) {
      blockers.add('guardian-targeted-not-deterministic');
    }
    if (!gate.silentExclusionTestPassed) {
      blockers.add('silent-exclusion-test-failed');
    }
    if (!gate.repositoryFindingsAttributed) {
      blockers.add('repository-findings-not-attributed');
    }
    if (!gate.networkAbsent) blockers.add('network-not-absent');
    if (!gate.sdkAbsent) blockers.add('sdk-not-absent');
    if (!gate.credentialsAbsent) blockers.add('credentials-not-absent');
    if (!gate.stagingBlocked) blockers.add('staging-not-blocked');
    if (!gate.productionBlocked) blockers.add('production-not-blocked');
    if (gate.realAdapterWorkAuthorized) {
      blockers.add('real-adapter-work-authorized');
    }
    if (!gate.platformAnalyzePassed) blockers.add('platform-analyze-failed');
    if (!gate.platformFullSuitePassed) {
      blockers.add('platform-full-suite-failed');
    }

    if (blockers.isNotEmpty) {
      return CloudFrameworkClosureValidationResult(
        allowed: false,
        decision: CloudFrameworkClosureDecision.blocked,
        blockers: blockers,
      );
    }

    return const CloudFrameworkClosureValidationResult(
      allowed: true,
      decision: CloudFrameworkClosureDecision.goWithConditions,
      blockers: [],
    );
  }
}

class CloudFrameworkClosureValidationResult {
  const CloudFrameworkClosureValidationResult({
    required this.allowed,
    required this.decision,
    required this.blockers,
  });

  final bool allowed;
  final CloudFrameworkClosureDecision decision;
  final List<String> blockers;
}
