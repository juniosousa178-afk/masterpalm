import 'package:masterpalm_platform/masterpalm_platform.dart';

class CloudTestFixtures {
  const CloudTestFixtures._();

  static PersistentArtifactCloudEndpointReference endpoint() =>
      const PersistentArtifactCloudEndpointReference(
        endpointId: 'endpoint-1',
        serviceType: CloudServiceType.objectStorage,
        endpointType: CloudEndpointType.dataPlane,
        regionId: 'sa-east-1',
        hostnameReference: 'storage.example.invalid',
        pathPrefix: '/tenant-a',
        metadata: {'owner': 'qa'},
      );

  static PersistentArtifactCloudRegionReference region() =>
      const PersistentArtifactCloudRegionReference(
        regionId: 'sa-east-1',
        providerRegionReference: 'southamerica-east1',
        status: CloudRegionStatus.healthy,
        zones: ['sa-east-1a', 'sa-east-1b', 'sa-east-1c'],
        metadata: {'compliance': 'pci'},
      );

  static PersistentArtifactCloudFailureDomainReference failureDomain() =>
      const PersistentArtifactCloudFailureDomainReference(
        failureDomainId: 'fd-1',
        regionId: 'sa-east-1',
        rackHints: ['rack-a', 'rack-b'],
      );

  static PersistentArtifactCloudContainerReference container() =>
      const PersistentArtifactCloudContainerReference(
        containerId: 'container-1',
        providerType: PersistentArtifactCloudProviderType.s3Compatible,
        namespaceReference: 'tenant-a-artifacts',
        regionId: 'sa-east-1',
      );

  static PersistentArtifactCloudObjectReference objectReference() =>
      const PersistentArtifactCloudObjectReference(
        objectId: 'object-1',
        containerId: 'container-1',
        objectKey: 'releases/v1/evidence.json',
        status: CloudObjectStatus.available,
        sizeBytes: 2048,
        etag: 'etag-1',
        checksums: {
          'sha256':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        },
      );

  static PersistentArtifactCloudObjectVersionReference objectVersion() =>
      const PersistentArtifactCloudObjectVersionReference(
        versionId: 'version-1',
        objectId: 'object-1',
        providerVersionReference: 'provider-v1',
        versionIndex: 1,
      );

  static PersistentArtifactCloudAuthenticationReference authentication() =>
      const PersistentArtifactCloudAuthenticationReference(
        authenticationId: 'auth-1',
        authenticationType: CloudAuthenticationType.serviceAccountReference,
        identityId: 'identity-1',
        credentialReference: 'secret://tenant-a/cloud-auth',
        scope: ['read', 'write'],
      );

  static PersistentArtifactCloudIdentityReference identity() =>
      const PersistentArtifactCloudIdentityReference(
        identityId: 'identity-1',
        identityType: CloudIdentityType.workloadIdentity,
        subjectReference: 'svc:platform-artifacts',
        tenantId: 'tenant-a',
      );

  static PersistentArtifactCloudEncryptionCapability encryption() =>
      const PersistentArtifactCloudEncryptionCapability(
        mode: CloudEncryptionMode.customerManaged,
        atRest: true,
        inTransit: true,
        keyRotationDays: 90,
      );

  static PersistentArtifactCloudDurabilityDescriptor durability() =>
      const PersistentArtifactCloudDurabilityDescriptor(
        minimumReplicas: 2,
        failureDomainDiversity: 2,
        expectedAvailabilityPercent: 99.99,
      );

  static PersistentArtifactCloudReplicationDescriptor replication() =>
      const PersistentArtifactCloudReplicationDescriptor(
        mode: CloudReplicationMode.multiRegion,
        sourceRegionId: 'sa-east-1',
        targetRegionIds: ['sa-east-1', 'us-east-1'],
        maxLagSeconds: 10,
      );

  static PersistentArtifactCloudConsistencyCapability consistency() =>
      const PersistentArtifactCloudConsistencyCapability(
        readConsistency: CloudConsistencyLevel.readAfterWrite,
        writeConsistency: CloudConsistencyLevel.strong,
        supportsConditionalWrites: true,
      );

