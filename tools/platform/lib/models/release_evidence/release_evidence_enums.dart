/// Release Evidence policy lifecycle status.
enum ReleaseEvidencePolicyStatus {
  draft,
  candidate,
  active,
  deprecated,
  retired,
}

extension ReleaseEvidencePolicyStatusX on ReleaseEvidencePolicyStatus {
  String get wireName => name;

  static ReleaseEvidencePolicyStatus fromWireName(String value) {
    return ReleaseEvidencePolicyStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseEvidencePolicyStatus: $value'),
    );
  }
}

/// Evidence reference status.
enum ReleaseEvidenceReferenceStatus {
  available,
  unavailable,
  incompatible,
  invalid,
  expired,
  superseded,
  unverified,
  verified,
  unknown,
}

extension ReleaseEvidenceReferenceStatusX on ReleaseEvidenceReferenceStatus {
  String get wireName => name;

  static ReleaseEvidenceReferenceStatus fromWireName(String value) {
    return ReleaseEvidenceReferenceStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidenceReferenceStatus: $value',
      ),
    );
  }
}

/// Evidence type taxonomy.
enum ReleaseEvidenceType {
  ast,
  graph,
  guardian,
  metrics,
  history,
  score,
  mes,
  dashboard,
  observability,
  qualityGate,
  releaseGovernance,
  approval,
  waiver,
  releaseContext,
  report,
  build,
  test,
  deployment,
  source,
  provenance,
  external,
  unavailable,
  incompatible,
  unknown,
}

extension ReleaseEvidenceTypeX on ReleaseEvidenceType {
  String get wireName => name;

  static ReleaseEvidenceType fromWireName(String value) {
    return ReleaseEvidenceType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseEvidenceType: $value'),
    );
  }
}

/// Platform artifact type referenced by evidence.
enum ReleaseEvidenceArtifactType {
  ast,
  graph,
  guardian,
  metrics,
  history,
  score,
  mes,
  dashboard,
  observability,
  qualityGate,
  releaseGovernance,
  approval,
  waiver,
  releaseContext,
  report,
  build,
  test,
  deployment,
  provenance,
  attestation,
  evidenceBundle,
  external,
  unknown,
}

extension ReleaseEvidenceArtifactTypeX on ReleaseEvidenceArtifactType {
  String get wireName => name;

  static ReleaseEvidenceArtifactType fromWireName(String value) {
    return ReleaseEvidenceArtifactType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidenceArtifactType: $value',
      ),
    );
  }
}

/// Evidence subject type.
enum ReleaseEvidenceSubjectType {
  project,
  release,
  commit,
  artifact,
  qualityGateSnapshot,
  releaseDecisionSnapshot,
  approval,
  waiver,
  evidenceBundle,
  attestation,
  custom,
}

extension ReleaseEvidenceSubjectTypeX on ReleaseEvidenceSubjectType {
  String get wireName => name;

  static ReleaseEvidenceSubjectType fromWireName(String value) {
    return ReleaseEvidenceSubjectType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseEvidenceSubjectType: $value'),
    );
  }
}

/// Evidence class taxonomy.
enum ReleaseEvidenceClass {
  technical,
  governance,
  operational,
  historical,
  compliance,
  provenance,
  contextual,
  external,
}

extension ReleaseEvidenceClassX on ReleaseEvidenceClass {
  String get wireName => name;

  static ReleaseEvidenceClass fromWireName(String value) {
    return ReleaseEvidenceClass.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseEvidenceClass: $value'),
    );
  }
}

/// Evidence role in a bundle.
enum ReleaseEvidenceRole {
  normative,
  supporting,
  contextual,
  informational,
  derived,
}

extension ReleaseEvidenceRoleX on ReleaseEvidenceRole {
  String get wireName => name;

  static ReleaseEvidenceRole fromWireName(String value) {
    return ReleaseEvidenceRole.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseEvidenceRole: $value'),
    );
  }
}

/// Structural integrity status (not cryptographic).
enum ReleaseEvidenceIntegrityStatus {
  intact,
  partiallyVerified,
  unverified,
  invalid,
  incompatible,
  unknown,
}

extension ReleaseEvidenceIntegrityStatusX on ReleaseEvidenceIntegrityStatus {
  String get wireName => name;

