import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_enums.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_models.dart';

class PersistentArtifactCloudValidators {
  const PersistentArtifactCloudValidators._();

  static List<PersistentArtifactCloudIssue> validateProviderType(
    PersistentArtifactCloudProviderType providerType,
  ) {
    if (providerType == PersistentArtifactCloudProviderType.custom) {
      return [
        _issue(
          code: 'CLOUD_PROVIDER_CUSTOM',
          message: 'Custom provider requires explicit governance review.',
          severity: CloudIssueSeverity.warning,
          path: 'providerType',
        ),
      ];
    }
    return const [];
  }

  static List<PersistentArtifactCloudIssue> validateServiceType(
    CloudServiceType serviceType,
  ) {
    if (serviceType == CloudServiceType.custom) {
      return [
        _issue(
          code: 'CLOUD_SERVICE_CUSTOM',
          message: 'Custom service type must be approved explicitly.',
          severity: CloudIssueSeverity.warning,
          path: 'serviceType',
        ),
      ];
    }
    return const [];
  }

  static List<PersistentArtifactCloudIssue> validateEndpointReference(
    PersistentArtifactCloudEndpointReference endpoint,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (endpoint.endpointId.trim().isEmpty) {
      issues.add(_issue(
          code: 'CLOUD_ENDPOINT_ID_EMPTY',
          message: 'Endpoint id is required.',
          path: 'endpointId'));
    }
    if (!endpoint.hostnameReference.contains('.')) {
      issues.add(_issue(
          code: 'CLOUD_ENDPOINT_HOST_INVALID',
          message: 'Hostname reference must contain a domain.',
          path: 'hostnameReference'));
    }
    issues.addAll(
        _sensitiveMaterialIssues(endpoint.metadata, 'endpoint.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateRegionReference(
    PersistentArtifactCloudRegionReference region,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (region.regionId.trim().isEmpty) {
      issues.add(_issue(
          code: 'CLOUD_REGION_ID_EMPTY',
          message: 'Region id is required.',
          path: 'regionId'));
    }
    issues.addAll(_sensitiveMaterialIssues(region.metadata, 'region.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateFailureDomainReference(
    PersistentArtifactCloudFailureDomainReference failureDomain,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (failureDomain.failureDomainId.trim().isEmpty) {
      issues.add(_issue(
          code: 'CLOUD_FAILURE_DOMAIN_ID_EMPTY',
          message: 'Failure domain id is required.',
          path: 'failureDomainId'));
    }
    issues.addAll(_sensitiveMaterialIssues(
        failureDomain.metadata, 'failureDomain.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateContainerReference(
    PersistentArtifactCloudContainerReference container,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (container.containerId.trim().isEmpty) {
      issues.add(_issue(
          code: 'CLOUD_CONTAINER_ID_EMPTY',
          message: 'Container id is required.',
          path: 'containerId'));
    }
    issues.addAll(validateProviderType(container.providerType));
    issues.addAll(
        _sensitiveMaterialIssues(container.metadata, 'container.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateObjectReference(
    PersistentArtifactCloudObjectReference object,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (object.objectKey.trim().isEmpty) {
      issues.add(_issue(
          code: 'CLOUD_OBJECT_KEY_EMPTY',
          message: 'Object key is required.',
          path: 'objectKey'));
    }
    if (object.sizeBytes < 0) {
      issues.add(_issue(
          code: 'CLOUD_OBJECT_SIZE_INVALID',
          message: 'Object size cannot be negative.',
          path: 'sizeBytes'));
    }
    issues
        .addAll(_sensitiveMaterialIssues(object.checksums, 'object.checksums'));
    issues.addAll(_sensitiveMaterialIssues(object.metadata, 'object.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateObjectVersionReference(
    PersistentArtifactCloudObjectVersionReference version,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (version.versionId.trim().isEmpty) {
      issues.add(_issue(
          code: 'CLOUD_VERSION_ID_EMPTY',
          message: 'Version id is required.',
          path: 'versionId'));
    }
    if (version.versionIndex < 0) {
      issues.add(_issue(
          code: 'CLOUD_VERSION_INDEX_INVALID',
          message: 'Version index must be >= 0.',
          path: 'versionIndex'));
    }
    issues
        .addAll(_sensitiveMaterialIssues(version.metadata, 'version.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateAuthenticationReference(
    PersistentArtifactCloudAuthenticationReference authentication,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (authentication.credentialReference.trim().isEmpty) {
      issues.add(_issue(
          code: 'CLOUD_AUTH_REFERENCE_EMPTY',
          message: 'Credential reference is required.',
          path: 'credentialReference'));
    }
    issues.addAll(_sensitiveMaterialIssues(
      {'credentialReference': authentication.credentialReference},
      'authentication.credentialReference',
    ));
    issues.addAll(_sensitiveMaterialIssues(
        authentication.metadata, 'authentication.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateIdentityReference(
    PersistentArtifactCloudIdentityReference identity,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (identity.identityId.trim().isEmpty) {
      issues.add(_issue(
          code: 'CLOUD_IDENTITY_ID_EMPTY',
          message: 'Identity id is required.',
          path: 'identityId'));
    }
    if (identity.tenantId.trim().isEmpty) {
      issues.add(_issue(
          code: 'CLOUD_TENANT_ID_EMPTY',
          message: 'Tenant id is required.',
          path: 'tenantId'));
    }
    issues.addAll(
        _sensitiveMaterialIssues(identity.metadata, 'identity.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateEncryptionCapability(
    PersistentArtifactCloudEncryptionCapability encryption,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (!encryption.atRest || !encryption.inTransit) {
      issues.add(_issue(
          code: 'CLOUD_ENCRYPTION_INCOMPLETE',
          message: 'Encryption at rest and in transit are required.',
          path: 'encryption'));
    }
    if (encryption.keyRotationDays != null &&
        encryption.keyRotationDays! <= 0) {
      issues.add(_issue(
          code: 'CLOUD_KEY_ROTATION_INVALID',
          message: 'keyRotationDays must be > 0.',
          path: 'keyRotationDays'));
    }
    issues.addAll(
        _sensitiveMaterialIssues(encryption.metadata, 'encryption.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateDurabilityDescriptor(
    PersistentArtifactCloudDurabilityDescriptor durability,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (durability.minimumReplicas <= 0) {
      issues.add(_issue(
          code: 'CLOUD_MIN_REPLICAS_INVALID',
          message: 'minimumReplicas must be > 0.',
          path: 'minimumReplicas'));
    }
    if (durability.expectedAvailabilityPercent < 0 ||
        durability.expectedAvailabilityPercent > 100) {
      issues.add(_issue(
          code: 'CLOUD_AVAILABILITY_INVALID',
          message: 'expectedAvailabilityPercent must be between 0 and 100.',
          path: 'expectedAvailabilityPercent'));
    }
    issues.addAll(
        _sensitiveMaterialIssues(durability.metadata, 'durability.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateReplicationDescriptor(
    PersistentArtifactCloudReplicationDescriptor replication,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (replication.mode != CloudReplicationMode.none &&
        replication.targetRegionIds.isEmpty) {
      issues.add(_issue(
          code: 'CLOUD_REPLICATION_TARGETS_EMPTY',
          message: 'Replication mode requires at least one target region.',
          path: 'targetRegionIds'));
    }
    if (replication.maxLagSeconds != null && replication.maxLagSeconds! < 0) {
      issues.add(_issue(
          code: 'CLOUD_REPLICATION_LAG_INVALID',
          message: 'maxLagSeconds must be >= 0.',
          path: 'maxLagSeconds'));
    }
    issues.addAll(
        _sensitiveMaterialIssues(replication.metadata, 'replication.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateConsistencyCapability(
    PersistentArtifactCloudConsistencyCapability consistency,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (!consistency.supportsConditionalWrites &&
        consistency.writeConsistency == CloudConsistencyLevel.strong) {
      issues.add(_issue(
          code: 'CLOUD_CONDITIONAL_WRITE_MISSING',
          message: 'Strong writes should expose conditional write support.',
          path: 'supportsConditionalWrites'));
    }
    issues.addAll(
        _sensitiveMaterialIssues(consistency.metadata, 'consistency.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateMultipartUpload(
    PersistentArtifactCloudMultipartUpload upload,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (upload.partSizeBytes <= 0) {
      issues.add(_issue(
          code: 'CLOUD_MULTIPART_SIZE_INVALID',
          message: 'partSizeBytes must be > 0.',
          path: 'partSizeBytes'));
    }
    issues.addAll(
        _sensitiveMaterialIssues(upload.metadata, 'multipart.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateMultipartPart(
    PersistentArtifactCloudMultipartPart part,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (part.partNumber <= 0) {
      issues.add(_issue(
          code: 'CLOUD_PART_NUMBER_INVALID',
          message: 'partNumber must be > 0.',
          path: 'partNumber'));
    }
    if (part.sizeBytes <= 0) {
      issues.add(_issue(
          code: 'CLOUD_PART_SIZE_INVALID',
          message: 'sizeBytes must be > 0.',
          path: 'sizeBytes'));
    }
    issues.addAll(_sensitiveMaterialIssues(part.metadata, 'part.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateRetryPolicy(
    PersistentArtifactCloudRetryPolicy retryPolicy,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (retryPolicy.maxAttempts <= 0) {
      issues.add(_issue(
          code: 'CLOUD_RETRY_ATTEMPTS_INVALID',
          message: 'maxAttempts must be > 0.',
          path: 'maxAttempts'));
    }
    if (retryPolicy.baseDelayMs < 0 ||
        retryPolicy.maxDelayMs < retryPolicy.baseDelayMs) {
      issues.add(_issue(
          code: 'CLOUD_RETRY_DELAYS_INVALID',
          message: 'Retry delay values are invalid.',
          path: 'baseDelayMs'));
    }
    issues.addAll(
        _sensitiveMaterialIssues(retryPolicy.metadata, 'retryPolicy.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateTimeoutPolicy(
    PersistentArtifactCloudTimeoutPolicy timeoutPolicy,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (timeoutPolicy.connectTimeoutMs <= 0 ||
        timeoutPolicy.readTimeoutMs <= 0 ||
        timeoutPolicy.writeTimeoutMs <= 0) {
      issues.add(_issue(
          code: 'CLOUD_TIMEOUT_INVALID',
          message: 'All timeout values must be > 0.',
          path: 'timeoutPolicy'));
    }
    issues.addAll(_sensitiveMaterialIssues(
        timeoutPolicy.metadata, 'timeoutPolicy.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateOperationRequest(
    PersistentArtifactCloudOperationRequest request,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (request.requestId.trim().isEmpty) {
      issues.add(_issue(
          code: 'CLOUD_REQUEST_ID_EMPTY',
          message: 'requestId is required.',
          path: 'requestId'));
    }
    if (request.backendId.trim().isEmpty) {
      issues.add(_issue(
          code: 'CLOUD_BACKEND_ID_EMPTY',
          message: 'backendId is required.',
          path: 'backendId'));
    }
    if (request.objectReference != null) {
      issues.addAll(validateObjectReference(request.objectReference!));
    }
    if (request.destinationObjectReference != null) {
      issues
          .addAll(validateObjectReference(request.destinationObjectReference!));
    }
    if (request.expectedVersionReference != null) {
      issues.addAll(
          validateObjectVersionReference(request.expectedVersionReference!));
    }
    if (request.multipartUpload != null) {
      issues.addAll(validateMultipartUpload(request.multipartUpload!));
    }
    if (request.retryPolicy != null) {
      issues.addAll(validateRetryPolicy(request.retryPolicy!));
    }
    if (request.timeoutPolicy != null) {
      issues.addAll(validateTimeoutPolicy(request.timeoutPolicy!));
    }
    issues
        .addAll(_sensitiveMaterialIssues(request.metadata, 'request.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateOperationResult(
    PersistentArtifactCloudOperationResult result,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    if (result.requestId.trim().isEmpty) {
      issues.add(_issue(
          code: 'CLOUD_RESULT_REQUEST_ID_EMPTY',
          message: 'requestId is required.',
          path: 'requestId'));
    }
    issues.addAll(result.issues);
    issues.addAll(_sensitiveMaterialIssues(result.metadata, 'result.metadata'));
    return issues;
  }

  static List<PersistentArtifactCloudIssue> validateBackendDescriptor(
    PersistentArtifactCloudBackendDescriptor descriptor,
  ) {
    final issues = <PersistentArtifactCloudIssue>[];
    issues.addAll(validateProviderType(descriptor.providerType));
    issues.addAll(validateServiceType(descriptor.serviceType));
    issues.addAll(validateEndpointReference(descriptor.endpoint));
    issues.addAll(validateRegionReference(descriptor.region));
    issues.addAll(validateContainerReference(descriptor.container));
    issues.addAll(validateEncryptionCapability(descriptor.encryption));
    issues.addAll(validateReplicationDescriptor(descriptor.replication));
    issues.addAll(validateConsistencyCapability(descriptor.consistency));
    issues.addAll(validateRetryPolicy(descriptor.retryPolicy));
    issues.addAll(validateTimeoutPolicy(descriptor.timeoutPolicy));
    if (descriptor.failureDomain != null) {
      issues.addAll(validateFailureDomainReference(descriptor.failureDomain!));
    }
    if (descriptor.authentication != null) {
      issues
          .addAll(validateAuthenticationReference(descriptor.authentication!));
    }
    if (descriptor.identity != null) {
      issues.addAll(validateIdentityReference(descriptor.identity!));
    }
    if (descriptor.productionEligible) {
      issues.add(
        _issue(
          code: 'CLOUD_PRODUCTION_BLOCKED',
          message: 'productionEligible must remain false in Part 1.',
          severity: CloudIssueSeverity.critical,
          path: 'productionEligible',
        ),
      );
    }
    issues.addAll(
        _sensitiveMaterialIssues(descriptor.metadata, 'descriptor.metadata'));
    return issues;
  }

  static PersistentArtifactCloudIssue _issue({
    required String code,
    required String message,
    CloudIssueSeverity severity = CloudIssueSeverity.critical,
    String? path,
  }) {
    return PersistentArtifactCloudIssue(
      code: code,
      message: message,
      severity: severity,
      path: path,
    );
  }

  static List<PersistentArtifactCloudIssue> _sensitiveMaterialIssues(
    Map<String, String> values,
    String path,
  ) {
    const blockedTerms = <String>[
      'accesskey',
      'secretkey',
      'token',
      'password',
      'presigned',
      'jwt',
    ];
    final issues = <PersistentArtifactCloudIssue>[];
    final presignedPattern = RegExp(
        r'https?://[^\s]+\?.*(x-amz-signature|sig=)',
        caseSensitive: false);
    final jwtPattern =
        RegExp(r'^[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+$');

    for (final entry in values.entries) {
      final normalizedKey =
          entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final value = entry.value.trim();
      final normalizedValue =
          value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

      final containsBlockedTerm = blockedTerms.any(
        (term) =>
            normalizedKey.contains(term) || normalizedValue.contains(term),
      );
      if (containsBlockedTerm ||
          presignedPattern.hasMatch(value) ||
          jwtPattern.hasMatch(value)) {
        issues.add(
          _issue(
            code: 'CLOUD_SENSITIVE_MATERIAL',
            message:
                'Sensitive material detected in cloud contracts. Store only references.',
            severity: CloudIssueSeverity.critical,
            path: '$path.${entry.key}',
          ),
        );
      }
    }
    return issues;
  }
}
