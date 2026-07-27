import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/quality_gate_provider.dart';
import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/interfaces/release_governance_provider.dart';
import 'package:masterpalm_platform/interfaces/release_supply_chain_provider.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_request.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_query.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_request.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_result.dart';
import 'package:masterpalm_platform/models/release_governance/release_decision_snapshot.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_request.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_request.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_result.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_snapshot.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_operational_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/sbom_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/supply_chain_models.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_collector.dart';
import 'package:masterpalm_platform/release_supply_chain/resolved_release_supply_chain_sources.dart';

import '../../release_evidence/support/release_evidence_test_fixtures.dart';
import '../../release_governance/support/release_governance_test_fixtures.dart';
import 'release_supply_chain_test_fixtures.dart';

/// Builds a deterministic passing evaluation via PlatformCore.
Future<ReleaseSupplyChainResult> evaluatePassingSnapshot({
  ReleaseSupplyChainProvider? provider,
  ReleaseGovernanceProvider? governanceProvider,
  ReleaseEvidenceProvider? evidenceProvider,
}) async {
  final core = PlatformBootstrap.forRepo(Directory.current.path);
  final rg = governanceProvider ?? core.releaseGovernance();
  final re = evidenceProvider ?? core.releaseEvidence();
  final rsc = provider ?? core.releaseSupplyChain();
  final rgResult =
      await rg.evaluate(ReleaseGovernanceTestFixtures.passingRequest());
  final reResult = await re.evaluate(
    ReleaseEvidenceTestFixtures.passingRequest(
      releaseDecisionSnapshot: rgResult.snapshot,
    ),
  );
  return rsc.evaluate(
    ReleaseSupplyChainTestFixtures.passingRequest(
      releaseDecisionSnapshot: rgResult.snapshot,
      releaseEvidenceBundle: reResult.bundle,
    ),
  );
}

class FakeQualityGateProviderForSupplyChain implements QualityGateProvider {
  FakeQualityGateProviderForSupplyChain({this.loaded, this.latestSnapshot});

  QualityGateSnapshot? loaded;
  QualityGateSnapshot? latestSnapshot;
  int loadCalls = 0;
  int latestCalls = 0;
  int evaluateCalls = 0;

  @override
  Future<QualityGateResult> evaluate(QualityGateRequest request) async {
    evaluateCalls++;
    throw StateError('QualityGateProvider.evaluate must not be called');
  }

  @override
  Future<QualityGateResult> evaluateAndPublish(
    QualityGateRequest request,
  ) async {
    evaluateCalls++;
    throw StateError(
        'QualityGateProvider.evaluateAndPublish must not be called');
  }

  @override
  Future<void> publish(QualityGateSnapshot snapshot) async {}

  @override
  Future<QualityGateSnapshot?> load(String snapshotId) async {
    loadCalls++;
    return loaded;
  }

  @override
  Future<QualityGateSnapshot?> latest({
    required String projectId,
    String? policyId,
  }) async {
    latestCalls++;
    return latestSnapshot;
  }

  @override
  Future<List<QualityGateSnapshot>> query(query) async => const [];

  @override
  Future<void> invalidate(String snapshotId) async {}
}

class FakeReleaseGovernanceProviderForSupplyChain
    implements ReleaseGovernanceProvider {
  FakeReleaseGovernanceProviderForSupplyChain(
      {this.loaded, this.latestSnapshot});

  ReleaseDecisionSnapshot? loaded;
  ReleaseDecisionSnapshot? latestSnapshot;
  int loadCalls = 0;
  int latestCalls = 0;
  int evaluateCalls = 0;

  @override
  Future<ReleaseGovernanceResult> evaluate(
    ReleaseGovernanceRequest request,
  ) async {
    evaluateCalls++;
    throw StateError('ReleaseGovernanceProvider.evaluate must not be called');
  }

  @override
  Future<ReleaseGovernanceResult> evaluateAndPublish(
    ReleaseGovernanceRequest request,
  ) async {
    evaluateCalls++;
    throw StateError(
      'ReleaseGovernanceProvider.evaluateAndPublish must not be called',
    );
  }

  @override
  Future<void> publish(ReleaseDecisionSnapshot snapshot) async {}

  @override
  Future<ReleaseDecisionSnapshot?> load(String snapshotId) async {
    loadCalls++;
    return loaded;
  }

  @override
  Future<ReleaseDecisionSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async {
    latestCalls++;
    return latestSnapshot;
  }

  @override
  Future<List<ReleaseDecisionSnapshot>> query(query) async => const [];

  @override
  Future<void> invalidate(String snapshotId) async {}
}