  static ReleaseEvidenceIntegrityStatus fromWireName(String value) {
    return ReleaseEvidenceIntegrityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidenceIntegrityStatus: $value',
      ),
    );
  }
}

/// Provenance classification.
enum ReleaseProvenanceType {
  source,
  build,
  test,
  analysis,
  qualityGate,
  releaseGovernance,
  packaging,
  deployment,
  manual,
  imported,
  unknown,
}

extension ReleaseProvenanceTypeX on ReleaseProvenanceType {
  String get wireName => name;

  static ReleaseProvenanceType fromWireName(String value) {
    return ReleaseProvenanceType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseProvenanceType: $value'),
    );
  }
}

enum ReleaseProvenanceStatus {
  planned,
  started,
  completed,
  failed,
  skipped,
  cancelled,
  unknown,
}

extension ReleaseProvenanceStatusX on ReleaseProvenanceStatus {
  String get wireName => name;

  static ReleaseProvenanceStatus fromWireName(String value) {
    return ReleaseProvenanceStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseProvenanceStatus: $value'),
    );
  }
}

enum ReleaseProvenanceStepType {
  source,
  build,
  test,
  analysis,
  qualityGate,
  releaseGovernance,
  packaging,
  deployment,
  manual,
  import,
  unknown,
}

extension ReleaseProvenanceStepTypeX on ReleaseProvenanceStepType {
  String get wireName => name;

  static ReleaseProvenanceStepType fromWireName(String value) {
    return ReleaseProvenanceStepType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseProvenanceStepType: $value'),
    );
  }
}

enum ReleaseProvenanceActorType {
  person,
  service,
  system,
  tool,
  organization,
  automation,
  unknown,
}

extension ReleaseProvenanceActorTypeX on ReleaseProvenanceActorType {
  String get wireName => name;

  static ReleaseProvenanceActorType fromWireName(String value) {
    return ReleaseProvenanceActorType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseProvenanceActorType: $value'),
    );
  }
}

enum ReleaseIdentityStatus {
  declared,
  structurallyValidated,
  externallyVerified,
  unverified,
  invalid,
  unknown,
}

extension ReleaseIdentityStatusX on ReleaseIdentityStatus {
  String get wireName => name;

  static ReleaseIdentityStatus fromWireName(String value) {
    return ReleaseIdentityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseIdentityStatus: $value'),
    );
  }
}

/// Attestation type taxonomy.
enum ReleaseAttestationType {
  evidenceBundleIntegrity,
  qualityGateDecision,
  releaseGovernanceDecision,
  approvalPresence,
  waiverPresence,
  provenanceCompleteness,
  artifactIntegrity,
  buildCompletion,
  testCompletion,
  deploymentReadiness,
  releaseAuthorization,
  rollbackPreparedness,
  complianceStatement,
  custom,
}

extension ReleaseAttestationTypeX on ReleaseAttestationType {
  String get wireName => name;

  static ReleaseAttestationType fromWireName(String value) {
    return ReleaseAttestationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseAttestationType: $value'),
    );
  }
}

enum ReleaseAttestationStatus {
  draft,
  issued,
  active,
  expired,
  revoked,
  superseded,
  invalid,
  unverified,
  incompatible,
}

extension ReleaseAttestationStatusX on ReleaseAttestationStatus {
  String get wireName => name;

  static ReleaseAttestationStatus fromWireName(String value) {
    return ReleaseAttestationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseAttestationStatus: $value'),
    );
  }
}

enum ReleaseAttestationPredicateType {
  evidenceBundle,
  qualityGate,
  releaseDecision,
  approval,
  waiver,
  provenance,
  artifactIntegrity,
  readiness,
  compliance,
  custom,
}

extension ReleaseAttestationPredicateTypeX on ReleaseAttestationPredicateType {
  String get wireName => name;

  static ReleaseAttestationPredicateType fromWireName(String value) {
    return ReleaseAttestationPredicateType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseAttestationPredicateType: $value',
      ),
    );
  }
}

enum ReleaseAttestationPredicateResult {
  satisfied,
  partiallySatisfied,
  notSatisfied,
  unavailable,
  incompatible,
  expired,
  unverified,
  invalid,
  error,
}

extension ReleaseAttestationPredicateResultX
    on ReleaseAttestationPredicateResult {
  String get wireName => name;

  static ReleaseAttestationPredicateResult fromWireName(String value) {
    return ReleaseAttestationPredicateResult.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseAttestationPredicateResult: $value',
      ),
    );
  }
}

