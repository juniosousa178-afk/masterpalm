import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_snapshot.dart';
import '../models/release_supply_chain/release_supply_chain_validation_result.dart';
import 'artifact_registry_validator.dart';
import 'compliance_validator.dart';
import 'release_distribution_validator.dart';
import 'release_provenance_validator.dart';
import 'sbom_validator.dart';
import 'supply_chain_validator.dart';

/// Aggregate validation for release supply chain snapshots.
class ReleaseSupplyChainSnapshotValidator {
  const ReleaseSupplyChainSnapshotValidator({
    ReleaseProvenanceValidator? provenanceValidator,
    SupplyChainValidator? supplyChainValidator,
    SbomValidator? sbomValidator,
    ArtifactRegistryValidator? artifactRegistryValidator,
    ReleaseDistributionValidator? distributionValidator,
    ComplianceValidator? complianceValidator,
  })  : _provenanceValidator =
            provenanceValidator ?? const ReleaseProvenanceValidator(),
        _supplyChainValidator =
            supplyChainValidator ?? const SupplyChainValidator(),
        _sbomValidator = sbomValidator ?? const SbomValidator(),
        _artifactRegistryValidator =
            artifactRegistryValidator ?? const ArtifactRegistryValidator(),
        _distributionValidator =
            distributionValidator ?? const ReleaseDistributionValidator(),
        _complianceValidator =
            complianceValidator ?? const ComplianceValidator();

  final ReleaseProvenanceValidator _provenanceValidator;
  final SupplyChainValidator _supplyChainValidator;
  final SbomValidator _sbomValidator;
  final ArtifactRegistryValidator _artifactRegistryValidator;
  final ReleaseDistributionValidator _distributionValidator;
  final ComplianceValidator _complianceValidator;

  ReleaseSupplyChainValidationResult validate(
      ReleaseSupplyChainSnapshot snapshot) {
    final issues = <ReleaseSupplyChainValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];
    final limitations = <String>[];

    void merge(ReleaseSupplyChainValidationResult result) {
      issues.addAll(result.issues);
      warnings.addAll(result.warnings);
      errors.addAll(result.errors);
      limitations.addAll(result.limitations);
    }

    final metadata = snapshot.metadata;
    if (metadata.supplyChainSnapshotId.isEmpty) {
      errors.add('supplyChainSnapshotId is required');
      issues.add(
        const ReleaseSupplyChainValidationIssue(
          code: 'RSC_SNAPSHOT_ID',
          path: 'metadata.supplyChainSnapshotId',
          severity: ReleaseSupplyChainValidationSeverity.critical,
          message: 'supplyChainSnapshotId is required',
        ),
      );
    }
    if (snapshot.fingerprint.isEmpty) {
      errors.add('fingerprint is required');
    }
    if (metadata.fingerprint != snapshot.fingerprint) {
      errors.add('metadata fingerprint does not match snapshot fingerprint');
    }

    if (snapshot.provenance != null) {
      merge(_provenanceValidator.validate(snapshot.provenance!));
    }
    if (snapshot.supplyChain != null) {
      merge(_supplyChainValidator.validate(snapshot.supplyChain!));
    }
    if (snapshot.sbom != null) {
      merge(_sbomValidator.validate(snapshot.sbom!));
    }
    for (final artifact in snapshot.artifacts) {
      merge(_artifactRegistryValidator.validate(artifact));
    }
    if (snapshot.distribution != null) {
      merge(_distributionValidator.validate(snapshot.distribution!));
    }
    if (snapshot.compliance != null) {
      merge(_complianceValidator.validate(snapshot.compliance!));
    }

    return ReleaseSupplyChainValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
      limitations: limitations,
    );
  }
}
