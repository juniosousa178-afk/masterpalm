import '../models/persistent_artifacts/persistent_artifact_availability_record.dart';
import '../models/persistent_artifacts/persistent_artifact_content_descriptor.dart';
import '../models/persistent_artifacts/persistent_artifact_deletion_models.dart';
import '../models/persistent_artifacts/persistent_artifact_encryption_descriptor.dart';
import '../models/persistent_artifacts/persistent_artifact_enums.dart';
import '../models/persistent_artifacts/persistent_artifact_infrastructure_snapshot.dart';
import '../models/persistent_artifacts/persistent_artifact_integrity_record.dart';
import '../models/persistent_artifacts/persistent_artifact_lifecycle_record.dart';
import '../models/persistent_artifacts/persistent_artifact_location_reference.dart';
import '../models/persistent_artifacts/persistent_artifact_manifest.dart';
import '../models/persistent_artifacts/persistent_artifact_operation_models.dart';
import '../models/persistent_artifacts/persistent_artifact_policy_models.dart';
import '../models/persistent_artifacts/persistent_artifact_publication_record.dart';
import '../models/persistent_artifacts/persistent_artifact_replica_record.dart';
import '../models/persistent_artifacts/persistent_artifact_replication_requirement.dart';
import '../models/persistent_artifacts/persistent_artifact_retention_record.dart';
import '../models/persistent_artifacts/persistent_artifact_subject.dart';
import '../models/persistent_artifacts/persistent_artifact_validation_result.dart';
import '../models/persistent_artifacts/persistent_artifact_version.dart';
import 'persistent_artifact_validation_helpers.dart';

/// Validates structural consistency of [PersistentArtifactSubject].
class PersistentArtifactSubjectValidator {
  const PersistentArtifactSubjectValidator();

  PersistentArtifactValidationResult validate(
      PersistentArtifactSubject subject) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId,
        versionId: versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (subject.subjectId.isEmpty) {
      addError('PA_SUBJECT_ID', 'subjectId', 'subjectId is required');
    }
    if (subject.projectId.isEmpty) {
      addError('PA_SUBJECT_PROJECT_ID', 'projectId', 'projectId is required');
    }
    if (subject.sourceId.isEmpty) {
      addError('PA_SUBJECT_SOURCE_ID', 'sourceId', 'sourceId is required');
    }
    if (subject.sourceFingerprint.isEmpty) {
      addError(
        'PA_SUBJECT_SOURCE_FINGERPRINT',
        'sourceFingerprint',
        'sourceFingerprint is required',
      );
    }
    if (subject.sourceModule.isEmpty) {
      addError(
        'PA_SUBJECT_SOURCE_MODULE',
        'sourceModule',
        'sourceModule is required',
      );
    }

    validateSensitiveMetadata(subject.metadata, 'metadata', addError);
    validateReleaseAuthorizationMetadata(
        subject.metadata, 'metadata', addError);

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactContentDescriptor].
class PersistentArtifactContentDescriptorValidator {
  const PersistentArtifactContentDescriptorValidator();

  PersistentArtifactValidationResult validate(
    PersistentArtifactContentDescriptor content, {
    String pathPrefix = '',
  }) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];
    final prefix = pathPrefix.isEmpty ? '' : '$pathPrefix.';

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId,
        versionId: versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (content.contentId.isEmpty) {
      addError('PA_CONTENT_ID', '${prefix}contentId', 'contentId is required');
    }
    if (content.mediaType.isEmpty) {
      addError(
        'PA_CONTENT_MEDIA_TYPE',
        '${prefix}mediaType',
        'mediaType is required',
      );
    }
    if (content.contentFingerprint.isEmpty) {
      addError(
        'PA_CONTENT_FINGERPRINT',
        '${prefix}contentFingerprint',
        'contentFingerprint is required',
      );
    }
    if (content.sizeBytes != null && content.sizeBytes! < 0) {
      addError(
        'PA_CONTENT_SIZE_BYTES',
        '${prefix}sizeBytes',
        'sizeBytes must be >= 0',
      );
    }
    if (content.canonicalDigest != null &&
        content.canonicalDigest!.isNotEmpty &&
        !isStructurallyValidHexDigest(content.canonicalDigest!)) {
      addError(
        'PA_CONTENT_CANONICAL_DIGEST',
        '${prefix}canonicalDigest',
        'canonicalDigest must be a non-empty even-length hex string',
      );
    }

    validateSensitiveMetadata(
      content.metadata,
      '${prefix}metadata',
      addError,
    );

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactLocationReference].
class PersistentArtifactLocationValidator {
  const PersistentArtifactLocationValidator();

  PersistentArtifactValidationResult validate(
    PersistentArtifactLocationReference location, {
    String pathPrefix = '',
  }) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];
    final prefix = pathPrefix.isEmpty ? '' : '$pathPrefix.';

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId,
        versionId: versionId,
        locationId: locationId ?? location.locationId,
        policyId: policyId,
      );
    }

    if (location.locationId.isEmpty) {
      addError(
        'PA_LOCATION_ID',
        '${prefix}locationId',
        'locationId is required',
      );
    }
    if (location.storageNamespace.isEmpty) {
      addError(
        'PA_LOCATION_STORAGE_NAMESPACE',
        '${prefix}storageNamespace',
        'storageNamespace is required',
      );
    }
    if (location.objectKey.isEmpty) {
      addError(
        'PA_LOCATION_OBJECT_KEY',
        '${prefix}objectKey',
        'objectKey is required',
      );
    }
    if (location.contentFingerprint.isEmpty) {
      addError(
        'PA_LOCATION_CONTENT_FINGERPRINT',
        '${prefix}contentFingerprint',
        'contentFingerprint is required',
      );
    }

    validateSensitiveMetadata(
      location.metadata,
      '${prefix}metadata',
      addError,
      code: 'PA_LOCATION_SENSITIVE_METADATA',
    );
    validatePresignedMetadataValues(
      location.metadata,
      '${prefix}metadata',
      addError,
    );

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactVersion].
class PersistentArtifactVersionValidator {
  const PersistentArtifactVersionValidator({
    PersistentArtifactContentDescriptorValidator? contentDescriptorValidator,
  }) : _contentDescriptorValidator = contentDescriptorValidator ??
            const PersistentArtifactContentDescriptorValidator();

  final PersistentArtifactContentDescriptorValidator
      _contentDescriptorValidator;

  PersistentArtifactValidationResult validate(
    PersistentArtifactVersion version,
  ) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void merge(PersistentArtifactValidationResult result) {
      issues.addAll(result.issues);
      warnings.addAll(result.warnings);
      errors.addAll(result.errors);
    }

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId ?? version.artifactId,
        versionId: versionId ?? version.versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (version.artifactId.isEmpty) {
      addError(
          'PA_VERSION_ARTIFACT_ID', 'artifactId', 'artifactId is required');
    }
    if (version.versionId.isEmpty) {
      addError('PA_VERSION_ID', 'versionId', 'versionId is required');
    }
    if (version.revision < 1) {
      addError('PA_VERSION_REVISION', 'revision', 'revision must be >= 1');
    }
    if (version.parentVersionId != null &&
        version.parentVersionId == version.versionId) {
      addError(
        'PA_VERSION_PARENT_SELF',
        'parentVersionId',
        'parentVersionId must not equal versionId',
      );
    }
    if (!isIsoDateRangeCoherent(version.createdAt, version.supersededAt)) {
      addError(
        'PA_VERSION_SUPERSEDED_AT',
        'supersededAt',
        'supersededAt must be >= createdAt',
      );
    }
    if (version.status == PersistentArtifactVersionStatus.superseded &&
        (version.supersededAt == null || version.supersededAt!.isEmpty)) {
      addError(
        'PA_VERSION_SUPERSEDED_STATUS',
        'supersededAt',
        'supersededAt is required when status is superseded',
      );
    }

