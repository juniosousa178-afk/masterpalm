import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/cicd_integration_provider.dart';
import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/interfaces/release_supply_chain_provider.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_operational_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_result.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_fingerprint.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_models.dart';
import 'package:masterpalm_platform/cicd_integration/resolved_cicd_integration_sources.dart';

import '../../release_evidence/support/release_evidence_test_fixtures.dart';
import '../../release_governance/support/release_governance_test_fixtures.dart';
import '../../release_supply_chain/support/release_supply_chain_test_fixtures.dart';
import 'cicd_integration_operational_fixtures.dart';
import 'pipeline_test_fixtures.dart';

/// Builds a deterministic passing CI/CD integration evaluation via PlatformCore.
Future<CicdIntegrationResult> evaluatePassingSnapshot({
  CicdIntegrationProvider? provider,
  ReleaseEvidenceProvider? evidenceProvider,
  ReleaseSupplyChainProvider? supplyChainProvider,
}) async {
  final core = PlatformBootstrap.forRepo(Directory.current.path);
  final rg = core.releaseGovernance();
  final re = evidenceProvider ?? core.releaseEvidence();
  final rsc = supplyChainProvider ?? core.releaseSupplyChain();
  final cicd = provider ?? core.cicdIntegration();

  final rgResult = await rg.evaluate(
    ReleaseGovernanceTestFixtures.passingRequest(),
  );
  final reResult = await re.evaluate(
    ReleaseEvidenceTestFixtures.passingRequest(
      releaseDecisionSnapshot: rgResult.snapshot,
    ),
  );
  final rscResult = await rsc.evaluate(
    ReleaseSupplyChainTestFixtures.passingRequest(
      releaseDecisionSnapshot: rgResult.snapshot,
      releaseEvidenceBundle: reResult.bundle,
    ),
  );
  return cicd.evaluate(
    CicdIntegrationOperationalFixtures.passingRequest(
      releaseEvidenceBundle: reResult.bundle,
      releaseSupplyChainSnapshot: rscResult.snapshot,
    ),
  );
}

/// Builds and publishes a deterministic passing CI/CD integration snapshot.
Future<CicdIntegrationResult> publishPassingSnapshot({
  CicdIntegrationProvider? provider,
  ReleaseEvidenceProvider? evidenceProvider,
  ReleaseSupplyChainProvider? supplyChainProvider,
}) async {
  final core = PlatformBootstrap.forRepo(Directory.current.path);
  final rg = core.releaseGovernance();
  final re = evidenceProvider ?? core.releaseEvidence();
  final rsc = supplyChainProvider ?? core.releaseSupplyChain();
  final cicd = provider ?? core.cicdIntegration();

  final rgResult = await rg.evaluate(
    ReleaseGovernanceTestFixtures.passingRequest(),
  );
  final reResult = await re.evaluate(
    ReleaseEvidenceTestFixtures.passingRequest(
      releaseDecisionSnapshot: rgResult.snapshot,
    ),
  );
  final rscResult = await rsc.evaluate(
    ReleaseSupplyChainTestFixtures.passingRequest(
      releaseDecisionSnapshot: rgResult.snapshot,
      releaseEvidenceBundle: reResult.bundle,
    ),
  );
  return cicd.evaluateAndPublish(
    CicdIntegrationOperationalFixtures.passingRequest(
      releaseEvidenceBundle: reResult.bundle,
      releaseSupplyChainSnapshot: rscResult.snapshot,
    ),
  );
}

ResolvedCicdIntegrationSource<T> cicdNotRequested<T>(
  CicdIntegrationSourceType sourceType,
) {
  return ResolvedCicdIntegrationSource<T>(
    sourceType: sourceType,
    resolutionMode: CicdIntegrationSourceResolutionMode.notRequested,
    state: CicdIntegrationSourceState.notRequested,
  );
}

/// Builds a large pipeline definition for stress tests.
PipelineDefinition buildLargePipelineDefinition({int stageCount = 500}) {
  final stages = <PipelineStage>[];
  for (var i = 0; i < stageCount; i++) {
    stages.add(
      PipelineStage(
        stageId: 'stage-${i.toString().padLeft(5, '0')}',
        name: 'Stage $i',
        stageType: PipelineStageType.sequential,
        order: i,
        steps: [
          PipelineStep(
            stepId: 'step-$i',
            name: 'Step $i',
            stepType: PipelineStepType.build,
            order: 0,
          ),
        ],
      ),
    );
  }
  final comparable = {
    'definitionId': 'def-stress',
    'name': 'Stress Pipeline',
    'version': 1,
    'stages': stages.map((s) => s.toComparableJson()).toList(),
    'triggers': [PipelineTestFixtures.validTrigger().toComparableJson()],
    'environments': [
      PipelineTestFixtures.validEnvironment().toComparableJson()
    ],
    'artifacts': [PipelineTestFixtures.validArtifact().toComparableJson()],
    'schemaVersion': PipelineDefinition.currentSchemaVersion,
    'canonicalizationVersion':
        PipelineDefinition.currentCanonicalizationVersion,
  };
  final fingerprint = PipelineFingerprint.fromComparableJson(comparable);

  return PipelineDefinition(
    definitionId: 'def-stress',
    name: 'Stress Pipeline',
    version: 1,
    stages: stages,
    triggers: [PipelineTestFixtures.validTrigger()],
    environments: [PipelineTestFixtures.validEnvironment()],
    artifacts: [PipelineTestFixtures.validArtifact()],
    fingerprint: fingerprint,
    metadata: {'projectId': PipelineTestFixtures.projectId},
  );
}
