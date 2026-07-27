import '../persistent_artifact_equality.dart';
import 'persistent_artifact_cloud_enums.dart';
import 'persistent_artifact_cloud_models.dart'
    show PersistentArtifactCloudIssue;

/// Declarative checklist for admitting a future real cloud adapter prototype.
///
/// Satisfying criteria does not enable staging, production, SDK installation,
/// or release authorization.
class PersistentArtifactRealCloudAdapterAdmissionCriteria {
  const PersistentArtifactRealCloudAdapterAdmissionCriteria({
    this.targetProviderSelected = false,
    this.protocolSpecificationReviewed = false,
    this.officialSdkDecisionRecorded = false,
    this.dependencySecurityReviewApproved = false,
    this.credentialArchitectureApproved = false,
    this.leastPrivilegePolicyApproved = false,
    this.workloadIdentityDecisionApproved = false,
    this.networkBoundaryApproved = false,
    this.endpointPolicyApproved = false,
    this.tlsPolicyApproved = false,
    this.dataResidencyApproved = false,
    this.encryptionPolicyApproved = false,
    this.keyOwnershipApproved = false,
    this.retentionSemanticsApproved = false,
    this.legalHoldSemanticsApproved = false,
    this.deletionSemanticsApproved = false,
    this.versioningSemanticsApproved = false,
    this.consistencySemanticsDocumented = false,
    this.retrySemanticsApproved = false,
    this.timeoutSemanticsApproved = false,
    this.idempotencyStrategyApproved = false,
    this.multipartStrategyApproved = false,
    this.observabilityPolicyApproved = false,
    this.secretRedactionApproved = false,
    this.integrationTestEnvironmentApproved = false,
    this.costControlsApproved = false,
    this.rateLimitStrategyApproved = false,
    this.incidentResponseApproved = false,
    this.operationalOwnerAssigned = false,
    this.rollbackPlanApproved = false,
    this.adrApproved = false,
    this.metadata = const {},
  });

  final bool targetProviderSelected;
  final bool protocolSpecificationReviewed;
  final bool officialSdkDecisionRecorded;
  final bool dependencySecurityReviewApproved;
  final bool credentialArchitectureApproved;
  final bool leastPrivilegePolicyApproved;
  final bool workloadIdentityDecisionApproved;
  final bool networkBoundaryApproved;
  final bool endpointPolicyApproved;
  final bool tlsPolicyApproved;
  final bool dataResidencyApproved;
  final bool encryptionPolicyApproved;
  final bool keyOwnershipApproved;
  final bool retentionSemanticsApproved;
  final bool legalHoldSemanticsApproved;
  final bool deletionSemanticsApproved;
  final bool versioningSemanticsApproved;
  final bool consistencySemanticsDocumented;
  final bool retrySemanticsApproved;
  final bool timeoutSemanticsApproved;
  final bool idempotencyStrategyApproved;
  final bool multipartStrategyApproved;
  final bool observabilityPolicyApproved;
  final bool secretRedactionApproved;
  final bool integrationTestEnvironmentApproved;
  final bool costControlsApproved;
  final bool rateLimitStrategyApproved;
  final bool incidentResponseApproved;
  final bool operationalOwnerAssigned;
  final bool rollbackPlanApproved;
  final bool adrApproved;
  final Map<String, String> metadata;

