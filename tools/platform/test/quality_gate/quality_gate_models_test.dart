import 'dart:convert';

import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_governance.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_messages.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_policy.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_request.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_rule_value.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:masterpalm_platform/quality_gate/policies/quality_gate_release_policy_v1.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_policy_validator.dart';
import 'package:test/test.dart';

void main() {
  group('QualityGateReleasePolicyV1', () {
    test('has expected identity and candidate status', () {
      final policy = QualityGateReleasePolicyV1.create();
      expect(policy.metadata.policyId, QualityGateReleasePolicyV1.policyId);
      expect(policy.metadata.policyName, 'MasterPalm Release Quality Gate');
      expect(policy.metadata.status, QualityGatePolicyStatus.candidate);
      expect(policy.metadata.owner, 'MasterPalm Engineering Governance');
      expect(policy.metadata.policyVersion, 1);
    });

    test('contains 15 rules across 7 rule sets', () {
      final policy = QualityGateReleasePolicyV1.create();
      expect(policy.ruleSets.length, 7);
      expect(policy.allRules.length, 15);
      expect(
        policy.allRules.map((r) => r.ruleId).toList(),
        [
          'QG001',
          'QG002',
          'QG003',
          'QG004',
          'QG005',
          'QG006',
          'QG007',
          'QG008',
          'QG009',
          'QG010',
          'QG011',
          'QG012',
          'QG013',
          'QG014',
          'QG015',
        ],
      );
    });

    test('validates successfully', () {
      final result = const QualityGatePolicyValidator()
          .validate(QualityGateReleasePolicyV1.create());
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
      expect(result.errors, isEmpty);
    });

    test('toComparableJson is deterministic', () {
      final policy = QualityGateReleasePolicyV1.create();
      final a = jsonEncode(policy.toComparableJson());
      final b = jsonEncode(policy.toComparableJson());
      expect(a, equals(b));
    });

    test('round-trips through JSON', () {
      final original = QualityGateReleasePolicyV1.create();
      final restored = QualityGatePolicy.fromJson(original.toJson());
      expect(restored.metadata.policyId, original.metadata.policyId);
      expect(restored.allRules.length, original.allRules.length);
      expect(
        restored.allRules.first.ruleId,
        original.allRules.first.ruleId,
      );
    });
  });

  group('QualityGatePolicyValidator', () {
    const validator = QualityGatePolicyValidator();

    test('rejects duplicate ruleId', () {
      final base = QualityGateReleasePolicyV1.create();
      final duplicateRule = base.allRules.first;
      final invalid = QualityGatePolicy(
        metadata: base.metadata,
        governance: base.governance,
        decisionPolicy: base.decisionPolicy,
        requiredSourceTypes: base.requiredSourceTypes,
        ruleSets: [
          QualityGateRuleSet(
            ruleSetId: 'dup-set',
            name: 'Dup',
            description: 'Dup',
            aggregationMode: QualityGateRuleSetAggregationMode.all,
            required: true,
            severity: QualityGateRuleSeverity.blocking,
            order: 1,
            rules: [duplicateRule, duplicateRule],
          ),
        ],
      );
      final result = validator.validate(invalid);
      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('duplicate ruleId')));
    });

    test('rejects informational rule with critical severity', () {
      final result = validator.validate(
        QualityGatePolicy(
          metadata: QualityGateReleasePolicyV1.create().metadata,
          governance: QualityGateReleasePolicyV1.create().governance,
          decisionPolicy: QualityGateReleasePolicyV1.create().decisionPolicy,
          ruleSets: [
            QualityGateRuleSet(
              ruleSetId: 'invalid',
              name: 'Invalid',
              description: 'Invalid',
              aggregationMode: QualityGateRuleSetAggregationMode.all,
              required: true,
              severity: QualityGateRuleSeverity.critical,
              order: 1,
              rules: [
                QualityGateRule(
                  ruleId: 'BAD001',
                  name: 'Bad',
                  description: 'Bad',
                  target: QualityGateRuleTarget.guardianDecision,
                  operator: QualityGateRuleOperator.isTrue,
                  requirement: QualityGateRuleRequirement.informational,
                  severity: QualityGateRuleSeverity.critical,
                  missingDataPolicy: QualityGateMissingDataPolicy.notApplicable,
                  incompatibleDataPolicy:
                      QualityGateIncompatibleDataPolicy.skip,
                  evidencePolicy: kReleaseGateEvidencePolicy,
                  explanationTemplateId: 'bad',
                  order: 1,
                ),
              ],
            ),
          ],
        ),
      );
      expect(result.isValid, isFalse);
      expect(
        result.errors,
        contains(
            contains('informational rules cannot be blocking or critical')),
      );
    });

    test('rejects inverted range value', () {
      expect(
        () => const QualityGateRangeValue(lower: 10, upper: 5),
        returnsNormally,
      );
      final result = validator.validate(
        QualityGatePolicy(
          metadata: QualityGateReleasePolicyV1.create().metadata,
          governance: QualityGateReleasePolicyV1.create().governance,
          decisionPolicy: QualityGateReleasePolicyV1.create().decisionPolicy,
          ruleSets: [
            QualityGateRuleSet(
              ruleSetId: 'range-invalid',
              name: 'Range',
              description: 'Range',
              aggregationMode: QualityGateRuleSetAggregationMode.all,
              required: true,
              severity: QualityGateRuleSeverity.blocking,
              order: 1,
              rules: [
                QualityGateRule(
                  ruleId: 'RANGE001',
                  name: 'Range',
                  description: 'Range',
                  target: QualityGateRuleTarget.engineeringScoreGlobal,
                  operator: QualityGateRuleOperator.betweenInclusive,
                  expectedValue:
                      const QualityGateRangeValue(lower: 10, upper: 5),
                  requirement: QualityGateRuleRequirement.required,
                  severity: QualityGateRuleSeverity.blocking,
                  missingDataPolicy: QualityGateMissingDataPolicy.fail,
                  incompatibleDataPolicy:
                      QualityGateIncompatibleDataPolicy.fail,
                  evidencePolicy: kReleaseGateEvidencePolicy,
                  explanationTemplateId: 'range',
                  order: 1,
                ),
              ],
            ),
          ],
        ),
      );
      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('inverted range')));
    });

    test('rejects NaN decimal via fromJson', () {
      expect(
        () => QualityGateDecimalValue.fromJson({
          'valueKind': 'decimal',
          'value': double.nan,
        }),
        throwsFormatException,
      );
    });

    test('warns when required rule is disabled', () {
      final base = QualityGateReleasePolicyV1.create();
      final disabledRule = QualityGateRule(
        ruleId: 'DIS001',
        name: 'Disabled',
        description: 'Disabled',
        target: QualityGateRuleTarget.guardianDecision,
        operator: QualityGateRuleOperator.isTrue,
        requirement: QualityGateRuleRequirement.required,
        severity: QualityGateRuleSeverity.blocking,
        missingDataPolicy: QualityGateMissingDataPolicy.unavailable,
        incompatibleDataPolicy: QualityGateIncompatibleDataPolicy.incompatible,
        evidencePolicy: kReleaseGateEvidencePolicy,
        explanationTemplateId: 'disabled',
        enabled: false,
        order: 99,
      );
      final result = validator.validate(
        QualityGatePolicy(
          metadata: base.metadata,
          governance: base.governance,
          decisionPolicy: base.decisionPolicy,
          requiredSourceTypes: base.requiredSourceTypes,
          ruleSets: [
            ...base.ruleSets,
            QualityGateRuleSet(
              ruleSetId: 'disabled-set',
              name: 'Disabled',
              description: 'Disabled',
              aggregationMode: QualityGateRuleSetAggregationMode.all,
              required: true,
              severity: QualityGateRuleSeverity.blocking,
              order: 99,
              rules: [disabledRule],
            ),
          ],
        ),
      );
      expect(
        result.warnings,
        contains(contains('required rule is disabled')),
      );
    });
  });

  group('QualityGateRuleValue', () {
    test('normalizes negative zero decimal', () {
      final value = QualityGateDecimalValue.fromJson({
        'valueKind': 'decimal',
        'value': -0.0,
      });
      expect(value.value, 0.0);
      expect(value.value.isNegative, isFalse);
    });

    test('rejects invalid percentage', () {
      expect(
        () => QualityGatePercentageValue.fromJson({
          'valueKind': 'percentage',
          'value': 120,
        }),
        throwsFormatException,
      );
    });

    test('set value sorts deterministically in JSON', () {
      final set = QualityGateSetValue.fromJson({
        'valueKind': 'set',
        'values': ['b', 'a'],
      });
      final json = set.toJson();
      expect(json['values'], ['a', 'b']);
    });
  });

  group('QualityGateRequest', () {
    test('defaults useLatest and historicalEvaluation to false', () {
      const request = QualityGateRequest(
        projectId: 'proj-1',
        createdAt: '2026-01-01T00:00:00.000Z',
        referenceTime: '2026-01-01T00:00:00.000Z',
      );
      expect(request.useLatest, isFalse);
      expect(request.historicalEvaluation, isFalse);
      expect(request.strictCompatibility, isFalse);
    });

    test('round-trips scalar fields through JSON', () {
      const request = QualityGateRequest(
        projectId: 'proj-1',
        policyId: QualityGateReleasePolicyV1.policyId,
        policyVersion: 1,
        commitId: 'abc123',
        createdAt: '2026-01-01T00:00:00.000Z',
        referenceTime: '2026-01-01T00:00:00.000Z',
        requestedRuleIds: {'QG001'},
      );
      final restored = QualityGateRequest.fromJson(request.toJson());
      expect(restored.projectId, request.projectId);
      expect(restored.policyId, request.policyId);
      expect(restored.commitId, request.commitId);
      expect(restored.requestedRuleIds, request.requestedRuleIds);
    });
  });

  group('QualityGateSnapshot', () {
    test('round-trips through JSON', () {
      final snapshot = QualityGateSnapshot(
        metadata: const QualityGateSnapshotMetadata(
          qualityGateSnapshotId: 'qg-1',
          qualityGateFingerprint: 'fp-1',
          requestFingerprint: 'req-1',
          policyFingerprint: 'pol-1',
          projectId: 'proj-1',
          schemaVersion: 1,
          calculationVersion: 1,
          canonicalizationVersion: 1,
          createdAt: '2026-01-01T00:00:00.000Z',
          evaluatedAt: '2026-01-01T00:00:01.000Z',
          decision: QualityGateDecision.failed,
          policyId: QualityGateReleasePolicyV1.policyId,
          policyVersion: 1,
          totalRuleCount: 15,
          evaluatedRuleCount: 11,
          failedRuleCount: 2,
          blockingFailureCount: 1,
          warningCount: 1,
          errorCount: 0,
          sourceCount: 4,
        ),
        policyReference: const QualityGatePolicyVersion(
          policyId: QualityGateReleasePolicyV1.policyId,
          policyVersion: 1,
          schemaVersion: 1,
          calculationVersion: 1,
          canonicalizationVersion: 1,
        ),
        decision: QualityGateDecision.failed,
        eligibility: const QualityGateEligibility(
          status: QualityGateEligibilityStatus.eligible,
          reasons: [],
          requiredSources: [QualityGateSourceType.metrics],
          availableSources: [QualityGateSourceType.metrics],
          missingSources: [],
          incompatibleSources: [],
          eligibilityFingerprint: 'elig-1',
        ),
        compatibility: const QualityGateCompatibility(
          status: QualityGateCompatibilityStatus.compatible,
          checks: [],
          compatibleSources: [QualityGateSourceType.metrics],
          partiallyCompatibleSources: [],
          incompatibleSources: [],
          unknownSources: [],
          reasons: [],
          compatibilityFingerprint: 'compat-1',
        ),
        coverage: const QualityGateCoverage(
          totalRuleCount: 15,
          enabledRuleCount: 15,
          evaluatedRuleCount: 11,
          passedRuleCount: 9,
          failedRuleCount: 2,
          unavailableRuleCount: 0,
          incompatibleRuleCount: 0,
          skippedRuleCount: 4,
          notApplicableRuleCount: 0,
          requiredRuleCount: 11,
          evaluatedRequiredRuleCount: 11,
          requiredRuleCoveragePercentage: 100,
          overallRuleCoveragePercentage: 73.33,
          evidenceCoveragePercentage: 100,
          sourceCoveragePercentage: 100,
          ruleSetCoverage: {},
          missingRuleIds: [],
          missingSourceTypes: [],
          limitations: [],
        ),
        evaluations: const [],
        ruleSetEvaluations: const [],
        evidence: const [],
        sourceReferences: const [],
        explanations: const [],
        warnings: const [],
        errors: const [],
        limitations: const [],
      );

      final restored = QualityGateSnapshot.fromJson(snapshot.toJson());
      expect(restored.metadata.qualityGateSnapshotId, 'qg-1');
      expect(restored.decision, QualityGateDecision.failed);
      expect(restored.coverage.passedRuleCount, 9);
    });

    test('toComparableJson excludes temporal metadata fields', () {
      final snapshot = QualityGateSnapshot(
        metadata: const QualityGateSnapshotMetadata(
          qualityGateSnapshotId: 'qg-1',
          qualityGateFingerprint: 'fp-1',
          requestFingerprint: 'req-1',
          policyFingerprint: 'pol-1',
          projectId: 'proj-1',
          schemaVersion: 1,
          calculationVersion: 1,
          canonicalizationVersion: 1,
          createdAt: '2026-01-01T00:00:00.000Z',
          evaluatedAt: '2026-01-01T00:00:01.000Z',
          decision: QualityGateDecision.passed,
          policyId: QualityGateReleasePolicyV1.policyId,
          policyVersion: 1,
          totalRuleCount: 15,
          evaluatedRuleCount: 15,
          failedRuleCount: 0,
          blockingFailureCount: 0,
          warningCount: 0,
          errorCount: 0,
          sourceCount: 4,
        ),
        policyReference: const QualityGatePolicyVersion(
          policyId: QualityGateReleasePolicyV1.policyId,
          policyVersion: 1,
          schemaVersion: 1,
          calculationVersion: 1,
          canonicalizationVersion: 1,
        ),
        decision: QualityGateDecision.passed,
        eligibility: const QualityGateEligibility(
          status: QualityGateEligibilityStatus.eligible,
          reasons: [],
          requiredSources: [],
          availableSources: [],
          missingSources: [],
          incompatibleSources: [],
          eligibilityFingerprint: 'elig-1',
        ),
        compatibility: const QualityGateCompatibility(
          status: QualityGateCompatibilityStatus.compatible,
          checks: [],
          compatibleSources: [],
          partiallyCompatibleSources: [],
          incompatibleSources: [],
          unknownSources: [],
          reasons: [],
          compatibilityFingerprint: 'compat-1',
        ),
        coverage: const QualityGateCoverage(
          totalRuleCount: 15,
          enabledRuleCount: 15,
          evaluatedRuleCount: 15,
          passedRuleCount: 15,
          failedRuleCount: 0,
          unavailableRuleCount: 0,
          incompatibleRuleCount: 0,
          skippedRuleCount: 0,
          notApplicableRuleCount: 0,
          requiredRuleCount: 11,
          evaluatedRequiredRuleCount: 11,
          requiredRuleCoveragePercentage: 100,
          overallRuleCoveragePercentage: 100,
          evidenceCoveragePercentage: 100,
          sourceCoveragePercentage: 100,
          ruleSetCoverage: {},
          missingRuleIds: [],
          missingSourceTypes: [],
          limitations: [],
        ),
        evaluations: const [],
        ruleSetEvaluations: const [],
        evidence: const [],
        sourceReferences: const [],
        explanations: const [],
        warnings: const [],
        errors: const [],
        limitations: const [],
      );

      final comparable = snapshot.toComparableJson();
      final meta = comparable['metadata'] as Map<String, dynamic>;
      expect(meta.containsKey('createdAt'), isFalse);
      expect(meta.containsKey('evaluatedAt'), isFalse);
    });
  });

  group('QualityGateResult', () {
    test('distinguishes execution success from gate failure', () {
      const result = QualityGateResult(
        status: QualityGateResultStatus.success,
      );
      expect(result.status, QualityGateResultStatus.success);
      expect(result.snapshot, isNull);
    });
  });
}