enum ReleaseAttestationIssuerType {
  platform,
  person,
  service,
  organization,
  externalSystem,
  automation,
  unknown,
}

extension ReleaseAttestationIssuerTypeX on ReleaseAttestationIssuerType {
  String get wireName => name;

  static ReleaseAttestationIssuerType fromWireName(String value) {
    return ReleaseAttestationIssuerType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseAttestationIssuerType: $value'),
    );
  }
}

enum ReleaseAttestationAuthorityStatus {
  active,
  suspended,
  revoked,
  expired,
  unverified,
  unknown,
}

extension ReleaseAttestationAuthorityStatusX
    on ReleaseAttestationAuthorityStatus {
  String get wireName => name;

  static ReleaseAttestationAuthorityStatus fromWireName(String value) {
    return ReleaseAttestationAuthorityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseAttestationAuthorityStatus: $value',
      ),
    );
  }
}

enum ReleaseSignatureVerificationStatus {
  notPresent,
  present,
  unverified,
  valid,
  invalid,
  expired,
  revoked,
  unsupported,
  unknown,
}

extension ReleaseSignatureVerificationStatusX
    on ReleaseSignatureVerificationStatus {
  String get wireName => name;

  static ReleaseSignatureVerificationStatus fromWireName(String value) {
    return ReleaseSignatureVerificationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseSignatureVerificationStatus: $value',
      ),
    );
  }
}

enum ReleaseVerificationStatus {
  verified,
  partiallyVerified,
  unverified,
  invalid,
  unavailable,
  incompatible,
  expired,
  error,
}

extension ReleaseVerificationStatusX on ReleaseVerificationStatus {
  String get wireName => name;

  static ReleaseVerificationStatus fromWireName(String value) {
    return ReleaseVerificationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseVerificationStatus: $value'),
    );
  }
}

enum ReleaseVerificationCheckType {
  identity,
  fingerprint,
  subjectConsistency,
  projectConsistency,
  commitConsistency,
  schema,
  policy,
  canonicalization,
  evidenceAvailability,
  evidenceIntegrity,
  provenance,
  issuer,
  authority,
  signature,
  expiration,
  coverage,
  releaseDecisionConsistency,
}

extension ReleaseVerificationCheckTypeX on ReleaseVerificationCheckType {
  String get wireName => name;

  static ReleaseVerificationCheckType fromWireName(String value) {
    return ReleaseVerificationCheckType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseVerificationCheckType: $value'),
    );
  }
}

enum ReleaseVerificationCheckStatus {
  passed,
  failed,
  skipped,
  unavailable,
  incompatible,
  error,
}

extension ReleaseVerificationCheckStatusX on ReleaseVerificationCheckStatus {
  String get wireName => name;

  static ReleaseVerificationCheckStatus fromWireName(String value) {
    return ReleaseVerificationCheckStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseVerificationCheckStatus: $value',
      ),
    );
  }
}

enum ReleaseEvidenceCompatibilityStatus {
  compatible,
  partiallyCompatible,
  incompatible,
  unknown,
}

extension ReleaseEvidenceCompatibilityStatusX
    on ReleaseEvidenceCompatibilityStatus {
  String get wireName => name;

  static ReleaseEvidenceCompatibilityStatus fromWireName(String value) {
    return ReleaseEvidenceCompatibilityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidenceCompatibilityStatus: $value',
      ),
    );
  }
}

enum ReleaseEvidenceEligibilityStatus {
  eligible,
  partiallyEligible,
  ineligible,
  unknown,
}

extension ReleaseEvidenceEligibilityStatusX
    on ReleaseEvidenceEligibilityStatus {
  String get wireName => name;

  static ReleaseEvidenceEligibilityStatus fromWireName(String value) {
    return ReleaseEvidenceEligibilityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidenceEligibilityStatus: $value',
      ),
    );
  }
}

enum ReleaseEvidenceResultStatus {
  success,
  partial,
  unavailable,
  incompatible,
  failure,
}

extension ReleaseEvidenceResultStatusX on ReleaseEvidenceResultStatus {
  String get wireName => name;