    merge(
      _contentDescriptorValidator.validate(
        version.contentDescriptor,
        pathPrefix: 'contentDescriptor',
      ),
    );
    validateSensitiveMetadata(version.metadata, 'metadata', addError);

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactManifest].
class PersistentArtifactManifestValidator {
  const PersistentArtifactManifestValidator({
    PersistentArtifactSubjectValidator? subjectValidator,
    PersistentArtifactContentDescriptorValidator? contentDescriptorValidator,
    PersistentArtifactLocationValidator? locationValidator,
    PersistentArtifactIntegrityValidator? integrityValidator,
  })  : _subjectValidator =
            subjectValidator ?? const PersistentArtifactSubjectValidator(),
        _contentDescriptorValidator = contentDescriptorValidator ??
            const PersistentArtifactContentDescriptorValidator(),
        _locationValidator =
            locationValidator ?? const PersistentArtifactLocationValidator(),
        _integrityValidator =
            integrityValidator ?? const PersistentArtifactIntegrityValidator();

  final PersistentArtifactSubjectValidator _subjectValidator;
  final PersistentArtifactContentDescriptorValidator
      _contentDescriptorValidator;
  final PersistentArtifactLocationValidator _locationValidator;
  final PersistentArtifactIntegrityValidator _integrityValidator;

  PersistentArtifactValidationResult validate(
    PersistentArtifactManifest manifest,
  ) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void merge(PersistentArtifactValidationResult result) {
      issues.addAll(result.issues);
      warnings.addAll(result.warnings);
      errors.addAll(result.errors);
    }

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId ?? manifest.artifactId,
        versionId: versionId ?? manifest.versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (manifest.manifestId.isEmpty) {
      addError('PA_MANIFEST_ID', 'manifestId', 'manifestId is required');
    }
    if (manifest.artifactId.isEmpty) {
      addError(
          'PA_MANIFEST_ARTIFACT_ID', 'artifactId', 'artifactId is required');
    }
    if (manifest.versionId.isEmpty) {
      addError('PA_MANIFEST_VERSION_ID', 'versionId', 'versionId is required');
    }

    merge(_subjectValidator.validate(manifest.subject));
    merge(
      _contentDescriptorValidator.validate(
        manifest.contentDescriptor,
        pathPrefix: 'contentDescriptor',
      ),
    );

    if (manifest.contentDescriptor.contentFingerprint !=
        manifest.subject.sourceFingerprint) {
      addPersistentArtifactValidationWarning(
        issues,
        warnings,
        code: 'PA_MANIFEST_SUBJECT_CONTENT',
        path: 'contentDescriptor.contentFingerprint',
        message:
            'contentDescriptor fingerprint differs from subject sourceFingerprint',
        artifactId: manifest.artifactId,
        versionId: manifest.versionId,
      );
    }

    final locationIds = <String>{};
    for (final location in manifest.locations) {
      if (!locationIds.add(location.locationId)) {
        addError(
          'PA_MANIFEST_DUPLICATE_LOCATION',
          'locations',
          'duplicate locationId: ${location.locationId}',
          locationId: location.locationId,
        );
      }
      if (location.contentFingerprint !=
          manifest.contentDescriptor.contentFingerprint) {
        addError(
          'PA_MANIFEST_LOCATION_FINGERPRINT',
          'locations.${location.locationId}.contentFingerprint',
          'location contentFingerprint does not match manifest contentDescriptor',
          locationId: location.locationId,
        );
      }
      merge(
        _locationValidator.validate(
          location,
          pathPrefix: 'locations.${location.locationId}',
        ),
      );
    }

    final integrityIds = <String>{};
    for (final record in manifest.integrityRecords) {
      if (!integrityIds.add(record.integrityRecordId)) {
        addError(
          'PA_MANIFEST_DUPLICATE_INTEGRITY',
          'integrityRecords',
          'duplicate integrityRecordId: ${record.integrityRecordId}',
        );
      }
      if (record.artifactId != manifest.artifactId) {
        addError(
          'PA_MANIFEST_INTEGRITY_ARTIFACT',
          'integrityRecords.${record.integrityRecordId}.artifactId',
          'integrity record artifactId does not match manifest',
        );
      }
      if (record.versionId != manifest.versionId) {
        addError(
          'PA_MANIFEST_INTEGRITY_VERSION',
          'integrityRecords.${record.integrityRecordId}.versionId',
          'integrity record versionId does not match manifest',
        );
      }
      if (record.contentFingerprint !=
          manifest.contentDescriptor.contentFingerprint) {
        addError(
          'PA_MANIFEST_INTEGRITY_FINGERPRINT',
          'integrityRecords.${record.integrityRecordId}.contentFingerprint',
          'integrity record contentFingerprint does not match manifest contentDescriptor',
        );
      }
      merge(_integrityValidator.validate(record));
    }

    validateSensitiveMetadata(manifest.metadata, 'metadata', addError);

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactIntegrityRecord].
class PersistentArtifactIntegrityValidator {
  const PersistentArtifactIntegrityValidator();

  PersistentArtifactValidationResult validate(
    PersistentArtifactIntegrityRecord record, {
    String pathPrefix = '',
  }) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];
    final prefix = pathPrefix.isEmpty ? '' : '$pathPrefix.';

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId ?? record.artifactId,
        versionId: versionId ?? record.versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (record.integrityRecordId.isEmpty) {
      addError(
        'PA_INTEGRITY_RECORD_ID',
        '${prefix}integrityRecordId',
        'integrityRecordId is required',
      );
    }
    if (record.artifactId.isEmpty) {
      addError(
        'PA_INTEGRITY_ARTIFACT_ID',
        '${prefix}artifactId',
        'artifactId is required',
      );
    }
    if (record.versionId.isEmpty) {
      addError(
        'PA_INTEGRITY_VERSION_ID',
        '${prefix}versionId',
        'versionId is required',
      );
    }
    if (record.digestAlgorithmId.isEmpty) {
      addError(
        'PA_INTEGRITY_ALGORITHM_ID',
        '${prefix}digestAlgorithmId',
        'digestAlgorithmId is required',
      );
    }
    if (record.digestValue.isEmpty) {
      addError(
        'PA_INTEGRITY_DIGEST_VALUE',
        '${prefix}digestValue',
        'digestValue is required',
      );
    }
    if (record.contentFingerprint.isEmpty) {
      addError(
        'PA_INTEGRITY_CONTENT_FINGERPRINT',
        '${prefix}contentFingerprint',
        'contentFingerprint is required',
      );
    }

    validateSensitiveMetadata(
      record.metadata,
      '${prefix}metadata',
      addError,
      code: 'PA_INTEGRITY_SENSITIVE_METADATA',
    );

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactEncryptionDescriptor].
class PersistentArtifactEncryptionDescriptorValidator {
  const PersistentArtifactEncryptionDescriptorValidator();

