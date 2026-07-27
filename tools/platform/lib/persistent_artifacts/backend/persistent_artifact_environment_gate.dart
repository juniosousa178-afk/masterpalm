import 'persistent_artifact_backend_environment.dart';
import 'persistent_artifact_backend_environment_decision.dart';

enum PersistentArtifactRuntimeEnvironment {
  test,
  development,
  localReference,
  staging,
  production,
}

class PersistentArtifactEnvironmentGate {
  const PersistentArtifactEnvironmentGate({
    this.allowStagingByDefault = false,
  });

  final bool allowStagingByDefault;

  PersistentArtifactBackendEnvironmentDecision evaluate({
    required PersistentArtifactBackendEnvironment environment,
    required PersistentArtifactRuntimeEnvironment runtimeEnvironment,
  }) {
    switch (runtimeEnvironment) {
      case PersistentArtifactRuntimeEnvironment.production:
        return PersistentArtifactBackendEnvironmentDecision.blockedDecision(
          environment: environment,
          reasonCode: 'production-blocked',
          message: 'Physical backend usage is blocked in production',
        );
      case PersistentArtifactRuntimeEnvironment.staging:
        if (!allowStagingByDefault || !environment.stagingEligible) {
          return PersistentArtifactBackendEnvironmentDecision.blockedDecision(
            environment: environment,
            reasonCode: 'staging-blocked',
            message: 'Staging requires explicit allow-list',
            metadata: const {'allowStagingByDefault': 'false'},
          );
        }
        return PersistentArtifactBackendEnvironmentDecision.allowedDecision(
          environment: environment,
        );
      case PersistentArtifactRuntimeEnvironment.localReference:
        if (!environment.localReference) {
          return PersistentArtifactBackendEnvironmentDecision.blockedDecision(
            environment: environment,
            reasonCode: 'local-reference-rejected',
            message: 'Backend is not local-reference compatible',
          );
        }
        return PersistentArtifactBackendEnvironmentDecision.allowedDecision(
          environment: environment,
        );
      case PersistentArtifactRuntimeEnvironment.development:
        if (!environment.development) {
          return PersistentArtifactBackendEnvironmentDecision.blockedDecision(
            environment: environment,
            reasonCode: 'development-rejected',
            message: 'Backend is not development compatible',
          );
        }
        return PersistentArtifactBackendEnvironmentDecision.allowedDecision(
          environment: environment,
        );
      case PersistentArtifactRuntimeEnvironment.test:
        if (!environment.test &&
            !environment.development &&
            !environment.localReference) {
          return PersistentArtifactBackendEnvironmentDecision.blockedDecision(
            environment: environment,
            reasonCode: 'test-rejected',
            message: 'Backend is not test compatible',
          );
        }
        return PersistentArtifactBackendEnvironmentDecision.allowedDecision(
          environment: environment,
        );
    }
  }
}