  static ReleaseEvidenceResultStatus fromWireName(String value) {
    return ReleaseEvidenceResultStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseEvidenceResultStatus: $value'),
    );
  }
}

enum ReleaseEvidenceCollectionRuleSeverity {
  informational,
  advisory,
  warning,
  blocking,
  critical,
}

extension ReleaseEvidenceCollectionRuleSeverityX
    on ReleaseEvidenceCollectionRuleSeverity {
  String get wireName => name;

  static ReleaseEvidenceCollectionRuleSeverity fromWireName(String value) {
    return ReleaseEvidenceCollectionRuleSeverity.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidenceCollectionRuleSeverity: $value',
      ),
    );
  }
}

enum ReleaseEvidenceCollectionRuleRequirement {
  required,
  optional,
  informational,
}

extension ReleaseEvidenceCollectionRuleRequirementX
    on ReleaseEvidenceCollectionRuleRequirement {
  String get wireName => name;

  static ReleaseEvidenceCollectionRuleRequirement fromWireName(String value) {
    return ReleaseEvidenceCollectionRuleRequirement.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidenceCollectionRuleRequirement: $value',
      ),
    );
  }
}

enum ReleaseEvidenceCollectionRuleTarget {
  qualityGatePresent,
  releaseDecisionPresent,
  projectConsistency,
  commitConsistency,
  policyConsistency,
  fingerprintPresent,
  sourceAvailable,
  sourceCompatible,
  evidenceFreshness,
  evidenceCount,
  normativeEvidenceCount,
  provenancePresent,
  provenanceComplete,
  requiredAttestationCount,
  validAttestationCount,
  invalidAttestationCount,
  expiredAttestationCount,
  unverifiedAttestationCount,
  releaseAuthorizationConsistent,
  sourceSetComplete,
}

extension ReleaseEvidenceCollectionRuleTargetX
    on ReleaseEvidenceCollectionRuleTarget {
  String get wireName => name;

  static ReleaseEvidenceCollectionRuleTarget fromWireName(String value) {
    return ReleaseEvidenceCollectionRuleTarget.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidenceCollectionRuleTarget: $value',
      ),
    );
  }
}

enum ReleaseEvidenceCollectionRuleOperator {
  isTrue,
  isFalse,
  equals,
  notEquals,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  exists,
  doesNotExist,
}

extension ReleaseEvidenceCollectionRuleOperatorX
    on ReleaseEvidenceCollectionRuleOperator {
  String get wireName => name;

  static ReleaseEvidenceCollectionRuleOperator fromWireName(String value) {
    return ReleaseEvidenceCollectionRuleOperator.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidenceCollectionRuleOperator: $value',
      ),
    );
  }
}

enum ReleaseEvidenceMissingDataPolicy {
  fail,
  warn,
  ignore,
  unavailable,
}

extension ReleaseEvidenceMissingDataPolicyX
    on ReleaseEvidenceMissingDataPolicy {
  String get wireName => name;

  static ReleaseEvidenceMissingDataPolicy fromWireName(String value) {
    return ReleaseEvidenceMissingDataPolicy.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidenceMissingDataPolicy: $value',
      ),
    );
  }
}

enum ReleaseEvidenceIncompatibleDataPolicy {
  fail,
  warn,
  ignore,
  incompatible,
}

extension ReleaseEvidenceIncompatibleDataPolicyX
    on ReleaseEvidenceIncompatibleDataPolicy {
  String get wireName => name;

  static ReleaseEvidenceIncompatibleDataPolicy fromWireName(String value) {
    return ReleaseEvidenceIncompatibleDataPolicy.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidenceIncompatibleDataPolicy: $value',
      ),
    );
  }
}

enum ReleaseEvidenceRuleSetAggregationMode {
  all,
  any,
  minimumCount,
  minimumPercentage,
}

extension ReleaseEvidenceRuleSetAggregationModeX
    on ReleaseEvidenceRuleSetAggregationMode {
  String get wireName => name;

  static ReleaseEvidenceRuleSetAggregationMode fromWireName(String value) {
    return ReleaseEvidenceRuleSetAggregationMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidenceRuleSetAggregationMode: $value',
      ),
    );
  }
}