  PersistentArtifactValidationResult validate(
    PersistentArtifactEncryptionDescriptor descriptor, {
    String pathPrefix = '',
  }) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];
    final prefix = pathPrefix.isEmpty ? '' : '$pathPrefix.';

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId,
        versionId: versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (descriptor.encryptionStatus !=
            PersistentArtifactEncryptionStatus.none &&
        (descriptor.algorithmId == null || descriptor.algorithmId!.isEmpty)) {
      addError(
        'PA_ENCRYPTION_ALGORITHM_ID',
        '${prefix}algorithmId',
        'algorithmId is required when encryption is declared',
      );
    }

    validateSensitiveMetadata(
      descriptor.metadata,
      '${prefix}metadata',
      addError,
      code: 'PA_ENCRYPTION_SENSITIVE_METADATA',
    );
    validatePresignedMetadataValues(
      descriptor.metadata,
      '${prefix}metadata',
      addError,
      code: 'PA_ENCRYPTION_PRESIGNED_METADATA',
    );

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactPublicationRecord].
class PersistentArtifactPublicationValidator {
  const PersistentArtifactPublicationValidator({
    PersistentArtifactLocationValidator? locationValidator,
  }) : _locationValidator =
            locationValidator ?? const PersistentArtifactLocationValidator();

  final PersistentArtifactLocationValidator _locationValidator;

  PersistentArtifactValidationResult validate(
    PersistentArtifactPublicationRecord publication,
  ) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void merge(PersistentArtifactValidationResult result) {
      issues.addAll(result.issues);
      warnings.addAll(result.warnings);
      errors.addAll(result.errors);
    }

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId ?? publication.artifactId,
        versionId: versionId ?? publication.versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (publication.publicationId.isEmpty) {
      addError(
        'PA_PUBLICATION_ID',
        'publicationId',
        'publicationId is required',
      );
    }
    if (publication.artifactId.isEmpty) {
      addError(
        'PA_PUBLICATION_ARTIFACT_ID',
        'artifactId',
        'artifactId is required',
      );
    }
    if (publication.versionId.isEmpty) {
      addError(
        'PA_PUBLICATION_VERSION_ID',
        'versionId',
        'versionId is required',
      );
    }
    if (publication.publicationStatus ==
            PersistentArtifactPublicationStatus.published &&
        publication.publishedLocations.isEmpty) {
      addError(
        'PA_PUBLICATION_LOCATIONS',
        'publishedLocations',
        'publishedLocations must not be empty when status is published',
      );
    }

    final locationIds = <String>{};
    for (final location in publication.publishedLocations) {
      if (!locationIds.add(location.locationId)) {
        addError(
          'PA_PUBLICATION_DUPLICATE_LOCATION',
          'publishedLocations',
          'duplicate locationId: ${location.locationId}',
          locationId: location.locationId,
        );
      }
      merge(
        _locationValidator.validate(
          location,
          pathPrefix: 'publishedLocations.${location.locationId}',
        ),
      );
    }

    validateReleaseAuthorizationMetadata(
      publication.metadata,
      'metadata',
      addError,
    );
    validateSensitiveMetadata(
      publication.metadata,
      'metadata',
      addError,
      code: 'PA_PUBLICATION_SENSITIVE_METADATA',
    );

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

int _lifecycleStatusOrdinal(PersistentArtifactLifecycleStatus status) {
  switch (status) {
    case PersistentArtifactLifecycleStatus.created:
      return 0;
    case PersistentArtifactLifecycleStatus.published:
      return 1;
    case PersistentArtifactLifecycleStatus.retained:
      return 2;
    case PersistentArtifactLifecycleStatus.expired:
      return 3;
    case PersistentArtifactLifecycleStatus.deletionRequested:
      return 4;
    case PersistentArtifactLifecycleStatus.deleted:
      return 5;
    case PersistentArtifactLifecycleStatus.tombstoned:
      return 6;
    case PersistentArtifactLifecycleStatus.unknown:
      return -1;
  }
}

/// Validates structural consistency of [PersistentArtifactLifecycleRecord].
class PersistentArtifactLifecycleValidator {
  const PersistentArtifactLifecycleValidator();

  PersistentArtifactValidationResult validate(
    PersistentArtifactLifecycleRecord record,
  ) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId ?? record.artifactId,
        versionId: versionId ?? record.versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (record.lifecycleRecordId.isEmpty) {
      addError(
        'PA_LIFECYCLE_RECORD_ID',
        'lifecycleRecordId',
        'lifecycleRecordId is required',
      );
    }
    if (record.artifactId.isEmpty) {
      addError(
          'PA_LIFECYCLE_ARTIFACT_ID', 'artifactId', 'artifactId is required');
    }
    if (record.versionId.isEmpty) {
      addError('PA_LIFECYCLE_VERSION_ID', 'versionId', 'versionId is required');
    }

    final previous = record.previousStatus;
    if (previous != null && previous == record.lifecycleStatus) {
      addError(
        'PA_LIFECYCLE_TRANSITION_SAME',
        'lifecycleStatus',
        'lifecycleStatus must differ from previousStatus',
      );
    }
    if (previous != null) {
      final previousOrdinal = _lifecycleStatusOrdinal(previous);
      final currentOrdinal = _lifecycleStatusOrdinal(record.lifecycleStatus);
      if (previousOrdinal >= 0 &&
          currentOrdinal >= 0 &&
          currentOrdinal < previousOrdinal) {
        addError(
          'PA_LIFECYCLE_TRANSITION_BACKWARD',
          'lifecycleStatus',
          'lifecycle transition is not coherent: ${previous.wireName} -> ${record.lifecycleStatus.wireName}',
        );
      }
    }

    validateSensitiveMetadata(record.metadata, 'metadata', addError);

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactRetentionPolicy].
class PersistentArtifactRetentionPolicyValidator {
  const PersistentArtifactRetentionPolicyValidator();

  PersistentArtifactValidationResult validate(
    PersistentArtifactRetentionPolicy policy,
  ) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId,
        versionId: versionId,
        locationId: locationId,
        policyId: policyId ?? policy.policyId,
      );
    }

    if (policy.policyId.isEmpty) {
      addError('PA_RETENTION_POLICY_ID', 'policyId', 'policyId is required');
    }
    if (policy.version < 1) {
      addError(
          'PA_RETENTION_POLICY_VERSION', 'version', 'version must be >= 1');
    }
    if (policy.name.isEmpty) {
      addError('PA_RETENTION_POLICY_NAME', 'name', 'name is required');
    }
    if (policy.minimumRetention.isEmpty) {
      addError(
        'PA_RETENTION_POLICY_MINIMUM',
        'minimumRetention',
        'minimumRetention is required',
      );
    }
    if (policy.artifactTypes.isEmpty) {
      addError(
        'PA_RETENTION_POLICY_ARTIFACT_TYPES',
        'artifactTypes',
        'artifactTypes must not be empty',
      );
    }

    if (!isIsoDateRangeCoherent(policy.effectiveFrom, policy.deprecatedAt)) {
      addError(
        'PA_RETENTION_POLICY_DEPRECATED',
        'deprecatedAt',
        'deprecatedAt must be >= effectiveFrom',
      );
    }
    if (!isIsoDateRangeCoherent(policy.deprecatedAt, policy.retiredAt)) {
      addError(
        'PA_RETENTION_POLICY_RETIRED',
        'retiredAt',
        'retiredAt must be >= deprecatedAt',
      );
    }

    validateSensitiveMetadata(policy.metadata, 'metadata', addError);

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactStoragePolicy].
class PersistentArtifactStoragePolicyValidator {
  const PersistentArtifactStoragePolicyValidator();

