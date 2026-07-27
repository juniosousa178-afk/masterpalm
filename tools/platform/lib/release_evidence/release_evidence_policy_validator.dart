import '../models/release_evidence/release_evidence_collection_rule.dart';
import '../models/release_evidence/release_evidence_enums.dart';
import '../models/release_evidence/release_evidence_policy.dart';
import '../models/release_evidence/release_evidence_rule_value.dart';
import '../models/release_evidence/release_evidence_validation_result.dart';

/// Validates declarative release evidence collection policies.
class ReleaseEvidencePolicyValidator {
  const ReleaseEvidencePolicyValidator();

  ReleaseEvidenceValidationResult validate(
    ReleaseEvidencePolicy policy, {
    bool allowRetired = false,
  }) {
    final issues = <ReleaseEvidenceValidationIssue>[];
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
        ReleaseEvidenceValidationIssue(
          code: code,
          path: path,
          severity: ReleaseEvidenceCollectionRuleSeverity.critical,
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
        ReleaseEvidenceValidationIssue(
          code: code,
          path: path,
          severity: ReleaseEvidenceCollectionRuleSeverity.warning,
          message: message,
          relatedId: relatedId,
        ),
      );
    }

    final metadata = policy.metadata;
    if (metadata.policyId.isEmpty) {
      addError(
          'RE_POLICY_ID_REQUIRED', 'metadata.policyId', 'policyId is required');
    }
    if (metadata.policyVersion < 1) {
      addError(
        'RE_POLICY_VERSION_INVALID',
        'metadata.policyVersion',
        'policyVersion must be >= 1',
      );
    }
    if (metadata.owner.isEmpty) {
      addError('RE_OWNER_REQUIRED', 'metadata.owner', 'owner is required');
    }
    if (metadata.rationale.isEmpty) {
      addError('RE_RATIONALE_REQUIRED', 'metadata.rationale',
          'rationale is required');
    }
    if (metadata.calculationVersion < 1) {
      addError(
        'RE_CALCULATION_VERSION_REQUIRED',
        'metadata.calculationVersion',
        'calculationVersion is required',
      );
    }
    if (metadata.canonicalizationVersion < 1) {
      addError(
        'RE_CANONICALIZATION_VERSION_REQUIRED',
        'metadata.canonicalizationVersion',
        'canonicalizationVersion is required',
      );
    }
    if (!policy.compatibilityPolicy.supportedSchemas
        .contains(metadata.schemaVersion)) {
      addError(
        'RE_SCHEMA_UNSUPPORTED',
        'metadata.schemaVersion',
        'schemaVersion ${metadata.schemaVersion} is not supported',
      );
    }
    if (metadata.status == ReleaseEvidencePolicyStatus.retired &&
        !allowRetired) {
      addWarning(
        'RE_RETIRED_POLICY',
        'metadata.status',
        'retired policy should only be used with historicalEvaluation',
      );
    }
    if (metadata.status == ReleaseEvidencePolicyStatus.active &&
        metadata.policyId.contains('candidate')) {
      addWarning(
        'RE_CANDIDATE_ACTIVE',
        'metadata.status',
        'candidate policy should not be active',
      );
    }

    final ruleSetIds = <String>{};
    for (final ruleSet in policy.ruleSets) {
      if (!ruleSetIds.add(ruleSet.ruleSetId)) {
        addError(
          'RE_DUPLICATE_RULE_SET_ID',
          'ruleSets',
          'duplicate ruleSetId: ${ruleSet.ruleSetId}',
          relatedId: ruleSet.ruleSetId,
        );
      }
      if (ruleSet.aggregationMode ==
              ReleaseEvidenceRuleSetAggregationMode.minimumCount &&
          ruleSet.minimumPassCount == null) {
        addError(
          'RE_RULE_SET_MIN_COUNT',
          'ruleSets.${ruleSet.ruleSetId}',
          'rule set ${ruleSet.ruleSetId} requires minimumPassCount',
          relatedId: ruleSet.ruleSetId,
        );
      }
      if (ruleSet.aggregationMode ==
              ReleaseEvidenceRuleSetAggregationMode.minimumPercentage &&
          ruleSet.minimumPassPercentage == null) {
        addError(
          'RE_RULE_SET_MIN_PERCENTAGE',
          'ruleSets.${ruleSet.ruleSetId}',
          'rule set ${ruleSet.ruleSetId} requires minimumPassPercentage',
          relatedId: ruleSet.ruleSetId,
        );
      }
      if (ruleSet.minimumPassPercentage != null &&
          (ruleSet.minimumPassPercentage! < 0 ||
              ruleSet.minimumPassPercentage! > 100)) {
        addError(
          'RE_RULE_SET_PERCENTAGE_RANGE',
          'ruleSets.${ruleSet.ruleSetId}',
          'minimumPassPercentage must be between 0 and 100',
          relatedId: ruleSet.ruleSetId,
        );
      }
    }

