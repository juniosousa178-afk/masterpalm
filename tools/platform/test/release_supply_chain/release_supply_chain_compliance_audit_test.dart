import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:masterpalm_platform/models/release_supply_chain/compliance_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_operational_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_operational_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_result.dart';
import 'package:masterpalm_platform/release_supply_chain/compliance_engine.dart';
import 'package:masterpalm_platform/release_supply_chain/compliance_validator.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/compliance_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/distribution_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/supply_chain_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_collector.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_snapshot_validator.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_source_resolver.dart';
import 'package:masterpalm_platform/release_supply_chain/resolved_release_supply_chain_sources.dart';
import 'package:test/test.dart';

import 'support/release_supply_chain_hardening_helpers.dart';
import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('Release Supply Chain compliance audit', () {
    const complianceEngine = ComplianceEngine();
    const complianceValidator = ComplianceValidator();
    const snapshotValidator = ReleaseSupplyChainSnapshotValidator();

    ReleaseSupplyChainEvaluationContext buildContext() {
      return ReleaseSupplyChainEvaluationContext(
        request: ReleaseSupplyChainTestFixtures.passingRequest(),
        sources: ResolvedReleaseSupplyChainSources(
          releaseContext: ResolvedReleaseSupplyChainSource(
            sourceType: ReleaseSupplyChainSourceType.releaseContext,
            resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
            state: ReleaseSupplyChainSourceState.available,
            resolvedArtifact: ReleaseSupplyChainTestFixtures.validContext(),
          ),
          qualityGateSnapshot: rscNotRequested(),
          releaseDecisionSnapshot: rscNotRequested(),
          releaseEvidenceBundle: rscNotRequested(),
          supplyChainPolicy: rscNotRequested(),
          distributionPolicy: rscNotRequested(),
          compliancePolicy: rscNotRequested(),
          sourceReferences: const [],
          resolutionSummary: const ReleaseSupplyChainSourceResolutionSummary(
            resolvedSources: [],
            unresolvedSources: [],
            injectedSources: [],
          ),
        ),
        supplyChainPolicy: SupplyChainPolicyV1.create(),
        distributionPolicy: DistributionPolicyV1.create(),
        compliancePolicy: CompliancePolicyV1.create(),
      );
    }

    test('inconsistent projectId surfaces resolver limitation', () async {
      final base = ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot();
      final json = base.toJson();
      (json['metadata'] as Map<String, dynamic>)['projectId'] = 'other-project';
      final mismatched = QualityGateSnapshot.fromJson(json);
      final resolver = ReleaseSupplyChainSourceResolver(
        qualityGateProvider: FakeQualityGateProviderForSupplyChain(),
        releaseGovernanceProvider:
            FakeReleaseGovernanceProviderForSupplyChain(),
        releaseEvidenceProvider: FakeReleaseEvidenceProviderForSupplyChain(),
      );

      final sources = await resolver.resolveAll(
        ReleaseSupplyChainTestFixtures.passingRequest(
          qualityGateSnapshot: mismatched,
        ),
        injectedSupplyChainPolicy: SupplyChainPolicyV1.create(),
        injectedDistributionPolicy: DistributionPolicyV1.create(),
        injectedCompliancePolicy: CompliancePolicyV1.create(),
      );

      expect(sources.compatibilityHints, isNotEmpty);
      expect(
        sources.limitations
            .any((l) => l.limitationId.contains('project-mismatch')),
        isTrue,
      );
    });

    test('missing fingerprints fail snapshot validation', () {
      final snapshot = ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot()
          .copyWith(fingerprint: '');
      final result = snapshotValidator.validate(snapshot);
      expect(result.isValid, isFalse);
      expect(result.errors, isNotEmpty);
    });

    test('missing compliance fingerprint fails validator', () {
      final compliance = ReleaseSupplyChainTestFixtures.validComplianceResult()
          .copyWith(fingerprint: '');
      final result = complianceValidator.validate(compliance);
      expect(result.isValid, isFalse);
    });

    test('compliance policy explicitly never approves release', () {
      final policy = CompliancePolicyV1.create();
      expect(
        policy.metadata.limitations,
        contains('never-approves-release'),
      );
      expect(
        policy.policy.limitations,
        contains('never-approves-release'),
      );
    });

    test('compliance result status is descriptive not authorization', () {
      final context = buildContext();
      final collected = const ReleaseSupplyChainCollector().collect(context);
      final result = complianceEngine.evaluate(
        context: context,
        collected: collected,
        evaluatedAt: ReleaseSupplyChainTestFixtures.referenceTime,
      );

      expect(
        [
          ComplianceStatus.compliant,
          ComplianceStatus.nonCompliant,
          ComplianceStatus.unknown,
        ],
        contains(result.status),
      );
      expect(result.toJson().containsKey('releaseAuthorized'), isFalse);
      expect(result.toJson().containsKey('approved'), isFalse);
    });

    test('nonCompliant result requires violations in validator', () {
      final comp =
          ReleaseSupplyChainTestFixtures.validComplianceResult().copyWith(
        status: ComplianceStatus.nonCompliant,
        violations: const [],
      );
      expect(complianceValidator.validate(comp).isValid, isFalse);
    });
  });
}