  PersistentArtifactValidationResult validate(
    PersistentArtifactStoragePolicy policy,
  ) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId,
        versionId: versionId,
        locationId: locationId,
        policyId: policyId ?? policy.policyId,
      );
    }

    if (policy.policyId.isEmpty) {
      addError('PA_STORAGE_POLICY_ID', 'policyId', 'policyId is required');
    }
    if (policy.version < 1) {
      addError('PA_STORAGE_POLICY_VERSION', 'version', 'version must be >= 1');
    }
    if (policy.name.isEmpty) {
      addError('PA_STORAGE_POLICY_NAME', 'name', 'name is required');
    }
    if (policy.minimumReplicaCount < 1) {
      addError(
        'PA_STORAGE_POLICY_REPLICA_COUNT',
        'minimumReplicaCount',
        'minimumReplicaCount must be >= 1',
      );
    }
    if (policy.allowedLocationTypes.isEmpty) {
      addError(
        'PA_STORAGE_POLICY_LOCATION_TYPES',
        'allowedLocationTypes',
        'allowedLocationTypes must not be empty',
      );
    }
    if (policy.allowedStorageClasses.isEmpty) {
      addError(
        'PA_STORAGE_POLICY_STORAGE_CLASSES',
        'allowedStorageClasses',
        'allowedStorageClasses must not be empty',
      );
    }

    validateSensitiveMetadata(policy.metadata, 'metadata', addError);
    validateReleaseAuthorizationMetadata(policy.metadata, 'metadata', addError);

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactReplicationRequirement].
class PersistentArtifactReplicationRequirementValidator {
  const PersistentArtifactReplicationRequirementValidator();

  PersistentArtifactValidationResult validate(
    PersistentArtifactReplicationRequirement requirement,
  ) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId ?? requirement.artifactId,
        versionId: versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (requirement.requirementId.isEmpty) {
      addError(
        'PA_REPLICATION_REQUIREMENT_ID',
        'requirementId',
        'requirementId is required',
      );
    }
    if (requirement.minimumReplicaCount < 1) {
      addError(
        'PA_REPLICATION_MINIMUM_COUNT',
        'minimumReplicaCount',
        'minimumReplicaCount must be >= 1',
      );
    }
    if (requirement.distinctFailureDomains < 1) {
      addError(
        'PA_REPLICATION_FAILURE_DOMAINS',
        'distinctFailureDomains',
        'distinctFailureDomains must be >= 1',
      );
    }
    if (requirement.distinctFailureDomains > requirement.minimumReplicaCount) {
      addError(
        'PA_REPLICATION_DOMAIN_COUNT',
        'distinctFailureDomains',
        'distinctFailureDomains must be <= minimumReplicaCount',
      );
    }

    validateSensitiveMetadata(requirement.metadata, 'metadata', addError);

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactReplicaRecord].
class PersistentArtifactReplicaValidator {
  const PersistentArtifactReplicaValidator({
    PersistentArtifactLocationValidator? locationValidator,
  }) : _locationValidator =
            locationValidator ?? const PersistentArtifactLocationValidator();

  final PersistentArtifactLocationValidator _locationValidator;

  PersistentArtifactValidationResult validate(
    PersistentArtifactReplicaRecord replica,
  ) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void merge(PersistentArtifactValidationResult result) {
      issues.addAll(result.issues);
      warnings.addAll(result.warnings);
      errors.addAll(result.errors);
    }

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId ?? replica.artifactId,
        versionId: versionId ?? replica.versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (replica.replicaId.isEmpty) {
      addError('PA_REPLICA_ID', 'replicaId', 'replicaId is required');
    }
    if (replica.artifactId.isEmpty) {
      addError(
          'PA_REPLICA_ARTIFACT_ID', 'artifactId', 'artifactId is required');
    }
    if (replica.versionId.isEmpty) {
      addError('PA_REPLICA_VERSION_ID', 'versionId', 'versionId is required');
    }
    if (replica.contentFingerprint.isEmpty) {
      addError(
        'PA_REPLICA_CONTENT_FINGERPRINT',
        'contentFingerprint',
        'contentFingerprint is required',
      );
    }
    if (replica.contentFingerprint !=
        replica.locationReference.contentFingerprint) {
      addError(
        'PA_REPLICA_FINGERPRINT_MISMATCH',
        'contentFingerprint',
        'replica contentFingerprint does not match locationReference contentFingerprint',
        locationId: replica.locationReference.locationId,
      );
    }

    merge(
      _locationValidator.validate(
        replica.locationReference,
        pathPrefix: 'locationReference',
      ),
    );
    validateSensitiveMetadata(replica.metadata, 'metadata', addError);

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactAvailabilityRecord].
class PersistentArtifactAvailabilityValidator {
  const PersistentArtifactAvailabilityValidator();

  PersistentArtifactValidationResult validate(
    PersistentArtifactAvailabilityRecord record,
  ) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId ?? record.artifactId,
        versionId: versionId ?? record.versionId,
        locationId: locationId ?? record.locationId,
        policyId: policyId,
      );
    }

    if (record.availabilityRecordId.isEmpty) {
      addError(
        'PA_AVAILABILITY_RECORD_ID',
        'availabilityRecordId',
        'availabilityRecordId is required',
      );
    }
    if (record.artifactId.isEmpty) {
      addError(
        'PA_AVAILABILITY_ARTIFACT_ID',
        'artifactId',
        'artifactId is required',
      );
    }
    if (record.versionId.isEmpty) {
      addError(
        'PA_AVAILABILITY_VERSION_ID',
        'versionId',
        'versionId is required',
      );
    }
    if ((record.status == PersistentArtifactAvailabilityStatus.partial ||
            record.status ==
                PersistentArtifactAvailabilityStatus.unavailable) &&
        (record.locationId == null || record.locationId!.isEmpty)) {
      addError(
        'PA_AVAILABILITY_LOCATION_ID',
        'locationId',
        'locationId is required when status is ${record.status.wireName}',
      );
    }

    validateSensitiveMetadata(record.metadata, 'metadata', addError);

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactRetentionRecord].
class PersistentArtifactRetentionRecordValidator {
  const PersistentArtifactRetentionRecordValidator();

