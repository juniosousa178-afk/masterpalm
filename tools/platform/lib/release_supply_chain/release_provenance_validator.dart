import '../models/release_supply_chain/release_provenance_record.dart';
import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_validation_result.dart';

/// Validates structural consistency of [ReleaseProvenanceRecord].
class ReleaseProvenanceValidator {
  const ReleaseProvenanceValidator();

  ReleaseSupplyChainValidationResult validate(ReleaseProvenanceRecord record) {
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
    if (metadata.provenanceRecordId.isEmpty) {
      addError('RSC_PROV_ID', 'metadata.provenanceRecordId',
          'provenanceRecordId is required');
    }
    if (metadata.fingerprint.isEmpty) {
      addError('RSC_PROV_FINGERPRINT', 'metadata.fingerprint',
          'fingerprint is required');
    }
    if (record.fingerprintDescriptor.value.isEmpty) {
      addError(
        'RSC_PROV_FP_DESCRIPTOR',
        'fingerprintDescriptor.value',
        'fingerprint descriptor value is required',
      );
    }
    if (record.subject.projectId != metadata.projectId) {
      addError(
        'RSC_PROV_PROJECT_MISMATCH',
        'subject.projectId',
        'subject projectId does not match metadata',
      );
    }
    if (metadata.artifactCount != record.artifacts.length) {
      addError(
        'RSC_PROV_ARTIFACT_COUNT',
        'metadata.artifactCount',
        'artifactCount does not match artifacts list length',
      );
    }
    if (metadata.relationCount != record.relations.length) {
      addError(
        'RSC_PROV_RELATION_COUNT',
        'metadata.relationCount',
        'relationCount does not match relations list length',
      );
    }

    final artifactIds = <String>{};
    for (final artifact in record.artifacts) {
      if (!artifactIds.add(artifact.artifactId)) {
        addError(
          'RSC_PROV_DUPLICATE_ARTIFACT',
          'artifacts',
          'duplicate artifactId: ${artifact.artifactId}',
          relatedId: artifact.artifactId,
        );
      }
      if (artifact.fingerprint.isEmpty) {
        addError(
          'RSC_PROV_ARTIFACT_FINGERPRINT',
          'artifacts.${artifact.artifactId}.fingerprint',
          'artifact fingerprint is required',
          relatedId: artifact.artifactId,
        );
      }
    }

    final relationIds = <String>{};
    for (final relation in record.relations) {
      if (!relationIds.add(relation.relationId)) {
        addError(
          'RSC_PROV_DUPLICATE_RELATION',
          'relations',
          'duplicate relationId: ${relation.relationId}',
          relatedId: relation.relationId,
        );
      }
    }

    if (metadata.status == ReleaseProvenanceStatus.invalid) {
      warnings.add('provenance status is invalid');
    }

    return ReleaseSupplyChainValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