class FakeReleaseEvidenceProviderForSupplyChain
    implements ReleaseEvidenceProvider {
  FakeReleaseEvidenceProviderForSupplyChain({this.loaded, this.latestBundle});

  ReleaseEvidenceBundle? loaded;
  ReleaseEvidenceBundle? latestBundle;
  int loadCalls = 0;
  int latestCalls = 0;
  int evaluateCalls = 0;

  @override
  Future<ReleaseEvidenceResult> evaluate(ReleaseEvidenceRequest request) async {
    evaluateCalls++;
    throw StateError('ReleaseEvidenceProvider.evaluate must not be called');
  }

  @override
  Future<ReleaseEvidenceResult> evaluateAndPublish(
    ReleaseEvidenceRequest request,
  ) async {
    evaluateCalls++;
    throw StateError(
      'ReleaseEvidenceProvider.evaluateAndPublish must not be called',
    );
  }

  @override
  Future<void> publish(ReleaseEvidenceBundle bundle) async {}

  @override
  Future<ReleaseEvidenceBundle?> load(String bundleId) async {
    loadCalls++;
    return loaded;
  }

  @override
  Future<ReleaseEvidenceBundle?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async {
    latestCalls++;
    return latestBundle;
  }

  @override
  Future<List<ReleaseEvidenceBundle>> query(ReleaseEvidenceQuery query) async =>
      const [];

  @override
  Future<void> invalidate(String bundleId) async {}
}

ResolvedReleaseSupplyChainSource<T> rscNotRequested<T>() {
  return const ResolvedReleaseSupplyChainSource(
    sourceType: ReleaseSupplyChainSourceType.releaseContext,
    resolutionMode: ReleaseSupplyChainSourceResolutionMode.notRequested,
    state: ReleaseSupplyChainSourceState.notRequested,
  );
}

SupplyChainRecord buildLargeSupplyChainGraph({int nodeCount = 500}) {
  final actors = [
    const SupplyChainActor(
      actorId: 'actor-ci',
      actorType: SupplyChainActorType.pipeline,
      name: 'CI Pipeline',
    ),
  ];
  final stages = <SupplyChainStage>[];
  final nodes = <SupplyChainNode>[];
  for (var i = 0; i < nodeCount; i++) {
    final stageId = 'stage-$i';
    stages.add(
      SupplyChainStage(
        stageId: stageId,
        stageType: SupplyChainStageType.build,
        name: 'Stage $i',
        actorId: 'actor-ci',
        outputArtifactIds: ['art-$i'],
      ),
    );
    nodes.add(
      SupplyChainNode(
        nodeId: 'node-$i',
        stageId: stageId,
        artifactId: 'art-$i',
        fingerprint: 'fp-$i',
      ),
    );
  }
  return SupplyChainRecord(
    recordId: 'sc-stress',
    projectId: ReleaseSupplyChainTestFixtures.projectId,
    releaseId: ReleaseSupplyChainTestFixtures.releaseId,
    status: SupplyChainStatus.active,
    fingerprint: 'fp-sc-stress',
    policy: ReleaseSupplyChainTestFixtures.validSupplyChainPolicy(),
    actors: actors,
    stages: stages,
    nodes: nodes,
    edges: const [],
    evidence: const [],
    schemaVersion: SupplyChainRecord.currentSchemaVersion,
    createdAt: ReleaseSupplyChainTestFixtures.referenceTime,
    recordedAt: ReleaseSupplyChainTestFixtures.referenceTime,
  );
}

SoftwareBillOfMaterials buildLargeSbom({int componentCount = 500}) {
  final components = List.generate(
    componentCount,
    (i) => SbomComponent(
      componentId: 'comp-${i.toString().padLeft(5, '0')}',
      componentType: SbomComponentType.library,
      packageRef: SbomPackage(
        packageId: 'pkg-$i',
        name: 'package-$i',
        version: '1.0.$i',
      ),
      hashes: const [],
    ),
  );
  return SoftwareBillOfMaterials(
    metadata: SbomMetadata(
      sbomId: 'sbom-stress',
      projectId: ReleaseSupplyChainTestFixtures.projectId,
      releaseId: ReleaseSupplyChainTestFixtures.releaseId,
      schemaVersion: SbomMetadata.currentSchemaVersion,
      canonicalizationVersion: SbomMetadata.currentCanonicalizationVersion,
      createdAt: ReleaseSupplyChainTestFixtures.referenceTime,
      generatedAt: ReleaseSupplyChainTestFixtures.referenceTime,
      status: SbomStatus.complete,
      fingerprint: 'fp-sbom-stress',
      componentCount: componentCount,
      dependencyCount: 0,
    ),
    components: components,
    dependencies: const [],
  );
}
