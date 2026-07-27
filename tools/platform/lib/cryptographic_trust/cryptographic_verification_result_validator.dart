import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'cryptographic_validation_helpers.dart';

/// Validates structural consistency of [CryptographicVerificationResult].
class CryptographicVerificationResultValidator {
  const CryptographicVerificationResultValidator();

  CryptographicValidationResult validate(
    CryptographicVerificationResult result,
  ) {
    final issues = <CryptographicValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

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

    if (result.verificationId.isEmpty) {
      addError(
        'CT_VERIFY_RESULT_ID',
        'verificationId',
        'verificationId is required',
      );
    }
    if (result.requestId.isEmpty) {
      addError(
        'CT_VERIFY_RESULT_REQUEST_ID',
        'requestId',
        'requestId is required',
      );
    }
    if (result.projectId.isEmpty) {
      addError(
        'CT_VERIFY_RESULT_PROJECT',
        'projectId',
        'projectId is required',
      );
    }

    final subjectResultIds = <String>{};
    for (final subjectResult in result.subjectResults) {
      if (!subjectResultIds.add(subjectResult.subjectId)) {
        addError(
          'CT_VERIFY_RESULT_DUPLICATE_SUBJECT',
          'subjectResults',
          'duplicate subjectId: ${subjectResult.subjectId}',
          relatedId: subjectResult.subjectId,
        );
      }
      _validateGranularIssues(
        issues: subjectResult.issues,
        path: 'subjectResults.${subjectResult.subjectId}.issues',
        addError: addError,
      );
    }

    final signatureResultIds = <String>{};
    for (final signatureResult in result.signatureResults) {
      if (!signatureResultIds.add(signatureResult.signatureId)) {
        addError(
          'CT_VERIFY_RESULT_DUPLICATE_SIGNATURE',
          'signatureResults',
          'duplicate signatureId: ${signatureResult.signatureId}',
          relatedId: signatureResult.signatureId,
        );
      }
      _validateGranularIssues(
        issues: signatureResult.issues,
        path: 'signatureResults.${signatureResult.signatureId}.issues',
        addError: addError,
      );
    }

    final attestationResultIds = <String>{};
    for (final attestationResult in result.attestationResults) {
      if (!attestationResultIds.add(attestationResult.attestationId)) {
        addError(
          'CT_VERIFY_RESULT_DUPLICATE_ATTESTATION',
          'attestationResults',
          'duplicate attestationId: ${attestationResult.attestationId}',
          relatedId: attestationResult.attestationId,
        );
      }
      _validateGranularIssues(
        issues: attestationResult.issues,
        path: 'attestationResults.${attestationResult.attestationId}.issues',
        addError: addError,
      );
    }

    final policyResultIds = <String>{};
    for (final policyResult in result.policyResults) {
      if (!policyResultIds.add(policyResult.policyId)) {
        addError(
          'CT_VERIFY_RESULT_DUPLICATE_POLICY',
          'policyResults',
          'duplicate policyId: ${policyResult.policyId}',
          relatedId: policyResult.policyId,
        );
      }
      _validateGranularIssues(
        issues: policyResult.issues,
        path: 'policyResults.${policyResult.policyId}.issues',
        addError: addError,
      );
    }

    _validateGranularIssues(
      issues: result.issues,
      path: 'issues',
      addError: addError,
    );

    final allCriticalIssues = <CryptographicIssueSeverity>[
      ...result.issues.map((issue) => issue.severity),
      ...result.subjectResults.expand(
        (entry) => entry.issues.map((issue) => issue.severity),
      ),
      ...result.signatureResults.expand(
        (entry) => entry.issues.map((issue) => issue.severity),
      ),
      ...result.attestationResults.expand(
        (entry) => entry.issues.map((issue) => issue.severity),
      ),
      ...result.policyResults.expand(
        (entry) => entry.issues.map((issue) => issue.severity),
      ),
    ];

    if (result.status == CryptographicVerificationStatus.verified &&
        hasCriticalIssues(allCriticalIssues)) {
      addError(
        'CT_VERIFY_RESULT_STATUS',
        'status',
        'verified status cannot coexist with critical issues',
      );
    }

    if (result.status == CryptographicVerificationStatus.invalid &&
        !hasCriticalIssues(allCriticalIssues) &&
        result.issues.isEmpty) {
      addWarning(
        'CT_VERIFY_RESULT_STATUS',
        'status',
        'invalid status without critical issues',
      );
    }

    for (final subjectResult in result.subjectResults) {
      _validateGranularMetadata(subjectResult.metadata, addError);
    }
    for (final signatureResult in result.signatureResults) {
      _validateGranularMetadata(signatureResult.metadata, addError);
    }
    for (final attestationResult in result.attestationResults) {
      _validateGranularMetadata(attestationResult.metadata, addError);
    }
    for (final policyResult in result.policyResults) {
      _validateGranularMetadata(policyResult.metadata, addError);
    }
    validateReleaseAuthorizationMetadata(result.metadata, 'metadata', addError);
    for (final issue in result.issues) {
      validateReleaseAuthorizationMetadata(
          issue.metadata, 'issues.metadata', addError);
    }

    validateSensitiveMetadata(
      result.metadata,
      'metadata',
      addError,
      code: 'CT_VERIFY_RESULT_SENSITIVE_METADATA',
    );

    return buildCryptographicValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }

  void _validateGranularIssues({
    required List<CryptographicVerificationIssue> issues,
    required String path,
    required CryptographicValidationAddError addError,
  }) {
    for (final issue in issues) {
      if (issue.code.isEmpty) {
        addError('CT_VERIFY_RESULT_ISSUE_CODE', path, 'issue code is required');
      }
      validateReleaseAuthorizationMetadata(
        issue.metadata,
        '$path.metadata',
        addError,
      );
    }
  }

  void _validateGranularMetadata(
    Map<String, String> metadata,
    CryptographicValidationAddError addError,
  ) {
    validateReleaseAuthorizationMetadata(metadata, 'metadata', addError);
    validateSensitiveMetadata(
      metadata,
      'metadata',
      addError,
      code: 'CT_VERIFY_RESULT_SENSITIVE_METADATA',
    );
  }
}
