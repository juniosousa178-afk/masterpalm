class PersistentArtifactBackendPromotionCriteria {
  const PersistentArtifactBackendPromotionCriteria({
    this.requireManualApprovalForStaging = true,
    this.requireGoldenStability = true,
    this.requireFingerprintStability = true,
    this.requireNoBootstrapRegistration = true,
    this.requireProductionBlock = true,
    this.metadata = const {},
  });

  final bool requireManualApprovalForStaging;
  final bool requireGoldenStability;
  final bool requireFingerprintStability;
  final bool requireNoBootstrapRegistration;
  final bool requireProductionBlock;
  final Map<String, String> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requireManualApprovalForStaging': requireManualApprovalForStaging,
      'requireGoldenStability': requireGoldenStability,
      'requireFingerprintStability': requireFingerprintStability,
      'requireNoBootstrapRegistration': requireNoBootstrapRegistration,
      'requireProductionBlock': requireProductionBlock,
      'metadata': metadata,
    };
  }
}