  PersistentArtifactValidationResult validate(
    PersistentArtifactRetentionRecord record,
  ) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId ?? record.artifactId,
        versionId: versionId ?? record.versionId,
        locationId: locationId,
        policyId: policyId ?? record.policyId,
      );
    }

    if (record.retentionRecordId.isEmpty) {
      addError(
        'PA_RETENTION_RECORD_ID',
        'retentionRecordId',
        'retentionRecordId is required',
      );
    }
    if (record.artifactId.isEmpty) {
      addError(
        'PA_RETENTION_RECORD_ARTIFACT_ID',
        'artifactId',
        'artifactId is required',
      );
    }
    if (record.versionId.isEmpty) {
      addError(
        'PA_RETENTION_RECORD_VERSION_ID',
        'versionId',
        'versionId is required',
      );
    }
    if (record.policyId.isEmpty) {
      addError(
          'PA_RETENTION_RECORD_POLICY_ID', 'policyId', 'policyId is required');
    }

    if (record.legalHold &&
        record.status != PersistentArtifactRetentionRecordStatus.legalHold &&
        record.status != PersistentArtifactRetentionRecordStatus.immutable) {
      addError(
        'PA_RETENTION_LEGAL_HOLD_STATUS',
        'status',
        'status must be legalHold or immutable when legalHold is true',
      );
    }
    if (record.status == PersistentArtifactRetentionRecordStatus.legalHold &&
        !record.legalHold) {
      addError(
        'PA_RETENTION_LEGAL_HOLD_FLAG',
        'legalHold',
        'legalHold must be true when status is legalHold',
      );
    }
    if (!isIsoDateRangeCoherent(record.evaluatedAt, record.retainUntil)) {
      addError(
        'PA_RETENTION_RETAIN_UNTIL',
        'retainUntil',
        'retainUntil must be >= evaluatedAt',
      );
    }
    if (!isIsoDateRangeCoherent(record.evaluatedAt, record.immutableUntil)) {
      addError(
        'PA_RETENTION_IMMUTABLE_UNTIL',
        'immutableUntil',
        'immutableUntil must be >= evaluatedAt',
      );
    }

    validateSensitiveMetadata(record.metadata, 'metadata', addError);

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactDeletionRequest].
class PersistentArtifactDeletionRequestValidator {
  const PersistentArtifactDeletionRequestValidator();

  PersistentArtifactValidationResult validate(
    PersistentArtifactDeletionRequest request, {
    bool legalHoldActive = false,
  }) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId ?? request.artifactId,
        versionId: versionId ?? request.versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (request.deletionRequestId.isEmpty) {
      addError(
        'PA_DELETION_REQUEST_ID',
        'deletionRequestId',
        'deletionRequestId is required',
      );
    }
    if (request.artifactId.isEmpty) {
      addError(
        'PA_DELETION_REQUEST_ARTIFACT_ID',
        'artifactId',
        'artifactId is required',
      );
    }
    if (request.reasonCode.isEmpty) {
      addError(
        'PA_DELETION_REQUEST_REASON_CODE',
        'reasonCode',
        'reasonCode is required',
      );
    }
    if (request.requestedAt.isEmpty) {
      addError(
        'PA_DELETION_REQUEST_REQUESTED_AT',
        'requestedAt',
        'requestedAt is required',
      );
    }
    if (legalHoldActive && !request.force) {
      addError(
        'PA_DELETION_REQUEST_LEGAL_HOLD',
        'force',
        'deletion is blocked by legal hold unless force is true',
      );
    }

    validateSensitiveMetadata(request.metadata, 'metadata', addError);

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactDeletionResult].
class PersistentArtifactDeletionResultValidator {
  const PersistentArtifactDeletionResultValidator();

  PersistentArtifactValidationResult validate(
    PersistentArtifactDeletionResult result, {
    Set<String> knownTombstoneIds = const {},
    bool legalHoldActive = false,
  }) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId ?? result.artifactId,
        versionId: versionId ?? result.versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (result.deletionResultId.isEmpty) {
      addError(
        'PA_DELETION_RESULT_ID',
        'deletionResultId',
        'deletionResultId is required',
      );
    }
    if (result.deletionRequestId.isEmpty) {
      addError(
        'PA_DELETION_RESULT_REQUEST_ID',
        'deletionRequestId',
        'deletionRequestId is required',
      );
    }
    if (result.artifactId.isEmpty) {
      addError(
        'PA_DELETION_RESULT_ARTIFACT_ID',
        'artifactId',
        'artifactId is required',
      );
    }
    if (result.status == PersistentArtifactDeletionStatus.completed &&
        (result.tombstoneId == null || result.tombstoneId!.isEmpty)) {
      addError(
        'PA_DELETION_RESULT_TOMBSTONE',
        'tombstoneId',
        'tombstoneId is required when deletion status is completed',
      );
    }
    if (result.tombstoneId != null &&
        result.tombstoneId!.isNotEmpty &&
        knownTombstoneIds.isNotEmpty &&
        !knownTombstoneIds.contains(result.tombstoneId)) {
      addError(
        'PA_DELETION_RESULT_TOMBSTONE_REFERENCE',
        'tombstoneId',
        'referenced tombstoneId not found: ${result.tombstoneId}',
      );
    }
    if (legalHoldActive &&
        result.status == PersistentArtifactDeletionStatus.completed) {
      addError(
        'PA_DELETION_RESULT_LEGAL_HOLD',
        'status',
        'deletion cannot be completed while legal hold is active',
      );
    }
    if (result.status == PersistentArtifactDeletionStatus.blocked &&
        result.issues.isEmpty) {
      addError(
        'PA_DELETION_RESULT_BLOCKED_ISSUES',
        'issues',
        'blocked deletion result must include issues',
      );
    }

    validateSensitiveMetadata(result.metadata, 'metadata', addError);

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactTombstone].
class PersistentArtifactTombstoneValidator {
  const PersistentArtifactTombstoneValidator();

  PersistentArtifactValidationResult validate(
    PersistentArtifactTombstone tombstone, {
    Set<String> knownDeletionRequestIds = const {},
  }) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId ?? tombstone.artifactId,
        versionId: versionId ?? tombstone.versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (tombstone.tombstoneId.isEmpty) {
      addError('PA_TOMBSTONE_ID', 'tombstoneId', 'tombstoneId is required');
    }
    if (tombstone.artifactId.isEmpty) {
      addError(
          'PA_TOMBSTONE_ARTIFACT_ID', 'artifactId', 'artifactId is required');
    }
    if (tombstone.previousContentFingerprint.isEmpty) {
      addError(
        'PA_TOMBSTONE_CONTENT_FINGERPRINT',
        'previousContentFingerprint',
        'previousContentFingerprint is required',
      );
    }
    if (tombstone.deletionRequestId.isEmpty) {
      addError(
        'PA_TOMBSTONE_DELETION_REQUEST',
        'deletionRequestId',
        'deletionRequestId is required',
      );
    }
    if (tombstone.reasonCode.isEmpty) {
      addError(
          'PA_TOMBSTONE_REASON_CODE', 'reasonCode', 'reasonCode is required');
    }
    if (tombstone.createdAt.isEmpty) {
      addError('PA_TOMBSTONE_CREATED_AT', 'createdAt', 'createdAt is required');
    }
    if (!isIsoDateRangeCoherent(tombstone.createdAt, tombstone.expiresAt)) {
      addError(
        'PA_TOMBSTONE_EXPIRES_AT',
        'expiresAt',
        'expiresAt must be >= createdAt',
      );
    }
    if (knownDeletionRequestIds.isNotEmpty &&
        !knownDeletionRequestIds.contains(tombstone.deletionRequestId)) {
      addError(
        'PA_TOMBSTONE_DELETION_REFERENCE',
        'deletionRequestId',
        'referenced deletionRequestId not found: ${tombstone.deletionRequestId}',
      );
    }

    validateSensitiveMetadata(tombstone.metadata, 'metadata', addError);

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactOperationRequest].
class PersistentArtifactOperationRequestValidator {
  const PersistentArtifactOperationRequestValidator({
    PersistentArtifactSubjectValidator? subjectValidator,
  }) : _subjectValidator =
            subjectValidator ?? const PersistentArtifactSubjectValidator();

