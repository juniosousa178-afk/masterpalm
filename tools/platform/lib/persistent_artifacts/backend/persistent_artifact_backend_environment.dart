enum PersistentArtifactBackendEnvironmentClassification {
  test,
  development,
  localReference,
  stagingEligible,
  productionEligible,
}

class PersistentArtifactBackendEnvironment {
  const PersistentArtifactBackendEnvironment({
    required this.classification,
    required this.test,
    required this.development,
    required this.localReference,
    required this.stagingEligible,
    required this.productionEligible,
  });

  final PersistentArtifactBackendEnvironmentClassification classification;
  final bool test;
  final bool development;
  final bool localReference;
  final bool stagingEligible;
  final bool productionEligible;

  static const localReferenceOnly = PersistentArtifactBackendEnvironment(
    classification:
        PersistentArtifactBackendEnvironmentClassification.localReference,
    test: false,
    development: true,
    localReference: true,
    stagingEligible: false,
    productionEligible: false,
  );
}

class PersistentArtifactBackendEnvironmentContext {
  const PersistentArtifactBackendEnvironmentContext({
    this.isProduction = false,
  });

  final bool isProduction;

  static const nonProduction = PersistentArtifactBackendEnvironmentContext();
  static const production =
      PersistentArtifactBackendEnvironmentContext(isProduction: true);
}
