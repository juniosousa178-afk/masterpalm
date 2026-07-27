import '../models/release_supply_chain/artifact_registry_models.dart';
import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_validation_result.dart';

/// Validates structural consistency of [ArtifactRecord].
class ArtifactRegistryValidator {
  const ArtifactRegistryValidator();

  ReleaseSupplyChainValidationResult validate(ArtifactRecord record) {
    final issues = <ReleaseSupplyChainValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(String code, String path, String message,
        {String? relatedId}) {
      errors.add(message);
      issues.add(
        ReleaseSupplyChainValidationIssue(
          code: code,
          path: path,
          severity: ReleaseSupplyChainValidationSeverity.critical,
          message: message,
          relatedId: relatedId,
        ),
      );
    }

    final metadata = record.metadata;
    if (metadata.recordId.isEmpty) {
      addError('RSC_ART_ID', 'metadata.recordId', 'recordId is required');
    }
    if (metadata.fingerprint.isEmpty) {
      addError('RSC_ART_FINGERPRINT', 'metadata.fingerprint',
          'fingerprint is required');
    }
    if (record.identifier.artifactId.isEmpty) {
      addError('RSC_ART_IDENTIFIER', 'identifier.artifactId',
          'artifactId is required');
    }
    if (record.location.uri.isEmpty) {
      addError('RSC_ART_LOCATION', 'location.uri', 'location uri is required');
    }
    if (record.integrity.digest.value.isEmpty) {
      addError('RSC_ART_DIGEST', 'integrity.digest.value',
          'digest value is required');
    }

    if (metadata.status == ArtifactStatus.corrupted) {
      warnings.add('artifact status is corrupted');
    }
    if (!record.integrity.verified) {
      warnings.add('artifact integrity not verified');
    }

    return ReleaseSupplyChainValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