  final PersistentArtifactSubjectValidator _subjectValidator;

  PersistentArtifactValidationResult validate(
    PersistentArtifactOperationRequest request,
  ) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void merge(PersistentArtifactValidationResult result) {
      issues.addAll(result.issues);
      warnings.addAll(result.warnings);
      errors.addAll(result.errors);
    }

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId,
        versionId: versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (request.requestId.isEmpty) {
      addError('PA_OPERATION_REQUEST_ID', 'requestId', 'requestId is required');
    }
    if (request.projectId.isEmpty) {
      addError(
          'PA_OPERATION_REQUEST_PROJECT', 'projectId', 'projectId is required');
    }
    if (request.requestedAt.isEmpty) {
      addError(
        'PA_OPERATION_REQUEST_REQUESTED_AT',
        'requestedAt',
        'requestedAt is required',
      );
    }
    if (request.artifactSubjects.isEmpty &&
        request.artifactIds.isEmpty &&
        request.versionIds.isEmpty) {
      addError(
        'PA_OPERATION_REQUEST_TARGETS',
        'artifactSubjects',
        'operation request must target at least one artifact subject or id',
      );
    }

    for (final subject in request.artifactSubjects) {
      merge(_subjectValidator.validate(subject));
      if (subject.projectId != request.projectId) {
        addError(
          'PA_OPERATION_REQUEST_SUBJECT_PROJECT',
          'artifactSubjects.${subject.subjectId}.projectId',
          'subject projectId does not match request projectId',
        );
      }
    }

    validateReleaseAuthorizationMetadata(
        request.metadata, 'metadata', addError);
    validateSensitiveMetadata(request.metadata, 'metadata', addError);

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Validates structural consistency of [PersistentArtifactOperationResult].
class PersistentArtifactOperationResultValidator {
  const PersistentArtifactOperationResultValidator();

  PersistentArtifactValidationResult validate(
    PersistentArtifactOperationResult result, {
    String? expectedRequestId,
    String? expectedProjectId,
  }) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId,
        versionId: versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (result.resultId.isEmpty) {
      addError('PA_OPERATION_RESULT_ID', 'resultId', 'resultId is required');
    }
    if (result.requestId.isEmpty) {
      addError('PA_OPERATION_RESULT_REQUEST_ID', 'requestId',
          'requestId is required');
    }
    if (result.projectId.isEmpty) {
      addError(
          'PA_OPERATION_RESULT_PROJECT', 'projectId', 'projectId is required');
    }
    if (expectedRequestId != null && result.requestId != expectedRequestId) {
      addError(
        'PA_OPERATION_RESULT_REQUEST_MISMATCH',
        'requestId',
        'requestId does not match operation request',
      );
    }
    if (expectedProjectId != null && result.projectId != expectedProjectId) {
      addError(
        'PA_OPERATION_RESULT_PROJECT_MISMATCH',
        'projectId',
        'projectId does not match operation request',
      );
    }
    if (result.status == PersistentArtifactOperationStatus.succeeded &&
        result.artifactResults.isEmpty) {
      addError(
        'PA_OPERATION_RESULT_ARTIFACT_RESULTS',
        'artifactResults',
        'artifactResults must not be empty when status is succeeded',
      );
    }

    final artifactIds = <String>{};
    for (final item in result.artifactResults) {
      if (!artifactIds.add(item.artifactId)) {
        addError(
          'PA_OPERATION_RESULT_DUPLICATE_ARTIFACT',
          'artifactResults',
          'duplicate artifactId: ${item.artifactId}',
          artifactId: item.artifactId,
        );
      }
      if (item.artifactId.isEmpty) {
        addError(
          'PA_OPERATION_RESULT_ARTIFACT_ID',
          'artifactResults',
          'artifactId is required',
        );
      }
    }

    validateReleaseAuthorizationMetadata(result.metadata, 'metadata', addError);
    validateSensitiveMetadata(result.metadata, 'metadata', addError);

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}

/// Aggregate validation for [PersistentArtifactInfrastructureSnapshot].
class PersistentArtifactInfrastructureSnapshotValidator {
  const PersistentArtifactInfrastructureSnapshotValidator({
    PersistentArtifactSubjectValidator? subjectValidator,
    PersistentArtifactContentDescriptorValidator? contentDescriptorValidator,
    PersistentArtifactLocationValidator? locationValidator,
    PersistentArtifactVersionValidator? versionValidator,
    PersistentArtifactManifestValidator? manifestValidator,
    PersistentArtifactIntegrityValidator? integrityValidator,
    PersistentArtifactEncryptionDescriptorValidator? encryptionValidator,
    PersistentArtifactPublicationValidator? publicationValidator,
    PersistentArtifactLifecycleValidator? lifecycleValidator,
    PersistentArtifactRetentionPolicyValidator? retentionPolicyValidator,
    PersistentArtifactStoragePolicyValidator? storagePolicyValidator,
    PersistentArtifactReplicationRequirementValidator?
        replicationRequirementValidator,
    PersistentArtifactReplicaValidator? replicaValidator,
    PersistentArtifactAvailabilityValidator? availabilityValidator,
    PersistentArtifactRetentionRecordValidator? retentionRecordValidator,
    PersistentArtifactDeletionRequestValidator? deletionRequestValidator,
    PersistentArtifactDeletionResultValidator? deletionResultValidator,
    PersistentArtifactTombstoneValidator? tombstoneValidator,
    PersistentArtifactOperationRequestValidator? operationRequestValidator,
    PersistentArtifactOperationResultValidator? operationResultValidator,
  })  : _subjectValidator =
            subjectValidator ?? const PersistentArtifactSubjectValidator(),
        _contentDescriptorValidator = contentDescriptorValidator ??
            const PersistentArtifactContentDescriptorValidator(),
        _locationValidator =
            locationValidator ?? const PersistentArtifactLocationValidator(),
        _versionValidator =
            versionValidator ?? const PersistentArtifactVersionValidator(),
        _manifestValidator =
            manifestValidator ?? const PersistentArtifactManifestValidator(),
        _integrityValidator =
            integrityValidator ?? const PersistentArtifactIntegrityValidator(),
        _encryptionValidator = encryptionValidator ??
            const PersistentArtifactEncryptionDescriptorValidator(),
        _publicationValidator = publicationValidator ??
            const PersistentArtifactPublicationValidator(),
        _lifecycleValidator =
            lifecycleValidator ?? const PersistentArtifactLifecycleValidator(),
        _retentionPolicyValidator = retentionPolicyValidator ??
            const PersistentArtifactRetentionPolicyValidator(),
        _storagePolicyValidator = storagePolicyValidator ??
            const PersistentArtifactStoragePolicyValidator(),
        _replicationRequirementValidator = replicationRequirementValidator ??
            const PersistentArtifactReplicationRequirementValidator(),
        _replicaValidator =
            replicaValidator ?? const PersistentArtifactReplicaValidator(),
        _availabilityValidator = availabilityValidator ??
            const PersistentArtifactAvailabilityValidator(),
        _retentionRecordValidator = retentionRecordValidator ??
            const PersistentArtifactRetentionRecordValidator(),
        _deletionRequestValidator = deletionRequestValidator ??
            const PersistentArtifactDeletionRequestValidator(),
        _deletionResultValidator = deletionResultValidator ??
            const PersistentArtifactDeletionResultValidator(),
        _tombstoneValidator =
            tombstoneValidator ?? const PersistentArtifactTombstoneValidator(),
        _operationRequestValidator = operationRequestValidator ??
            const PersistentArtifactOperationRequestValidator(),
        _operationResultValidator = operationResultValidator ??
            const PersistentArtifactOperationResultValidator();

