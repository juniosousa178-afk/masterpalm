import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_governance.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_messages.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_query.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:masterpalm_platform/quality_gate/policies/quality_gate_release_policy_v1.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_exceptions.dart';
import 'package:masterpalm_platform/quality_gate/stores/in_memory_quality_gate_store.dart';
import 'package:test/test.dart';

QualityGateSnapshot _minimalSnapshot({
  required String id,
  String fingerprint = 'fp-1',
  QualityGateDecision decision = QualityGateDecision.passed,
}) {
  return QualityGateSnapshot(
    metadata: QualityGateSnapshotMetadata(
      qualityGateSnapshotId: id,
      qualityGateFingerprint: fingerprint,
      requestFingerprint: 'req-1',
      policyFingerprint: 'pol-1',
      projectId: 'demo-project',
      schemaVersion: 1,
      calculationVersion: 1,
      canonicalizationVersion: 1,
      createdAt: '2026-01-01T00:00:00.000Z',
      evaluatedAt: '2026-01-01T00:00:01.000Z',
      decision: decision,
      policyId: QualityGateReleasePolicyV1.policyId,
      policyVersion: 1,
      totalRuleCount: 1,
      evaluatedRuleCount: 1,
      failedRuleCount: decision == QualityGateDecision.failed ? 1 : 0,
      blockingFailureCount: 0,
      warningCount: 0,
      errorCount: 0,
      sourceCount: 1,
    ),
    policyReference: const QualityGatePolicyVersion(
      policyId: QualityGateReleasePolicyV1.policyId,
      policyVersion: 1,
      schemaVersion: 1,
      calculationVersion: 1,
      canonicalizationVersion: 1,
    ),
    decision: decision,
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
      totalRuleCount: 1,
      enabledRuleCount: 1,
      evaluatedRuleCount: 1,
      passedRuleCount: 1,
      failedRuleCount: 0,
      unavailableRuleCount: 0,
      incompatibleRuleCount: 0,
      skippedRuleCount: 0,
      notApplicableRuleCount: 0,
      requiredRuleCount: 1,
      evaluatedRequiredRuleCount: 1,
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
}

void main() {
  group('InMemoryQualityGateStore', () {
    test('save and load', () async {
      final store = InMemoryQualityGateStore();
      final snapshot = _minimalSnapshot(id: 'qg-1');
      await store.save(snapshot);
      expect(await store.exists('qg-1'), isTrue);
      expect(await store.load('qg-1'), isNotNull);
    });

    test('idempotent save with same fingerprint', () async {
      final store = InMemoryQualityGateStore();
      final snapshot = _minimalSnapshot(id: 'qg-1');
      await store.save(snapshot);
      await store.save(snapshot);
      expect(await store.count(), 1);
    });

    test('conflict on same id different fingerprint', () async {
      final store = InMemoryQualityGateStore();
      await store.save(_minimalSnapshot(id: 'qg-1', fingerprint: 'fp-1'));
      expect(
        () => store.save(_minimalSnapshot(id: 'qg-1', fingerprint: 'fp-2')),
        throwsA(isA<QualityGateSnapshotConflictException>()),
      );
    });

    test('query filters by decision', () async {
      final store = InMemoryQualityGateStore();
      await store.save(
        _minimalSnapshot(id: 'qg-pass', decision: QualityGateDecision.passed),
      );
      await store.save(
        _minimalSnapshot(id: 'qg-fail', decision: QualityGateDecision.failed),
      );
      final failed = await store.query(
        const QualityGateQuery(decision: QualityGateDecision.failed),
      );
      expect(failed, hasLength(1));
      expect(failed.first.metadata.qualityGateSnapshotId, 'qg-fail');
    });
  });
}