enum ReleaseEvidenceExplanationType {
  evidenceAccepted,
  evidenceRejected,
  evidenceUnavailable,
  evidenceIncompatible,
  evidenceExpired,
  evidenceUnverified,
  attestationAccepted,
  attestationRejected,
  attestationExpired,
  attestationRevoked,
  attestationUnverified,
  provenanceAccepted,
  provenanceIncomplete,
  compatibility,
  eligibility,
  verificationPassed,
  verificationPartial,
  verificationFailed,
  verificationUnavailable,
  verificationIncompatible,
  verificationExpired,
  verificationError,
}

extension ReleaseEvidenceExplanationTypeX on ReleaseEvidenceExplanationType {
  String get wireName => name;

  static ReleaseEvidenceExplanationType fromWireName(String value) {
    return ReleaseEvidenceExplanationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
          'Unknown ReleaseEvidenceExplanationType: $value'),
    );
  }
}

enum ReleaseEvidenceWarningCode {
  evidenceNearExpiration,
  attestationNearExpiration,
  issuerUnverified,
  authorityUnverified,
  signatureUnverified,
  reducedCoverage,
  staleEvidence,
  deprecatedPolicy,
  historicalEvidence,
  derivedEvidence,
  provenanceIncomplete,
  externalEvidenceUnverified,
  capabilityGap,
}

extension ReleaseEvidenceWarningCodeX on ReleaseEvidenceWarningCode {
  String get wireName => name;

  static ReleaseEvidenceWarningCode fromWireName(String value) {
    return ReleaseEvidenceWarningCode.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseEvidenceWarningCode: $value'),
    );
  }
}

enum ReleaseEvidenceErrorCode {
  invalidPolicy,
  invalidRequest,
  invalidSubject,
  invalidBundle,
  invalidEvidence,
  invalidAttestation,
  invalidProvenance,
  sourceResolutionFailure,
  compatibilityFailure,
  verificationFailure,
  serializationFailure,
  identityFailure,
  snapshotValidationFailure,
}

extension ReleaseEvidenceErrorCodeX on ReleaseEvidenceErrorCode {
  String get wireName => name;

  static ReleaseEvidenceErrorCode fromWireName(String value) {
    return ReleaseEvidenceErrorCode.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown ReleaseEvidenceErrorCode: $value'),
    );
  }
}

enum ReleaseEvidenceLimitationCode {
  noCryptographicVerification,
  noSignatureGeneration,
  noExternalIdentityVerification,
  noCertificateValidation,
  noTransparencyLog,
  noPhysicalPersistence,
  noRemoteEvidenceFetch,
  noCiCdIntegration,
  noSbomGeneration,
  noAutomaticAttestationIssuance,
  provenanceNotExternallyVerified,
  historicalDataIncomplete,
}

extension ReleaseEvidenceLimitationCodeX on ReleaseEvidenceLimitationCode {
  String get wireName => name;

  static ReleaseEvidenceLimitationCode fromWireName(String value) {
    return ReleaseEvidenceLimitationCode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
          'Unknown ReleaseEvidenceLimitationCode: $value'),
    );
  }
}

enum ReleaseEvidenceAvailabilityStatus {
  available,
  partial,
  unavailable,
  incompatible,
}

extension ReleaseEvidenceAvailabilityStatusX
    on ReleaseEvidenceAvailabilityStatus {
  String get wireName => name;

  static ReleaseEvidenceAvailabilityStatus fromWireName(String value) {
    return ReleaseEvidenceAvailabilityStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidenceAvailabilityStatus: $value',
      ),
    );
  }
}

/// Publication status for provider operations (Part 2).
enum ReleaseEvidencePublicationStatus {
  notRequested,
  published,
  skipped,
  failed,
}

extension ReleaseEvidencePublicationStatusX
    on ReleaseEvidencePublicationStatus {
  String get wireName => name;

  static ReleaseEvidencePublicationStatus fromWireName(String value) {
    return ReleaseEvidencePublicationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidencePublicationStatus: $value',
      ),
    );
  }
}

enum ReleaseEvidenceSourceResolutionMode {
  injected,
  byId,
  latest,
  unavailable,
  notRequested,
}

extension ReleaseEvidenceSourceResolutionModeX
    on ReleaseEvidenceSourceResolutionMode {
  String get wireName => name;

  static ReleaseEvidenceSourceResolutionMode fromWireName(String value) {
    return ReleaseEvidenceSourceResolutionMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidenceSourceResolutionMode: $value',
      ),
    );
  }
}