  final PersistentArtifactSubjectValidator _subjectValidator;
  final PersistentArtifactContentDescriptorValidator
      _contentDescriptorValidator;
  final PersistentArtifactLocationValidator _locationValidator;
  final PersistentArtifactVersionValidator _versionValidator;
  final PersistentArtifactManifestValidator _manifestValidator;
  final PersistentArtifactIntegrityValidator _integrityValidator;
  final PersistentArtifactEncryptionDescriptorValidator _encryptionValidator;
  final PersistentArtifactPublicationValidator _publicationValidator;
  final PersistentArtifactLifecycleValidator _lifecycleValidator;
  final PersistentArtifactRetentionPolicyValidator _retentionPolicyValidator;
  final PersistentArtifactStoragePolicyValidator _storagePolicyValidator;
  final PersistentArtifactReplicationRequirementValidator
      _replicationRequirementValidator;
  final PersistentArtifactReplicaValidator _replicaValidator;
  final PersistentArtifactAvailabilityValidator _availabilityValidator;
  final PersistentArtifactRetentionRecordValidator _retentionRecordValidator;
  final PersistentArtifactDeletionRequestValidator _deletionRequestValidator;
  final PersistentArtifactDeletionResultValidator _deletionResultValidator;
  final PersistentArtifactTombstoneValidator _tombstoneValidator;
  final PersistentArtifactOperationRequestValidator _operationRequestValidator;
  final PersistentArtifactOperationResultValidator _operationResultValidator;

