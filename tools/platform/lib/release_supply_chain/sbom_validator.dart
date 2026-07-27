import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_validation_result.dart';
import '../models/release_supply_chain/sbom_models.dart';

/// Validates structural consistency of [SoftwareBillOfMaterials].
class SbomValidator {
  const SbomValidator();

  ReleaseSupplyChainValidationResult validate(SoftwareBillOfMaterials sbom) {
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

    final metadata = sbom.metadata;
    if (metadata.sbomId.isEmpty) {
      addError('RSC_SBOM_ID', 'metadata.sbomId', 'sbomId is required');
    }
    if (metadata.fingerprint.isEmpty) {
      addError('RSC_SBOM_FINGERPRINT', 'metadata.fingerprint',
          'fingerprint is required');
    }
    if (metadata.componentCount != sbom.components.length) {
      addError(
        'RSC_SBOM_COMPONENT_COUNT',
        'metadata.componentCount',
        'componentCount does not match components list length',
      );
    }
    if (metadata.dependencyCount != sbom.dependencies.length) {
      addError(
        'RSC_SBOM_DEPENDENCY_COUNT',
        'metadata.dependencyCount',
        'dependencyCount does not match dependencies list length',
      );
    }

    final componentIds = <String>{};
    for (final component in sbom.components) {
      if (!componentIds.add(component.componentId)) {
        addError(
          'RSC_SBOM_DUPLICATE_COMPONENT',
          'components',
          'duplicate componentId: ${component.componentId}',
          relatedId: component.componentId,
        );
      }
      if (component.hashes.isEmpty) {
        addError(
          'RSC_SBOM_HASH_REQUIRED',
          'components.${component.componentId}.hashes',
          'at least one hash is required',
          relatedId: component.componentId,
        );
      }
    }

    if (metadata.status == SbomStatus.partial) {
      warnings.add('sbom status is partial');
    }

    return ReleaseSupplyChainValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
