import 'package:masterpalm_platform/masterpalm_platform.dart';

import '../../support/cloud_test_fixtures.dart';
import '../../support/fake_persistent_artifact_cloud_backend_bridge.dart';

class CloudHardeningHelpers {
  const CloudHardeningHelpers._();

  static PersistentArtifactRealCloudAdapterAdmissionCriteria allCriteriaMet() {
    return const PersistentArtifactRealCloudAdapterAdmissionCriteria(
      targetProviderSelected: true,
      protocolSpecificationReviewed: true,
      officialSdkDecisionRecorded: true,
      dependencySecurityReviewApproved: true,
      credentialArchitectureApproved: true,
      leastPrivilegePolicyApproved: true,
      workloadIdentityDecisionApproved: true,
      networkBoundaryApproved: true,
      endpointPolicyApproved: true,
      tlsPolicyApproved: true,
      dataResidencyApproved: true,
      encryptionPolicyApproved: true,
      keyOwnershipApproved: true,
      retentionSemanticsApproved: true,
      legalHoldSemanticsApproved: true,
      deletionSemanticsApproved: true,
      versioningSemanticsApproved: true,
      consistencySemanticsDocumented: true,
      retrySemanticsApproved: true,
      timeoutSemanticsApproved: true,
      idempotencyStrategyApproved: true,
      multipartStrategyApproved: true,
      observabilityPolicyApproved: true,
      secretRedactionApproved: true,
      integrationTestEnvironmentApproved: true,
      costControlsApproved: true,
      rateLimitStrategyApproved: true,
      incidentResponseApproved: true,
      operationalOwnerAssigned: true,
      rollbackPlanApproved: true,
      adrApproved: true,
    );
  }

  static PersistentArtifactCloudOperationRequest putRequest({
    String backendId = 'offline-cloud-ref',
    String requestId = 'hardening-put-1',
    String objectKey = 'releases/v1/evidence.json',
  }) {
    return CloudTestFixtures.operationRequest().copyWith(
      backendId: backendId,
      requestId: requestId,
      operationType: CloudOperationType.putObject,
      objectReference: CloudTestFixtures.objectReference().copyWith(
        objectKey: objectKey,
      ),
    );
  }

  static FakePersistentArtifactCloudBackendBridge bridgeWithCounters() {
    return FakePersistentArtifactCloudBackendBridge();
  }

  static int bridgeCallCount(
    FakePersistentArtifactCloudBackendBridge bridge,
    CloudOperationType operation,
  ) {
    return bridge.operationCounters[operation] ?? 0;
  }
}