    final ruleIds = <String>{};
    final ruleSetIdSet = ruleSetIds;
    for (final rule in policy.rules) {
      if (!ruleIds.add(rule.ruleId)) {
        addError(
          'RE_DUPLICATE_RULE_ID',
          'rules',
          'duplicate ruleId: ${rule.ruleId}',
          relatedId: rule.ruleId,
        );
      }
      if (!ruleSetIdSet.contains(rule.ruleSetId)) {
        addError(
          'RE_RULE_SET_MISSING',
          'rules.${rule.ruleId}',
          'rule ${rule.ruleId} references missing ruleSet ${rule.ruleSetId}',
          relatedId: rule.ruleId,
        );
      }
      if (rule.requirement ==
              ReleaseEvidenceCollectionRuleRequirement.required &&
          !rule.enabled) {
        addError(
          'RE_REQUIRED_DISABLED',
          'rules.${rule.ruleId}',
          'required rule ${rule.ruleId} cannot be disabled',
          relatedId: rule.ruleId,
        );
      }
      if (rule.requirement ==
              ReleaseEvidenceCollectionRuleRequirement.optional &&
          rule.severity == ReleaseEvidenceCollectionRuleSeverity.critical) {
        addError(
          'RE_OPTIONAL_CRITICAL',
          'rules.${rule.ruleId}',
          'rule ${rule.ruleId} cannot be optional + critical',
          relatedId: rule.ruleId,
        );
      }
      _validateOperatorValue(rule, addError);
    }

    for (final ruleSet in policy.ruleSets) {
      for (final ruleId in ruleSet.ruleIds) {
        if (!ruleIds.contains(ruleId)) {
          addError(
            'RE_RULE_MISSING',
            'ruleSets.${ruleSet.ruleSetId}',
            'ruleSet ${ruleSet.ruleSetId} references missing rule $ruleId',
            relatedId: ruleSet.ruleSetId,
          );
        }
      }
    }

    final attestationReqIds =
        policy.attestationRequirements.map((r) => r.requirementId).toSet();
    if (attestationReqIds.length != policy.attestationRequirements.length) {
      addError(
        'RE_DUPLICATE_ATTESTATION_REQUIREMENT',
        'attestationRequirements',
        'duplicate attestation requirement IDs',
      );
    }

    if (policy.requiredEvidenceTypes.isEmpty) {
      addWarning(
        'RE_NO_REQUIRED_EVIDENCE_TYPES',
        'requiredEvidenceTypes',
        'requiredEvidenceTypes is empty',
      );
    }

    final coverage = policy.coveragePolicy;
    for (final percentage in [
      coverage.minimumEvidenceCoverage,
      coverage.minimumAttestationCoverage,
      coverage.minimumProvenanceCoverage,
      coverage.minimumSourceCoverage,
    ]) {
      if (percentage < 0 || percentage > 100) {
        addError(
          'RE_COVERAGE_PERCENTAGE_RANGE',
          'coveragePolicy',
          'coverage percentage out of range: $percentage',
        );
      }
    }

    if (coverage.minimumNormativeEvidenceCount < 0) {
      addError(
        'RE_COVERAGE_NORMATIVE_COUNT',
        'coveragePolicy.minimumNormativeEvidenceCount',
        'minimumNormativeEvidenceCount must be >= 0',
      );
    }

    return ReleaseEvidenceValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }

  void _validateOperatorValue(
    ReleaseEvidenceCollectionRule rule,
    void Function(String code, String path, String message, {String? relatedId})
        addError,
  ) {
    final needsValue = switch (rule.operator) {
      ReleaseEvidenceCollectionRuleOperator.exists ||
      ReleaseEvidenceCollectionRuleOperator.doesNotExist =>
        false,
      _ => true,
    };
    if (needsValue && rule.expectedValue == null) {
      addError(
        'RE_EXPECTED_VALUE_REQUIRED',
        'rules.${rule.ruleId}.expectedValue',
        'rule ${rule.ruleId} requires expectedValue for operator ${rule.operator.wireName}',
        relatedId: rule.ruleId,
      );
      return;
    }
    if (!needsValue && rule.expectedValue != null) {
      addError(
        'RE_EXPECTED_VALUE_UNEXPECTED',
        'rules.${rule.ruleId}.expectedValue',
        'rule ${rule.ruleId} must not have expectedValue for operator ${rule.operator.wireName}',
        relatedId: rule.ruleId,
      );
      return;
    }
    final value = rule.expectedValue;
    if (value == null) return;
    switch (rule.operator) {
      case ReleaseEvidenceCollectionRuleOperator.isTrue:
      case ReleaseEvidenceCollectionRuleOperator.isFalse:
        if (value is! ReleaseEvidenceBooleanValue) {
          addError(
            'RE_OPERATOR_VALUE_MISMATCH',
            'rules.${rule.ruleId}.expectedValue',
            'operator ${rule.operator.wireName} requires boolean value',
            relatedId: rule.ruleId,
          );
        }
      case ReleaseEvidenceCollectionRuleOperator.equals:
      case ReleaseEvidenceCollectionRuleOperator.notEquals:
      case ReleaseEvidenceCollectionRuleOperator.greaterThan:
      case ReleaseEvidenceCollectionRuleOperator.greaterThanOrEqual:
      case ReleaseEvidenceCollectionRuleOperator.lessThan:
      case ReleaseEvidenceCollectionRuleOperator.lessThanOrEqual:
        if (value is! ReleaseEvidenceIntegerValue &&
            value is! ReleaseEvidenceDecimalValue &&
            value is! ReleaseEvidencePercentageValue &&
            value is! ReleaseEvidenceDurationValue) {
          addError(
            'RE_OPERATOR_VALUE_MISMATCH',
            'rules.${rule.ruleId}.expectedValue',
            'comparison operator requires numeric or duration value',
            relatedId: rule.ruleId,
          );
        }
      case ReleaseEvidenceCollectionRuleOperator.exists:
      case ReleaseEvidenceCollectionRuleOperator.doesNotExist:
        break;
    }
  }
}