  static const List<String> criterionIds = [
    'targetProviderSelected',
    'protocolSpecificationReviewed',
    'officialSdkDecisionRecorded',
    'dependencySecurityReviewApproved',
    'credentialArchitectureApproved',
    'leastPrivilegePolicyApproved',
    'workloadIdentityDecisionApproved',
    'networkBoundaryApproved',
    'endpointPolicyApproved',
    'tlsPolicyApproved',
    'dataResidencyApproved',
    'encryptionPolicyApproved',
    'keyOwnershipApproved',
    'retentionSemanticsApproved',
    'legalHoldSemanticsApproved',
    'deletionSemanticsApproved',
    'versioningSemanticsApproved',
    'consistencySemanticsDocumented',
    'retrySemanticsApproved',
    'timeoutSemanticsApproved',
    'idempotencyStrategyApproved',
    'multipartStrategyApproved',
    'observabilityPolicyApproved',
    'secretRedactionApproved',
    'integrationTestEnvironmentApproved',
    'costControlsApproved',
    'rateLimitStrategyApproved',
    'incidentResponseApproved',
    'operationalOwnerAssigned',
    'rollbackPlanApproved',
    'adrApproved',
  ];

  List<String> missingCriterionIds() {
    final missing = <String>[];
    for (final entry in _entries) {
      if (!entry.$2) {
        missing.add(entry.$1);
      }
    }
    return List.unmodifiable(missing);
  }

  int get satisfiedCount => criterionIds.length - missingCriterionIds().length;

  bool get allSatisfied => missingCriterionIds().isEmpty;

  Iterable<(String, bool)> get _entries sync* {
    yield ('targetProviderSelected', targetProviderSelected);
    yield ('protocolSpecificationReviewed', protocolSpecificationReviewed);
    yield ('officialSdkDecisionRecorded', officialSdkDecisionRecorded);
    yield (
      'dependencySecurityReviewApproved',
      dependencySecurityReviewApproved,
    );
    yield ('credentialArchitectureApproved', credentialArchitectureApproved);
    yield ('leastPrivilegePolicyApproved', leastPrivilegePolicyApproved);
    yield (
      'workloadIdentityDecisionApproved',
      workloadIdentityDecisionApproved,
    );
    yield ('networkBoundaryApproved', networkBoundaryApproved);
    yield ('endpointPolicyApproved', endpointPolicyApproved);
    yield ('tlsPolicyApproved', tlsPolicyApproved);
    yield ('dataResidencyApproved', dataResidencyApproved);
    yield ('encryptionPolicyApproved', encryptionPolicyApproved);
    yield ('keyOwnershipApproved', keyOwnershipApproved);
    yield ('retentionSemanticsApproved', retentionSemanticsApproved);
    yield ('legalHoldSemanticsApproved', legalHoldSemanticsApproved);
    yield ('deletionSemanticsApproved', deletionSemanticsApproved);
    yield ('versioningSemanticsApproved', versioningSemanticsApproved);
    yield ('consistencySemanticsDocumented', consistencySemanticsDocumented);
    yield ('retrySemanticsApproved', retrySemanticsApproved);
    yield ('timeoutSemanticsApproved', timeoutSemanticsApproved);
    yield ('idempotencyStrategyApproved', idempotencyStrategyApproved);
    yield ('multipartStrategyApproved', multipartStrategyApproved);
    yield ('observabilityPolicyApproved', observabilityPolicyApproved);
    yield ('secretRedactionApproved', secretRedactionApproved);
    yield (
      'integrationTestEnvironmentApproved',
      integrationTestEnvironmentApproved,
    );
    yield ('costControlsApproved', costControlsApproved);
    yield ('rateLimitStrategyApproved', rateLimitStrategyApproved);
    yield ('incidentResponseApproved', incidentResponseApproved);
    yield ('operationalOwnerAssigned', operationalOwnerAssigned);
    yield ('rollbackPlanApproved', rollbackPlanApproved);
    yield ('adrApproved', adrApproved);
  }

