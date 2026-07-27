import '../models/cryptographic_trust/cryptographic_trust_chain.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'cryptographic_key_reference_validator.dart';
import 'cryptographic_trust_anchor_validator.dart';
import 'cryptographic_validation_helpers.dart';

/// Validates structural consistency of [CryptographicTrustChain].
class CryptographicTrustChainValidator {
  const CryptographicTrustChainValidator({
    CryptographicKeyReferenceValidator? keyReferenceValidator,
    CryptographicTrustAnchorValidator? trustAnchorValidator,
  })  : _keyReferenceValidator =
            keyReferenceValidator ?? const CryptographicKeyReferenceValidator(),
        _trustAnchorValidator =
            trustAnchorValidator ?? const CryptographicTrustAnchorValidator();

  final CryptographicKeyReferenceValidator _keyReferenceValidator;
  final CryptographicTrustAnchorValidator _trustAnchorValidator;

  CryptographicValidationResult validate(CryptographicTrustChain chain) {
    final issues = <CryptographicValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void merge(CryptographicValidationResult result) {
      issues.addAll(result.issues);
      warnings.addAll(result.warnings);
      errors.addAll(result.errors);
    }

    void addError(
      String code,
      String path,
      String message, {
      String? relatedId,
    }) {
      errors.add(message);
      issues.add(
        CryptographicValidationIssue(
          code: code,
          path: path,
          severity: CryptographicIssueSeverity.critical,
          message: message,
          relatedId: relatedId,
        ),
      );
    }

    void addWarning(
      String code,
      String path,
      String message, {
      String? relatedId,
    }) {
      warnings.add(message);
      issues.add(
        CryptographicValidationIssue(
          code: code,
          path: path,
          severity: CryptographicIssueSeverity.warning,
          message: message,
          relatedId: relatedId,
        ),
      );
    }

    if (chain.trustChainId.isEmpty) {
      addError('CT_CHAIN_ID', 'trustChainId', 'trustChainId is required');
    }
    if (chain.subjectId.isEmpty) {
      addError('CT_CHAIN_SUBJECT_ID', 'subjectId', 'subjectId is required');
    }
    if (chain.leafKey.keyId.isEmpty) {
      addError('CT_CHAIN_LEAF_KEY', 'leafKey', 'leafKey is required');
    }
    if (chain.trustAnchor.trustAnchorId.isEmpty) {
      addError(
        'CT_CHAIN_TRUST_ANCHOR',
        'trustAnchor',
        'trustAnchor is required',
      );
    }

    merge(_keyReferenceValidator.validate(chain.leafKey));
    merge(_trustAnchorValidator.validate(chain.trustAnchor));

    final intermediateKeyIds = <String>{};
    for (final intermediate in chain.intermediateReferences) {
      if (!intermediateKeyIds.add(intermediate.keyId)) {
        addError(
          'CT_CHAIN_DUPLICATE_INTERMEDIATE',
          'intermediateReferences',
          'duplicate intermediate keyId: ${intermediate.keyId}',
          relatedId: intermediate.keyId,
        );
      }
      merge(_keyReferenceValidator.validate(intermediate));
    }

    if (chain.leafKey.keyId == chain.trustAnchor.keyReference.keyId) {
      addWarning(
        'CT_CHAIN_LEAF_ANCHOR_SAME_KEY',
        'leafKey.keyId',
        'leaf keyId matches trust anchor keyId',
        relatedId: chain.trustChainId,
      );
    }

    if (chain.status == CryptographicTrustStatus.revoked ||
        chain.status == CryptographicTrustStatus.invalid) {
      addWarning(
        'CT_CHAIN_STATUS',
        'status',
        'trust chain status is ${chain.status.wireName}',
        relatedId: chain.trustChainId,
      );
    }

    validateSensitiveMetadata(
      chain.metadata,
      'metadata',
      addError,
      code: 'CT_CHAIN_SENSITIVE_METADATA',
    );

    return buildCryptographicValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