  static PersistentArtifactCloudMultipartUpload multipartUpload() =>
      const PersistentArtifactCloudMultipartUpload(
        multipartId: 'mp-1',
        objectId: 'object-1',
        status: CloudMultipartStatus.uploading,
        partSizeBytes: 5242880,
        uploadedPartNumbers: [1, 2],
      );

  static PersistentArtifactCloudMultipartPart multipartPart() =>
      const PersistentArtifactCloudMultipartPart(
        partNumber: 1,
        sizeBytes: 5242880,
        etag: 'part-etag-1',
        checksum:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );

  static PersistentArtifactCloudRetryPolicy retryPolicy() =>
      const PersistentArtifactCloudRetryPolicy(
        maxAttempts: 4,
        baseDelayMs: 100,
        maxDelayMs: 1000,
        retryableClassifications: [
          CloudRetryClassification.transient,
          CloudRetryClassification.timeout,
        ],
      );

  static PersistentArtifactCloudTimeoutPolicy timeoutPolicy() =>
      const PersistentArtifactCloudTimeoutPolicy(
        connectTimeoutMs: 250,
        readTimeoutMs: 5000,
        writeTimeoutMs: 5000,
      );

  static PersistentArtifactCloudOperationRequest operationRequest() =>
      PersistentArtifactCloudOperationRequest(
        requestId: 'request-1',
        backendId: 'cloud-backend-1',
        operationType: CloudOperationType.putObject,
        objectReference: objectReference(),
        expectedVersionReference: objectVersion(),
        multipartUpload: multipartUpload(),
        retryPolicy: retryPolicy(),
        timeoutPolicy: timeoutPolicy(),
        metadata: const {'traceId': 'trace-1'},
      );

  static PersistentArtifactCloudIssue issue({
    String code = 'ISSUE_1',
    CloudIssueSeverity severity = CloudIssueSeverity.warning,
  }) =>
      PersistentArtifactCloudIssue(
        code: code,
        message: 'Issue message $code',
        severity: severity,
      );

  static PersistentArtifactCloudOperationResult operationResult() =>
      PersistentArtifactCloudOperationResult(
        requestId: 'request-1',
        operationType: CloudOperationType.putObject,
        status: CloudOperationStatus.succeeded,
        objectReference: objectReference(),
        versionReference: objectVersion(),
        multipartStatus: CloudMultipartStatus.completed,
        issues: [issue()],
      );

  static PersistentArtifactCloudBackendDescriptor backendDescriptor({
    bool stagingEligible = false,
    bool productionEligible = false,
  }) =>
      PersistentArtifactCloudBackendDescriptor(
        backendId: 'cloud-backend-1',
        providerType: PersistentArtifactCloudProviderType.s3Compatible,
        serviceType: CloudServiceType.objectStorage,
        endpoint: endpoint(),
        region: region(),
        container: container(),
        encryption: encryption(),
        replication: replication(),
        consistency: consistency(),
        retryPolicy: retryPolicy(),
        timeoutPolicy: timeoutPolicy(),
        failureDomain: failureDomain(),
        authentication: authentication(),
        identity: identity(),
        stagingEligible: stagingEligible,
        productionEligible: productionEligible,
        metadata: const {'owner': 'platform'},
      );

  static PersistentArtifactCloudStagingPromotionCriteria promotionCriteria() =>
      PersistentArtifactCloudStagingPromotionCriteria(
        criteriaId: 'criteria-1',
        minimumDurability: durability(),
        requiredReplicationMode: CloudReplicationMode.multiRegion,
        requiredReadConsistency: CloudConsistencyLevel.readAfterWrite,
        requireEncryptionAtRest: true,
        requireEncryptionInTransit: true,
        requiredMetadataKeys: const ['owner'],
      );

  static PersistentArtifactCloudStagingReadinessDecision readinessDecision({
    bool approved = false,
  }) =>
      PersistentArtifactCloudStagingReadinessDecision(
        backendId: 'cloud-backend-1',
        criteriaId: 'criteria-1',
        status: approved
            ? CloudPromotionStatus.approved
            : CloudPromotionStatus.blocked,
        stagingEligible: false,
        productionEligible: false,
        approved: approved,
        issues: [issue()],
      );
}