  Map<String, dynamic> toJson() => {
        'targetProviderSelected': targetProviderSelected,
        'protocolSpecificationReviewed': protocolSpecificationReviewed,
        'officialSdkDecisionRecorded': officialSdkDecisionRecorded,
        'dependencySecurityReviewApproved': dependencySecurityReviewApproved,
        'credentialArchitectureApproved': credentialArchitectureApproved,
        'leastPrivilegePolicyApproved': leastPrivilegePolicyApproved,
        'workloadIdentityDecisionApproved': workloadIdentityDecisionApproved,
        'networkBoundaryApproved': networkBoundaryApproved,
        'endpointPolicyApproved': endpointPolicyApproved,
        'tlsPolicyApproved': tlsPolicyApproved,
        'dataResidencyApproved': dataResidencyApproved,
        'encryptionPolicyApproved': encryptionPolicyApproved,
        'keyOwnershipApproved': keyOwnershipApproved,
        'retentionSemanticsApproved': retentionSemanticsApproved,
        'legalHoldSemanticsApproved': legalHoldSemanticsApproved,
        'deletionSemanticsApproved': deletionSemanticsApproved,
        'versioningSemanticsApproved': versioningSemanticsApproved,
        'consistencySemanticsDocumented': consistencySemanticsDocumented,
        'retrySemanticsApproved': retrySemanticsApproved,
        'timeoutSemanticsApproved': timeoutSemanticsApproved,
        'idempotencyStrategyApproved': idempotencyStrategyApproved,
        'multipartStrategyApproved': multipartStrategyApproved,
        'observabilityPolicyApproved': observabilityPolicyApproved,
        'secretRedactionApproved': secretRedactionApproved,
        'integrationTestEnvironmentApproved':
            integrationTestEnvironmentApproved,
        'costControlsApproved': costControlsApproved,
        'rateLimitStrategyApproved': rateLimitStrategyApproved,
        'incidentResponseApproved': incidentResponseApproved,
        'operationalOwnerAssigned': operationalOwnerAssigned,
        'rollbackPlanApproved': rollbackPlanApproved,
        'adrApproved': adrApproved,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactRealCloudAdapterAdmissionCriteria.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactRealCloudAdapterAdmissionCriteria(
      targetProviderSelected: json['targetProviderSelected'] as bool? ?? false,
      protocolSpecificationReviewed:
          json['protocolSpecificationReviewed'] as bool? ?? false,
      officialSdkDecisionRecorded:
          json['officialSdkDecisionRecorded'] as bool? ?? false,
      dependencySecurityReviewApproved:
          json['dependencySecurityReviewApproved'] as bool? ?? false,
      credentialArchitectureApproved:
          json['credentialArchitectureApproved'] as bool? ?? false,
      leastPrivilegePolicyApproved:
          json['leastPrivilegePolicyApproved'] as bool? ?? false,
      workloadIdentityDecisionApproved:
          json['workloadIdentityDecisionApproved'] as bool? ?? false,
      networkBoundaryApproved:
          json['networkBoundaryApproved'] as bool? ?? false,
      endpointPolicyApproved: json['endpointPolicyApproved'] as bool? ?? false,
      tlsPolicyApproved: json['tlsPolicyApproved'] as bool? ?? false,
      dataResidencyApproved: json['dataResidencyApproved'] as bool? ?? false,
      encryptionPolicyApproved:
          json['encryptionPolicyApproved'] as bool? ?? false,
      keyOwnershipApproved: json['keyOwnershipApproved'] as bool? ?? false,
      retentionSemanticsApproved:
          json['retentionSemanticsApproved'] as bool? ?? false,
      legalHoldSemanticsApproved:
          json['legalHoldSemanticsApproved'] as bool? ?? false,
      deletionSemanticsApproved:
          json['deletionSemanticsApproved'] as bool? ?? false,
      versioningSemanticsApproved:
          json['versioningSemanticsApproved'] as bool? ?? false,
      consistencySemanticsDocumented:
          json['consistencySemanticsDocumented'] as bool? ?? false,
      retrySemanticsApproved: json['retrySemanticsApproved'] as bool? ?? false,
      timeoutSemanticsApproved:
          json['timeoutSemanticsApproved'] as bool? ?? false,
      idempotencyStrategyApproved:
          json['idempotencyStrategyApproved'] as bool? ?? false,
      multipartStrategyApproved:
          json['multipartStrategyApproved'] as bool? ?? false,
      observabilityPolicyApproved:
          json['observabilityPolicyApproved'] as bool? ?? false,
      secretRedactionApproved:
          json['secretRedactionApproved'] as bool? ?? false,
      integrationTestEnvironmentApproved:
          json['integrationTestEnvironmentApproved'] as bool? ?? false,
      costControlsApproved: json['costControlsApproved'] as bool? ?? false,
      rateLimitStrategyApproved:
          json['rateLimitStrategyApproved'] as bool? ?? false,
      incidentResponseApproved:
          json['incidentResponseApproved'] as bool? ?? false,
      operationalOwnerAssigned:
          json['operationalOwnerAssigned'] as bool? ?? false,
      rollbackPlanApproved: json['rollbackPlanApproved'] as bool? ?? false,
      adrApproved: json['adrApproved'] as bool? ?? false,
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'targetProviderSelected': targetProviderSelected,
        'protocolSpecificationReviewed': protocolSpecificationReviewed,
        'officialSdkDecisionRecorded': officialSdkDecisionRecorded,
        'dependencySecurityReviewApproved': dependencySecurityReviewApproved,
        'credentialArchitectureApproved': credentialArchitectureApproved,
        'leastPrivilegePolicyApproved': leastPrivilegePolicyApproved,
        'workloadIdentityDecisionApproved': workloadIdentityDecisionApproved,
        'networkBoundaryApproved': networkBoundaryApproved,
        'endpointPolicyApproved': endpointPolicyApproved,
        'tlsPolicyApproved': tlsPolicyApproved,
        'dataResidencyApproved': dataResidencyApproved,
        'encryptionPolicyApproved': encryptionPolicyApproved,
        'keyOwnershipApproved': keyOwnershipApproved,
        'retentionSemanticsApproved': retentionSemanticsApproved,
        'legalHoldSemanticsApproved': legalHoldSemanticsApproved,
        'deletionSemanticsApproved': deletionSemanticsApproved,
        'versioningSemanticsApproved': versioningSemanticsApproved,
        'consistencySemanticsDocumented': consistencySemanticsDocumented,
        'retrySemanticsApproved': retrySemanticsApproved,
        'timeoutSemanticsApproved': timeoutSemanticsApproved,
        'idempotencyStrategyApproved': idempotencyStrategyApproved,
        'multipartStrategyApproved': multipartStrategyApproved,
        'observabilityPolicyApproved': observabilityPolicyApproved,
        'secretRedactionApproved': secretRedactionApproved,
        'integrationTestEnvironmentApproved':
            integrationTestEnvironmentApproved,
        'costControlsApproved': costControlsApproved,
        'rateLimitStrategyApproved': rateLimitStrategyApproved,
        'incidentResponseApproved': incidentResponseApproved,
        'operationalOwnerAssigned': operationalOwnerAssigned,
        'rollbackPlanApproved': rollbackPlanApproved,
        'adrApproved': adrApproved,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactRealCloudAdapterAdmissionCriteria copyWith({
    bool? targetProviderSelected,
    bool? protocolSpecificationReviewed,
    bool? officialSdkDecisionRecorded,
    bool? dependencySecurityReviewApproved,
    bool? credentialArchitectureApproved,
    bool? leastPrivilegePolicyApproved,
    bool? workloadIdentityDecisionApproved,
    bool? networkBoundaryApproved,
    bool? endpointPolicyApproved,
    bool? tlsPolicyApproved,
    bool? dataResidencyApproved,
    bool? encryptionPolicyApproved,
    bool? keyOwnershipApproved,
    bool? retentionSemanticsApproved,
    bool? legalHoldSemanticsApproved,
    bool? deletionSemanticsApproved,
    bool? versioningSemanticsApproved,
    bool? consistencySemanticsDocumented,
    bool? retrySemanticsApproved,
    bool? timeoutSemanticsApproved,
    bool? idempotencyStrategyApproved,
    bool? multipartStrategyApproved,
    bool? observabilityPolicyApproved,
    bool? secretRedactionApproved,
    bool? integrationTestEnvironmentApproved,
    bool? costControlsApproved,
    bool? rateLimitStrategyApproved,
    bool? incidentResponseApproved,
    bool? operationalOwnerAssigned,
    bool? rollbackPlanApproved,
    bool? adrApproved,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactRealCloudAdapterAdmissionCriteria(
      targetProviderSelected:
          targetProviderSelected ?? this.targetProviderSelected,
      protocolSpecificationReviewed:
          protocolSpecificationReviewed ?? this.protocolSpecificationReviewed,
      officialSdkDecisionRecorded:
          officialSdkDecisionRecorded ?? this.officialSdkDecisionRecorded,
      dependencySecurityReviewApproved: dependencySecurityReviewApproved ??
          this.dependencySecurityReviewApproved,
      credentialArchitectureApproved:
          credentialArchitectureApproved ?? this.credentialArchitectureApproved,
      leastPrivilegePolicyApproved:
          leastPrivilegePolicyApproved ?? this.leastPrivilegePolicyApproved,
      workloadIdentityDecisionApproved: workloadIdentityDecisionApproved ??
          this.workloadIdentityDecisionApproved,
      networkBoundaryApproved:
          networkBoundaryApproved ?? this.networkBoundaryApproved,
      endpointPolicyApproved:
          endpointPolicyApproved ?? this.endpointPolicyApproved,
      tlsPolicyApproved: tlsPolicyApproved ?? this.tlsPolicyApproved,
      dataResidencyApproved:
          dataResidencyApproved ?? this.dataResidencyApproved,
      encryptionPolicyApproved:
          encryptionPolicyApproved ?? this.encryptionPolicyApproved,
      keyOwnershipApproved: keyOwnershipApproved ?? this.keyOwnershipApproved,
      retentionSemanticsApproved:
          retentionSemanticsApproved ?? this.retentionSemanticsApproved,
      legalHoldSemanticsApproved:
          legalHoldSemanticsApproved ?? this.legalHoldSemanticsApproved,
      deletionSemanticsApproved:
          deletionSemanticsApproved ?? this.deletionSemanticsApproved,
      versioningSemanticsApproved:
          versioningSemanticsApproved ?? this.versioningSemanticsApproved,
      consistencySemanticsDocumented:
          consistencySemanticsDocumented ?? this.consistencySemanticsDocumented,
      retrySemanticsApproved:
          retrySemanticsApproved ?? this.retrySemanticsApproved,
      timeoutSemanticsApproved:
          timeoutSemanticsApproved ?? this.timeoutSemanticsApproved,
      idempotencyStrategyApproved:
          idempotencyStrategyApproved ?? this.idempotencyStrategyApproved,
      multipartStrategyApproved:
          multipartStrategyApproved ?? this.multipartStrategyApproved,
      observabilityPolicyApproved:
          observabilityPolicyApproved ?? this.observabilityPolicyApproved,
      secretRedactionApproved:
          secretRedactionApproved ?? this.secretRedactionApproved,
      integrationTestEnvironmentApproved: integrationTestEnvironmentApproved ??
          this.integrationTestEnvironmentApproved,
      costControlsApproved: costControlsApproved ?? this.costControlsApproved,
      rateLimitStrategyApproved:
          rateLimitStrategyApproved ?? this.rateLimitStrategyApproved,
      incidentResponseApproved:
          incidentResponseApproved ?? this.incidentResponseApproved,
      operationalOwnerAssigned:
          operationalOwnerAssigned ?? this.operationalOwnerAssigned,
      rollbackPlanApproved: rollbackPlanApproved ?? this.rollbackPlanApproved,
      adrApproved: adrApproved ?? this.adrApproved,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactRealCloudAdapterAdmissionCriteria &&
          targetProviderSelected == other.targetProviderSelected &&
          protocolSpecificationReviewed ==
              other.protocolSpecificationReviewed &&
          officialSdkDecisionRecorded == other.officialSdkDecisionRecorded &&
          dependencySecurityReviewApproved ==
              other.dependencySecurityReviewApproved &&
          credentialArchitectureApproved ==
              other.credentialArchitectureApproved &&
          leastPrivilegePolicyApproved == other.leastPrivilegePolicyApproved &&
          workloadIdentityDecisionApproved ==
              other.workloadIdentityDecisionApproved &&
          networkBoundaryApproved == other.networkBoundaryApproved &&
          endpointPolicyApproved == other.endpointPolicyApproved &&
          tlsPolicyApproved == other.tlsPolicyApproved &&
          dataResidencyApproved == other.dataResidencyApproved &&
          encryptionPolicyApproved == other.encryptionPolicyApproved &&
          keyOwnershipApproved == other.keyOwnershipApproved &&
          retentionSemanticsApproved == other.retentionSemanticsApproved &&
          legalHoldSemanticsApproved == other.legalHoldSemanticsApproved &&
          deletionSemanticsApproved == other.deletionSemanticsApproved &&
          versioningSemanticsApproved == other.versioningSemanticsApproved &&
          consistencySemanticsDocumented ==
              other.consistencySemanticsDocumented &&
          retrySemanticsApproved == other.retrySemanticsApproved &&
          timeoutSemanticsApproved == other.timeoutSemanticsApproved &&
          idempotencyStrategyApproved == other.idempotencyStrategyApproved &&
          multipartStrategyApproved == other.multipartStrategyApproved &&
          observabilityPolicyApproved == other.observabilityPolicyApproved &&
          secretRedactionApproved == other.secretRedactionApproved &&
          integrationTestEnvironmentApproved ==
              other.integrationTestEnvironmentApproved &&
          costControlsApproved == other.costControlsApproved &&
          rateLimitStrategyApproved == other.rateLimitStrategyApproved &&
          incidentResponseApproved == other.incidentResponseApproved &&
          operationalOwnerAssigned == other.operationalOwnerAssigned &&
          rollbackPlanApproved == other.rollbackPlanApproved &&
          adrApproved == other.adrApproved &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hashAll([
        targetProviderSelected,
        protocolSpecificationReviewed,
        officialSdkDecisionRecorded,
        dependencySecurityReviewApproved,
        credentialArchitectureApproved,
        leastPrivilegePolicyApproved,
        workloadIdentityDecisionApproved,
        networkBoundaryApproved,
        endpointPolicyApproved,
        tlsPolicyApproved,
        dataResidencyApproved,
        encryptionPolicyApproved,
        keyOwnershipApproved,
        retentionSemanticsApproved,
        legalHoldSemanticsApproved,
        deletionSemanticsApproved,
        versioningSemanticsApproved,
        consistencySemanticsDocumented,
        retrySemanticsApproved,
        timeoutSemanticsApproved,
        idempotencyStrategyApproved,
        multipartStrategyApproved,
        observabilityPolicyApproved,
        secretRedactionApproved,
        integrationTestEnvironmentApproved,
        costControlsApproved,
        rateLimitStrategyApproved,
        incidentResponseApproved,
        operationalOwnerAssigned,
        rollbackPlanApproved,
        adrApproved,
        Object.hashAll(metadata.entries),
      ]);
}

/// Admission decision for a future real cloud adapter prototype.
///
/// [stagingApproved] and [productionApproved] remain false in all outcomes.
class PersistentArtifactRealCloudAdapterAdmissionDecision {
  const PersistentArtifactRealCloudAdapterAdmissionDecision({
    required this.status,
    required this.satisfiedCriteriaCount,
    required this.totalCriteriaCount,
    this.missingCriteria = const [],
    this.manualApprovalReference,
    this.stagingApproved = false,
    this.productionApproved = false,
    this.prototypeAdmissionGranted = false,
    this.issues = const [],
    this.metadata = const {},
  });

  final RealCloudAdapterAdmissionStatus status;
  final int satisfiedCriteriaCount;
  final int totalCriteriaCount;
  final List<String> missingCriteria;
  final String? manualApprovalReference;
  final bool stagingApproved;
  final bool productionApproved;
  final bool prototypeAdmissionGranted;
  final List<PersistentArtifactCloudIssue> issues;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'satisfiedCriteriaCount': satisfiedCriteriaCount,
        'totalCriteriaCount': totalCriteriaCount,
        if (missingCriteria.isNotEmpty) 'missingCriteria': missingCriteria,
        if (manualApprovalReference != null)
          'manualApprovalReference': manualApprovalReference,
        'stagingApproved': stagingApproved,
        'productionApproved': productionApproved,
        'prototypeAdmissionGranted': prototypeAdmissionGranted,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactRealCloudAdapterAdmissionDecision.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactRealCloudAdapterAdmissionDecision(
      status: RealCloudAdapterAdmissionStatusX.fromWireName(
        json['status'] as String,
      ),
      satisfiedCriteriaCount: json['satisfiedCriteriaCount'] as int,
      totalCriteriaCount: json['totalCriteriaCount'] as int,
      missingCriteria: _stringList(json['missingCriteria']),
      manualApprovalReference: json['manualApprovalReference'] as String?,
      stagingApproved: json['stagingApproved'] as bool? ?? false,
      productionApproved: json['productionApproved'] as bool? ?? false,
      prototypeAdmissionGranted:
          json['prototypeAdmissionGranted'] as bool? ?? false,
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactCloudIssue.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      metadata: _stringMap(json['metadata']),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'status': status.wireName,
        'satisfiedCriteriaCount': satisfiedCriteriaCount,
        'totalCriteriaCount': totalCriteriaCount,
        if (missingCriteria.isNotEmpty)
          'missingCriteria': List<String>.from(missingCriteria)..sort(),
        if (manualApprovalReference != null)
          'manualApprovalReference': manualApprovalReference,
        'stagingApproved': stagingApproved,
        'productionApproved': productionApproved,
        'prototypeAdmissionGranted': prototypeAdmissionGranted,
        if (issues.isNotEmpty)
          'issues': paSortedComparableList(
            issues.map((e) => e.toComparableJson()),
            'code',
          ),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactRealCloudAdapterAdmissionDecision &&
          status == other.status &&
          satisfiedCriteriaCount == other.satisfiedCriteriaCount &&
          totalCriteriaCount == other.totalCriteriaCount &&
          paListEquals(missingCriteria, other.missingCriteria) &&
          manualApprovalReference == other.manualApprovalReference &&
          stagingApproved == other.stagingApproved &&
          productionApproved == other.productionApproved &&
          prototypeAdmissionGranted == other.prototypeAdmissionGranted &&
          paListEquals(issues, other.issues) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        status,
        satisfiedCriteriaCount,
        totalCriteriaCount,
        Object.hashAll(missingCriteria),
        manualApprovalReference,
        stagingApproved,
        productionApproved,
        prototypeAdmissionGranted,
        Object.hashAll(issues),
        Object.hashAll(metadata.entries),
      );
}

Map<String, String> _stringMap(dynamic value) {
  return Map.unmodifiable(
    (value as Map<String, dynamic>? ?? {}).map(
      (key, dynamic value) => MapEntry(key, value.toString()),
    ),
  );
}

List<String> _stringList(dynamic value) {
  return List.unmodifiable(
    (value as List<dynamic>? ?? []).map((e) => e.toString()),
  );
}