  PersistentArtifactValidationResult validate(
    PersistentArtifactInfrastructureSnapshot snapshot,
  ) {
    final issues = <PersistentArtifactIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void merge(PersistentArtifactValidationResult result) {
      issues.addAll(result.issues);
      warnings.addAll(result.warnings);
      errors.addAll(result.errors);
    }

    void addError(
      String code,
      String path,
      String message, {
      String? artifactId,
      String? versionId,
      String? locationId,
      String? policyId,
    }) {
      addPersistentArtifactValidationError(
        issues,
        errors,
        code: code,
        path: path,
        message: message,
        artifactId: artifactId,
        versionId: versionId,
        locationId: locationId,
        policyId: policyId,
      );
    }

    if (snapshot.projectId.isEmpty) {
      addError('PA_SNAPSHOT_PROJECT_ID', 'projectId', 'projectId is required');
    }
    if (snapshot.createdAt.isEmpty) {
      addError('PA_SNAPSHOT_CREATED_AT', 'createdAt', 'createdAt is required');
    }
    if (!isIsoDateRangeCoherent(snapshot.createdAt, snapshot.evaluatedAt)) {
      addError(
        'PA_SNAPSHOT_EVALUATED_AT',
        'evaluatedAt',
        'evaluatedAt must be >= createdAt',
      );
    }
    if (!isIsoDateRangeCoherent(snapshot.evaluatedAt, snapshot.publishedAt)) {
      addError(
        'PA_SNAPSHOT_PUBLISHED_AT',
        'publishedAt',
        'publishedAt must be >= evaluatedAt',
      );
    }

    validateSensitiveMetadata(snapshot.metadata, 'metadata', addError);
    validateReleaseAuthorizationMetadata(
        snapshot.metadata, 'metadata', addError);

    final subjectIds = <String>{};
    for (final subject in snapshot.subjects) {
      if (!subjectIds.add(subject.subjectId)) {
        addError(
          'PA_SNAPSHOT_DUPLICATE_SUBJECT',
          'subjects',
          'duplicate subjectId: ${subject.subjectId}',
        );
      }
      if (subject.projectId != snapshot.projectId) {
        addError(
          'PA_SNAPSHOT_SUBJECT_PROJECT',
          'subjects.${subject.subjectId}.projectId',
          'subject projectId does not match snapshot projectId',
        );
      }
      merge(_subjectValidator.validate(subject));
    }

    final contentIds = <String>{};
    for (final content in snapshot.contentDescriptors) {
      if (!contentIds.add(content.contentId)) {
        addError(
          'PA_SNAPSHOT_DUPLICATE_CONTENT',
          'contentDescriptors',
          'duplicate contentId: ${content.contentId}',
        );
      }
      merge(
        _contentDescriptorValidator.validate(
          content,
          pathPrefix: 'contentDescriptors.${content.contentId}',
        ),
      );
    }

    final versionIds = <String>{};
    for (final version in snapshot.versions) {
      if (!versionIds.add(version.versionId)) {
        addError(
          'PA_SNAPSHOT_DUPLICATE_VERSION',
          'versions',
          'duplicate versionId: ${version.versionId}',
          versionId: version.versionId,
        );
      }
      merge(_versionValidator.validate(version));
    }

    final manifestIds = <String>{};
    for (final manifest in snapshot.manifests) {
      if (!manifestIds.add(manifest.manifestId)) {
        addError(
          'PA_SNAPSHOT_DUPLICATE_MANIFEST',
          'manifests',
          'duplicate manifestId: ${manifest.manifestId}',
        );
      }
      if (!versionIds.contains(manifest.versionId) &&
          snapshot.versions.isNotEmpty) {
        addError(
          'PA_SNAPSHOT_MANIFEST_VERSION',
          'manifests.${manifest.manifestId}.versionId',
          'manifest versionId not found in versions: ${manifest.versionId}',
          artifactId: manifest.artifactId,
          versionId: manifest.versionId,
        );
      }
      merge(_manifestValidator.validate(manifest));
    }

    final locationIds = <String>{};
    for (final location in snapshot.locations) {
      if (!locationIds.add(location.locationId)) {
        addError(
          'PA_SNAPSHOT_DUPLICATE_LOCATION',
          'locations',
          'duplicate locationId: ${location.locationId}',
          locationId: location.locationId,
        );
      }
      merge(
        _locationValidator.validate(
          location,
          pathPrefix: 'locations.${location.locationId}',
        ),
      );
    }

    final integrityIds = <String>{};
    for (final record in snapshot.integrityRecords) {
      if (!integrityIds.add(record.integrityRecordId)) {
        addError(
          'PA_SNAPSHOT_DUPLICATE_INTEGRITY',
          'integrityRecords',
          'duplicate integrityRecordId: ${record.integrityRecordId}',
        );
      }
      merge(_integrityValidator.validate(record));
    }

    for (var i = 0; i < snapshot.encryptionDescriptors.length; i++) {
      merge(
        _encryptionValidator.validate(
          snapshot.encryptionDescriptors[i],
          pathPrefix: 'encryptionDescriptors[$i]',
        ),
      );
    }

    final publicationIds = <String>{};
    for (final publication in snapshot.publications) {
      if (!publicationIds.add(publication.publicationId)) {
        addError(
          'PA_SNAPSHOT_DUPLICATE_PUBLICATION',
          'publications',
          'duplicate publicationId: ${publication.publicationId}',
        );
      }
      merge(_publicationValidator.validate(publication));
    }

    final lifecycleIds = <String>{};
    for (final record in snapshot.lifecycleRecords) {
      if (!lifecycleIds.add(record.lifecycleRecordId)) {
        addError(
          'PA_SNAPSHOT_DUPLICATE_LIFECYCLE',
          'lifecycleRecords',
          'duplicate lifecycleRecordId: ${record.lifecycleRecordId}',
        );
      }
      merge(_lifecycleValidator.validate(record));
    }

    final retentionPolicyIds = <String>{};
    for (final policy in snapshot.retentionPolicies) {
      final key = '${policy.policyId}|${policy.version}';
      if (!retentionPolicyIds.add(key)) {
        addError(
          'PA_SNAPSHOT_DUPLICATE_RETENTION_POLICY',
          'retentionPolicies',
          'duplicate retention policy: ${policy.policyId}',
          policyId: policy.policyId,
        );
      }
      merge(_retentionPolicyValidator.validate(policy));
    }

    final storagePolicyIds = <String>{};
    for (final policy in snapshot.storagePolicies) {
      final key = '${policy.policyId}|${policy.version}';
      if (!storagePolicyIds.add(key)) {
        addError(
          'PA_SNAPSHOT_DUPLICATE_STORAGE_POLICY',
          'storagePolicies',
          'duplicate storage policy: ${policy.policyId}',
          policyId: policy.policyId,
        );
      }
      merge(_storagePolicyValidator.validate(policy));
    }

    final requirementIds = <String>{};
    for (final requirement in snapshot.replicationRequirements) {
      if (!requirementIds.add(requirement.requirementId)) {
        addError(
          'PA_SNAPSHOT_DUPLICATE_REPLICATION_REQUIREMENT',
          'replicationRequirements',
          'duplicate requirementId: ${requirement.requirementId}',
        );
      }
      merge(_replicationRequirementValidator.validate(requirement));
    }

    final replicaIds = <String>{};
    for (final replica in snapshot.replicas) {
      if (!replicaIds.add(replica.replicaId)) {
        addError(
          'PA_SNAPSHOT_DUPLICATE_REPLICA',
          'replicas',
          'duplicate replicaId: ${replica.replicaId}',
        );
      }
      merge(_replicaValidator.validate(replica));
    }

    final availabilityIds = <String>{};
    for (final record in snapshot.availabilityRecords) {
      if (!availabilityIds.add(record.availabilityRecordId)) {
        addError(
          'PA_SNAPSHOT_DUPLICATE_AVAILABILITY',
          'availabilityRecords',
          'duplicate availabilityRecordId: ${record.availabilityRecordId}',
        );
      }
      if (record.locationId != null &&
          record.locationId!.isNotEmpty &&
          snapshot.locations.isNotEmpty &&
          !locationIds.contains(record.locationId)) {
        addError(
          'PA_SNAPSHOT_AVAILABILITY_LOCATION',
          'availabilityRecords.${record.availabilityRecordId}.locationId',
          'referenced locationId not found: ${record.locationId}',
          locationId: record.locationId,
        );
      }
      merge(_availabilityValidator.validate(record));
    }

    final retentionRecordIds = <String>{};
    final legalHoldByArtifactVersion = <String, bool>{};
    for (final record in snapshot.retentionRecords) {
      if (!retentionRecordIds.add(record.retentionRecordId)) {
        addError(
          'PA_SNAPSHOT_DUPLICATE_RETENTION_RECORD',
          'retentionRecords',
          'duplicate retentionRecordId: ${record.retentionRecordId}',
        );
      }
      final key = '${record.artifactId}|${record.versionId}';
      if (record.legalHold) {
        legalHoldByArtifactVersion[key] = true;
      }
      merge(_retentionRecordValidator.validate(record));
    }

    final deletionRequestIds = <String>{};
    for (final request in snapshot.deletionRequests) {
      if (!deletionRequestIds.add(request.deletionRequestId)) {
        addError(
          'PA_SNAPSHOT_DUPLICATE_DELETION_REQUEST',
          'deletionRequests',
          'duplicate deletionRequestId: ${request.deletionRequestId}',
        );
      }
      final key = '${request.artifactId}|${request.versionId ?? ''}';
      merge(
        _deletionRequestValidator.validate(
          request,
          legalHoldActive: legalHoldByArtifactVersion[key] ?? false,
        ),
      );
    }

    final tombstoneIds = snapshot.tombstones.map((e) => e.tombstoneId).toSet();
    for (final result in snapshot.deletionResults) {
      final key = '${result.artifactId}|${result.versionId ?? ''}';
      merge(
        _deletionResultValidator.validate(
          result,
          knownTombstoneIds: tombstoneIds,
          legalHoldActive: legalHoldByArtifactVersion[key] ?? false,
        ),
      );
      if (!deletionRequestIds.contains(result.deletionRequestId)) {
        addError(
          'PA_SNAPSHOT_DELETION_RESULT_REQUEST',
          'deletionResults.${result.deletionResultId}.deletionRequestId',
          'referenced deletionRequestId not found: ${result.deletionRequestId}',
          artifactId: result.artifactId,
        );
      }
    }

    for (final tombstone in snapshot.tombstones) {
      merge(
        _tombstoneValidator.validate(
          tombstone,
          knownDeletionRequestIds: deletionRequestIds,
        ),
      );
    }

    for (final source in snapshot.sourceReferences) {
      if (source.projectId != snapshot.projectId) {
        addError(
          'PA_SNAPSHOT_SOURCE_PROJECT',
          'sourceReferences.${source.sourceId}.projectId',
          'source reference projectId does not match snapshot projectId',
        );
      }
    }

    final operationRequestIds = <String, PersistentArtifactOperationRequest>{};
    for (final request in snapshot.operationRequests) {
      if (!operationRequestIds.containsKey(request.requestId)) {
        operationRequestIds[request.requestId] = request;
      } else {
        addError(
          'PA_SNAPSHOT_DUPLICATE_OPERATION_REQUEST',
          'operationRequests',
          'duplicate requestId: ${request.requestId}',
        );
      }
      if (request.projectId != snapshot.projectId) {
        addError(
          'PA_SNAPSHOT_OPERATION_REQUEST_PROJECT',
          'operationRequests.${request.requestId}.projectId',
          'operation request projectId does not match snapshot projectId',
        );
      }
      merge(_operationRequestValidator.validate(request));
    }

    for (final result in snapshot.operationResults) {
      final request = operationRequestIds[result.requestId];
      merge(
        _operationResultValidator.validate(
          result,
          expectedRequestId: request?.requestId,
          expectedProjectId: request?.projectId ?? snapshot.projectId,
        ),
      );
      if (request == null) {
        addError(
          'PA_SNAPSHOT_OPERATION_RESULT_REQUEST',
          'operationResults.${result.resultId}.requestId',
          'referenced requestId not found: ${result.requestId}',
        );
      } else if (result.operationType != request.operationType) {
        addError(
          'PA_SNAPSHOT_OPERATION_RESULT_TYPE',
          'operationResults.${result.resultId}.operationType',
          'operationType does not match request operationType',
        );
      }
    }

    if (snapshot.identity != null &&
        snapshot.identity!.persistentArtifactInfrastructureId.isEmpty) {
      addError(
        'PA_SNAPSHOT_IDENTITY_ID',
        'identity.persistentArtifactInfrastructureId',
        'persistentArtifactInfrastructureId is required',
      );
    }

    return buildPersistentArtifactValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
