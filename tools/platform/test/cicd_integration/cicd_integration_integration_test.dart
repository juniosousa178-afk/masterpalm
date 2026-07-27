import 'dart:io';

import 'package:masterpalm_platform/cicd_integration/cicd_integration_artifact_registry.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_collector.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_exceptions.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_policy_registry.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_snapshot_validator.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_source_resolver.dart';
import 'package:masterpalm_platform/cicd_integration/policies/deployment_integration_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_execution_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_integration_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/resolved_cicd_integration_sources.dart';
import 'package:masterpalm_platform/cicd_integration/stores/in_memory_cicd_integration_store.dart';
import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/dashboard/builders/cicd_deployment_section_builder.dart';
import 'package:masterpalm_platform/dashboard/builders/cicd_execution_section_builder.dart';
import 'package:masterpalm_platform/dashboard/builders/cicd_pipeline_section_builder.dart';
import 'package:masterpalm_platform/dashboard/builders/dashboard_section_context.dart';
import 'package:masterpalm_platform/dashboard/dashboard_source_resolver.dart';
import 'package:masterpalm_platform/history/history_comparator.dart';
import 'package:masterpalm_platform/history/mappers/cicd_integration_history_mapper.dart';
import 'package:masterpalm_platform/interfaces/cicd_integration_provider.dart';
import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/interfaces/release_supply_chain_provider.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_exceptions.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_operational_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_result.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_snapshot.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_enums.dart';
import 'package:masterpalm_platform/models/dashboard/dashboard_enums.dart';
import 'package:masterpalm_platform/models/dashboard/dashboard_request.dart';
import 'package:masterpalm_platform/models/history/history_artifact_type.dart';
import 'package:masterpalm_platform/models/history/history_metadata.dart';
import 'package:masterpalm_platform/models/history/history_snapshot.dart';
import 'package:masterpalm_platform/models/history/history_snapshot_status.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/providers/platform_cicd_integration_provider.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:masterpalm_platform/report/sources/cicd_integration_report_source.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import '../release_governance/support/release_governance_test_fixtures.dart';
import '../release_supply_chain/support/release_supply_chain_test_fixtures.dart';
import 'support/cicd_integration_fake_providers.dart';
import 'support/cicd_integration_operational_fixtures.dart';
import 'support/pipeline_test_fixtures.dart';

void main() {
  group('CI/CD Integration integration', () {
    late CicdIntegrationProvider cicdProvider;
    late ReleaseEvidenceProvider evidenceProvider;
    late ReleaseSupplyChainProvider supplyChainProvider;

    setUp(() {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      cicdProvider = core.cicdIntegration();
      evidenceProvider = core.releaseEvidence();
      supplyChainProvider = core.releaseSupplyChain();
    });

    Future<(dynamic, dynamic)> buildUpstreamArtifacts() async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final rgResult = await core.releaseGovernance().evaluate(
            ReleaseGovernanceTestFixtures.passingRequest(),
          );
      final reResult = await evidenceProvider.evaluate(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
      );
      final rscResult = await supplyChainProvider.evaluate(
        ReleaseSupplyChainTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
          releaseEvidenceBundle: reResult.bundle,
        ),
      );
      return (reResult.bundle, rscResult.snapshot);
    }

    Future<CicdIntegrationSnapshot> evaluatePublishedSnapshot() async {
      final (evidence, supplyChain) = await buildUpstreamArtifacts();
      final result = await cicdProvider.evaluateAndPublish(
        CicdIntegrationOperationalFixtures.passingRequest(
          releaseEvidenceBundle: evidence,
          releaseSupplyChainSnapshot: supplyChain,
        ),
      );
      expect(result.snapshot, isNotNull);
      return result.snapshot!;
    }

    test('source resolver prefers injected snapshots over byId', () async {
      final registry = CicdIntegrationArtifactRegistry();
      final registryDefinition =
          PipelineTestFixtures.validDefinition().copyWith(
        definitionId: 'def-registry-only',
        name: 'Registry Definition',
      );
      registry.registerDefinition(registryDefinition);

      final injectedDefinition = PipelineTestFixtures.validDefinition();
      final fakeEvidence = FakeReleaseEvidenceProviderForCicd();
      final fakeSupplyChain = FakeReleaseSupplyChainProviderForCicd();
      final resolver = CicdIntegrationSourceResolver(
        releaseEvidenceProvider: fakeEvidence,
        releaseSupplyChainProvider: fakeSupplyChain,
        artifactRegistry: registry,
        pipelineIntegrationPolicyRegistry: PipelineIntegrationPolicyRegistry()
          ..register(PipelineIntegrationPolicyV1.create())
          ..freeze(),
        pipelineExecutionPolicyRegistry: PipelineExecutionPolicyRegistry()
          ..register(PipelineExecutionPolicyV1.create())
          ..freeze(),
        deploymentIntegrationPolicyRegistry:
            DeploymentIntegrationPolicyRegistry()
              ..register(DeploymentIntegrationPolicyV1.create())
              ..freeze(),
      );

      final request =
          CicdIntegrationOperationalFixtures.byIdDefinitionRequest().copyWith(
        pipelineDefinition: injectedDefinition,
        pipelineDefinitionId: 'def-registry-only',
      );

      final sources = await resolver.resolveAll(
        request,
        injectedPipelineIntegrationPolicy: PipelineIntegrationPolicyV1.create(),
        injectedPipelineExecutionPolicy: PipelineExecutionPolicyV1.create(),
        injectedDeploymentIntegrationPolicy:
            DeploymentIntegrationPolicyV1.create(),
      );

      expect(sources.pipelineDefinition.isAvailable, isTrue);
      expect(
        sources.pipelineDefinition.resolutionMode,
        CicdIntegrationSourceResolutionMode.injected,
      );
      expect(
        sources.pipelineDefinition.resolvedArtifact!.definitionId,
        injectedDefinition.definitionId,
      );
      expect(sources.resolutionSummary.injectedSources,
          contains('pipelineDefinition'));
      expect(fakeEvidence.evaluateCalls, 0);
      expect(fakeEvidence.evaluateAndPublishCalls, 0);
      expect(fakeSupplyChain.evaluateCalls, 0);
      expect(fakeSupplyChain.evaluateAndPublishCalls, 0);
    });

    test('collector locates artifacts without rebuilding snapshots', () async {
      final (evidence, supplyChain) = await buildUpstreamArtifacts();
      final definition = PipelineTestFixtures.validDefinition();
      final definitionFingerprint = definition.fingerprint;

      final context = CicdIntegrationEvaluationContext(
        request: CicdIntegrationOperationalFixtures.passingRequest(
          releaseEvidenceBundle: evidence,
          releaseSupplyChainSnapshot: supplyChain,
        ),
        sources: ResolvedCicdIntegrationSources(
          pipelineDefinition: ResolvedCicdIntegrationSource(
            sourceType: CicdIntegrationSourceType.pipelineDefinition,
            resolutionMode: CicdIntegrationSourceResolutionMode.injected,
            state: CicdIntegrationSourceState.available,
            resolvedArtifact: definition,
            resolvedId: definition.definitionId,
            fingerprint: definitionFingerprint,
          ),
          pipelineExecution: ResolvedCicdIntegrationSource(
            sourceType: CicdIntegrationSourceType.pipelineExecution,
            resolutionMode: CicdIntegrationSourceResolutionMode.injected,
            state: CicdIntegrationSourceState.available,
            resolvedArtifact: PipelineTestFixtures.validExecution(),
          ),
          pipelineExecutionResult: const ResolvedCicdIntegrationSource(
            sourceType: CicdIntegrationSourceType.pipelineExecutionResult,
            resolutionMode: CicdIntegrationSourceResolutionMode.notRequested,
            state: CicdIntegrationSourceState.notRequested,
          ),
          deploymentPlan: const ResolvedCicdIntegrationSource(
            sourceType: CicdIntegrationSourceType.deploymentPlan,
            resolutionMode: CicdIntegrationSourceResolutionMode.notRequested,
            state: CicdIntegrationSourceState.notRequested,
          ),
          deploymentResult: const ResolvedCicdIntegrationSource(
            sourceType: CicdIntegrationSourceType.deploymentResult,
            resolutionMode: CicdIntegrationSourceResolutionMode.notRequested,
            state: CicdIntegrationSourceState.notRequested,
          ),
          releaseEvidenceBundle: const ResolvedCicdIntegrationSource(
            sourceType: CicdIntegrationSourceType.releaseEvidenceBundle,
            resolutionMode: CicdIntegrationSourceResolutionMode.notRequested,
            state: CicdIntegrationSourceState.notRequested,
          ),
          releaseSupplyChainSnapshot: const ResolvedCicdIntegrationSource(
            sourceType: CicdIntegrationSourceType.releaseSupplyChainSnapshot,
            resolutionMode: CicdIntegrationSourceResolutionMode.notRequested,
            state: CicdIntegrationSourceState.notRequested,
          ),
          pipelineIntegrationPolicy: ResolvedCicdIntegrationSource(
            sourceType: CicdIntegrationSourceType.pipelineIntegrationPolicy,
            resolutionMode: CicdIntegrationSourceResolutionMode.injected,
            state: CicdIntegrationSourceState.available,
            resolvedArtifact: PipelineIntegrationPolicyV1.create(),
          ),
          pipelineExecutionPolicy: ResolvedCicdIntegrationSource(
            sourceType: CicdIntegrationSourceType.pipelineExecutionPolicy,
            resolutionMode: CicdIntegrationSourceResolutionMode.injected,
            state: CicdIntegrationSourceState.available,
            resolvedArtifact: PipelineExecutionPolicyV1.create(),
          ),
          deploymentIntegrationPolicy: ResolvedCicdIntegrationSource(
            sourceType: CicdIntegrationSourceType.deploymentIntegrationPolicy,
            resolutionMode: CicdIntegrationSourceResolutionMode.injected,
            state: CicdIntegrationSourceState.available,
            resolvedArtifact: DeploymentIntegrationPolicyV1.create(),
          ),
          sourceReferences: const [],
          resolutionSummary: const CicdIntegrationSourceResolutionSummary(
            resolvedSources: [],
            unresolvedSources: [],
            injectedSources: [],
          ),
        ),
        pipelineIntegrationPolicy: PipelineIntegrationPolicyV1.create(),
        pipelineExecutionPolicy: PipelineExecutionPolicyV1.create(),
        deploymentIntegrationPolicy: DeploymentIntegrationPolicyV1.create(),
      );

      const collector = CicdIntegrationCollector();
      final collected = collector.collect(context);

      expect(collected.pipelineDefinition, isNotNull);
      expect(collected.pipelineDefinition!.fingerprint, definitionFingerprint);
      expect(collected.pipelineExecution, isNotNull);
    });

    test('report source consumes published snapshot only', () async {
      final snapshot = await evaluatePublishedSnapshot();
      const source = CicdIntegrationReportSource();
      final data = source.fromSnapshot(snapshot);

      expect(data.snapshotId, snapshot.metadata.cicdIntegrationSnapshotId);
      expect(data.fingerprint, snapshot.fingerprint);
      expect(data.projectId, snapshot.metadata.projectId);
    });

    test('history mapper compare empty diff for same snapshot', () async {
      final snapshot = await evaluatePublishedSnapshot();
      const mapper = CicdIntegrationHistoryMapper();
      final changes = mapper.compare(snapshot, snapshot);
      expect(changes, isEmpty);
    });

    test('history mapper compare diff on normative policy change', () async {
      final snapshot = await evaluatePublishedSnapshot();
      final changed = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(
          pipelineIntegrationPolicyVersion: 99,
        ),
      );
      const mapper = CicdIntegrationHistoryMapper();
      final changes = mapper.compare(snapshot, changed);
      expect(changes, isNotEmpty);
      expect(
        changes.any((c) => c.subjectId == 'pipelineIntegrationPolicy'),
        isTrue,
      );
    });

    test('history comparator diff on normative policy change', () async {
      final snapshot = await evaluatePublishedSnapshot();
      final changed = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(
          pipelineIntegrationPolicyVersion: 99,
        ),
      );
      const mapper = CicdIntegrationHistoryMapper();
      final fromArtifact = mapper.fromMap(snapshot.toJson());
      final toArtifact = mapper.fromMap(changed.toJson());
      final metadata = HistoryMetadata(
        historySnapshotId: 'hist-changed',
        historySchemaVersion: HistoryMetadata.currentSchemaVersion,
        historyCanonicalizationVersion:
            HistoryMetadata.currentCanonicalizationVersion,
        projectId: CicdIntegrationOperationalFixtures.projectId,
        createdAt: CicdIntegrationOperationalFixtures.referenceTime,
        snapshotFingerprint: fromArtifact.fingerprint,
        artifactCount: 1,
        artifactTypes: const [HistoryArtifactType.cicdIntegration],
        status: HistorySnapshotStatus.complete,
      );
      final from =
          HistorySnapshot(metadata: metadata, artifacts: [fromArtifact]);
      final to = HistorySnapshot(
        metadata:
            metadata.copyWith(snapshotFingerprint: toArtifact.fingerprint),
        artifacts: [toArtifact],
      );
      const comparator = HistoryComparator();
      final diff = comparator.compare(from, to);
      expect(diff.changes, isNotEmpty);
    });

    test('dashboard sections consume injected snapshot without evaluate',
        () async {
      final fullSnapshot = (await cicdProvider.evaluate(
        CicdIntegrationOperationalFixtures.passingRequest(),
      ))
          .snapshot!;
      final partialSnapshot = (await cicdProvider.evaluate(
        CicdIntegrationOperationalFixtures.partialRequest(),
      ))
          .snapshot!;

      final fullRequest = DashboardRequest(
        projectId: CicdIntegrationOperationalFixtures.projectId,
        createdAt: CicdIntegrationOperationalFixtures.referenceTime,
        referenceTime: CicdIntegrationOperationalFixtures.referenceTime,
        cicdIntegrationSnapshot: fullSnapshot,
        requestedSections: {
          DashboardSectionType.cicdPipeline,
          DashboardSectionType.cicdExecution,
          DashboardSectionType.cicdDeployment,
        },
      );
      final fullSources =
          DashboardResolvedSources(cicdIntegration: fullSnapshot);
      final fullContext = DashboardSectionBuildContext(
        request: fullRequest,
        sources: fullSources,
        compatibility: DashboardCompatibility.compatible,
        freshness: DashboardFreshness.current,
      );

      expect(const CicdPipelineSectionBuilder().build(fullContext).availability,
          DashboardAvailability.available);
      expect(
          const CicdExecutionSectionBuilder().build(fullContext).availability,
          DashboardAvailability.available);
      expect(
          const CicdDeploymentSectionBuilder().build(fullContext).availability,
          DashboardAvailability.available);

      final partialRequest = DashboardRequest(
        projectId: CicdIntegrationOperationalFixtures.projectId,
        createdAt: CicdIntegrationOperationalFixtures.referenceTime,
        referenceTime: CicdIntegrationOperationalFixtures.referenceTime,
        cicdIntegrationSnapshot: partialSnapshot,
        requestedSections: fullRequest.requestedSections,
      );
      final partialContext = DashboardSectionBuildContext(
        request: partialRequest,
        sources: DashboardResolvedSources(cicdIntegration: partialSnapshot),
        compatibility: DashboardCompatibility.compatible,
        freshness: DashboardFreshness.current,
      );

      expect(
        const CicdPipelineSectionBuilder().build(partialContext).availability,
        DashboardAvailability.available,
      );
      expect(
        const CicdExecutionSectionBuilder().build(partialContext).availability,
        DashboardAvailability.available,
      );
      expect(
        const CicdDeploymentSectionBuilder().build(partialContext).availability,
        DashboardAvailability.unavailable,
      );
    });

    test('platform bootstrap registers cicd integration after supply chain',
        () {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      expect(core.cicdIntegration(), isNotNull);
      expect(core.releaseSupplyChain(), isNotNull);
    });

    test('report engine generates cicdIntegration report from snapshot',
        () async {
      final snapshot = await evaluatePublishedSnapshot();
      final engine = ReportEngine();
      final result = await engine.generate(
        ReportRequest(
          reportType: ReportType.cicdIntegration,
          projectId: CicdIntegrationOperationalFixtures.projectId,
          cicdIntegrationSnapshot: snapshot.toJson(),
        ),
      );

      expect(result.document.sections, isNotEmpty);
    });

    group('E2E scenarios', () {
      test('valid pipeline produces complete snapshot', () async {
        final (evidence, supplyChain) = await buildUpstreamArtifacts();
        final result = await cicdProvider.evaluate(
          CicdIntegrationOperationalFixtures.passingRequest(
            releaseEvidenceBundle: evidence,
            releaseSupplyChainSnapshot: supplyChain,
          ),
        );

        expect(result.snapshot!.pipelineDefinition, isNotNull);
        expect(result.snapshot!.pipelineExecution, isNotNull);
        expect(result.snapshot!.deploymentPlan, isNotNull);
        expect(result.snapshot!.status, CicdIntegrationSnapshotStatus.complete);
      });

      test('partial request without deployment yields partial snapshot',
          () async {
        final result = await cicdProvider.evaluate(
          CicdIntegrationOperationalFixtures.partialRequest(),
        );

        expect(result.snapshot!.pipelineDefinition, isNotNull);
        expect(result.snapshot!.deploymentPlan, isNull);
        expect(result.snapshot!.status, CicdIntegrationSnapshotStatus.partial);
      });

      test('failed execution is reflected in snapshot', () async {
        final result = await cicdProvider.evaluate(
          CicdIntegrationOperationalFixtures.failedExecutionRequest(),
        );

        expect(
          result.snapshot!.pipelineExecution!.status,
          PipelineStatus.failed,
        );
      });

      test('missing definition by id adds limitation', () async {
        final fakeEvidence = FakeReleaseEvidenceProviderForCicd();
        final fakeSupplyChain = FakeReleaseSupplyChainProviderForCicd();
        final provider = PlatformCicdIntegrationProvider(
          sourceResolver: CicdIntegrationSourceResolver(
            releaseEvidenceProvider: fakeEvidence,
            releaseSupplyChainProvider: fakeSupplyChain,
            pipelineIntegrationPolicyRegistry:
                PipelineIntegrationPolicyRegistry()
                  ..register(PipelineIntegrationPolicyV1.create())
                  ..freeze(),
            pipelineExecutionPolicyRegistry: PipelineExecutionPolicyRegistry()
              ..register(PipelineExecutionPolicyV1.create())
              ..freeze(),
            deploymentIntegrationPolicyRegistry:
                DeploymentIntegrationPolicyRegistry()
                  ..register(DeploymentIntegrationPolicyV1.create())
                  ..freeze(),
          ),
          pipelineIntegrationPolicyRegistry: PipelineIntegrationPolicyRegistry()
            ..register(PipelineIntegrationPolicyV1.create())
            ..freeze(),
          pipelineExecutionPolicyRegistry: PipelineExecutionPolicyRegistry()
            ..register(PipelineExecutionPolicyV1.create())
            ..freeze(),
          deploymentIntegrationPolicyRegistry:
              DeploymentIntegrationPolicyRegistry()
                ..register(DeploymentIntegrationPolicyV1.create())
                ..freeze(),
          store: InMemoryCicdIntegrationStore(),
        );

        final result = await provider.evaluate(
          CicdIntegrationOperationalFixtures.missingDefinitionRequest(),
        );

        expect(result.limitations, isNotEmpty);
        expect(fakeEvidence.evaluateCalls, 0);
        expect(fakeSupplyChain.evaluateCalls, 0);
      });

      test('projectId mismatch on evidence adds limitation', () async {
        final result = await cicdProvider.evaluate(
          CicdIntegrationOperationalFixtures.projectIdMismatchRequest(),
        );

        expect(
          result.limitations
              .any((l) => l.limitationId == 'project-mismatch-evidence'),
          isTrue,
        );
      });

      test('releaseId mismatch on supply chain is preserved in metadata',
          () async {
        final mismatched =
            CicdIntegrationOperationalFixtures.supplyChainWithReleaseId(
                'rel-other');
        final result = await cicdProvider.evaluate(
          CicdIntegrationOperationalFixtures.passingRequest(
            releaseSupplyChainSnapshot: mismatched,
          ),
        );

        expect(
          result.snapshot!.metadata.releaseSupplyChainSnapshotId,
          mismatched.metadata.supplyChainSnapshotId,
        );
        expect(result.snapshot!.metadata.releaseId,
            CicdIntegrationOperationalFixtures.releaseId);
      });

      test('wrong definition ref adds execution-definition limitation',
          () async {
        final result = await cicdProvider.evaluate(
          CicdIntegrationOperationalFixtures.wrongDefinitionRefRequest(),
        );

        expect(
          result.limitations.any(
            (l) => l.limitationId == 'execution-definition-mismatch',
          ),
          isTrue,
        );
      });

      test('missing fingerprint fails publish validation', () async {
        final result = await cicdProvider.evaluate(
          CicdIntegrationOperationalFixtures.passingRequest(),
        );
        final tampered = result.snapshot!.copyWith(
          fingerprint: '',
          metadata: result.snapshot!.metadata.copyWith(fingerprint: ''),
        );

        final publishResult = await cicdProvider.evaluateAndPublish(
          CicdIntegrationOperationalFixtures.passingRequest(),
        );
        final tamperedPublish = await cicdProvider.evaluateAndPublish(
          CicdIntegrationOperationalFixtures.passingRequest().copyWith(
            requestId: 'tampered-fp-req',
          ),
        );

        expect(publishResult.publicationStatus,
            CicdIntegrationPublicationStatus.published);
        expect(tamperedPublish.snapshot!.fingerprint, isNotEmpty);
        expect(tampered.fingerprint, isEmpty);

        final validation = const CicdIntegrationSnapshotValidator().validate(
          tampered,
        );
        expect(validation.isValid, isFalse);
        expect(validation.errors, contains('fingerprint is required'));
      });

      test('repeated evaluate and publish is idempotent', () async {
        final (evidence, supplyChain) = await buildUpstreamArtifacts();
        final request = CicdIntegrationOperationalFixtures.passingRequest(
          releaseEvidenceBundle: evidence,
          releaseSupplyChainSnapshot: supplyChain,
        );

        final first = await cicdProvider.evaluateAndPublish(request);
        final second = await cicdProvider.evaluateAndPublish(request);
        final third = await cicdProvider.evaluate(request);

        expect(first.publicationStatus,
            CicdIntegrationPublicationStatus.published);
        expect(
            second.publicationStatus, CicdIntegrationPublicationStatus.skipped);
        expect(
          third.snapshot!.metadata.cicdIntegrationSnapshotId,
          first.snapshot!.metadata.cicdIntegrationSnapshotId,
        );
      });

      test('store conflict on divergent snapshot with same id', () async {
        final store = InMemoryCicdIntegrationStore();
        final snapshot = (await cicdProvider.evaluate(
          CicdIntegrationOperationalFixtures.passingRequest(),
        ))
            .snapshot!;
        await store.save(snapshot);

        final conflicting = snapshot.copyWith(
          metadata: snapshot.metadata.copyWith(
            cicdIntegrationSnapshotId:
                snapshot.metadata.cicdIntegrationSnapshotId,
            pipelineIntegrationPolicyVersion: 99,
          ),
        );

        await expectLater(
          store.save(conflicting),
          throwsA(isA<CicdIntegrationSnapshotConflictException>()),
        );
      });

      test('fake upstream providers never called during injected resolve',
          () async {
        final fakeEvidence = FakeReleaseEvidenceProviderForCicd();
        final fakeSupplyChain = FakeReleaseSupplyChainProviderForCicd();
        final resolver = CicdIntegrationSourceResolver(
          releaseEvidenceProvider: fakeEvidence,
          releaseSupplyChainProvider: fakeSupplyChain,
          pipelineIntegrationPolicyRegistry: PipelineIntegrationPolicyRegistry()
            ..register(PipelineIntegrationPolicyV1.create())
            ..freeze(),
          pipelineExecutionPolicyRegistry: PipelineExecutionPolicyRegistry()
            ..register(PipelineExecutionPolicyV1.create())
            ..freeze(),
          deploymentIntegrationPolicyRegistry:
              DeploymentIntegrationPolicyRegistry()
                ..register(DeploymentIntegrationPolicyV1.create())
                ..freeze(),
        );

        await resolver.resolveAll(
          CicdIntegrationOperationalFixtures.passingRequest(),
          injectedPipelineIntegrationPolicy:
              PipelineIntegrationPolicyV1.create(),
          injectedPipelineExecutionPolicy: PipelineExecutionPolicyV1.create(),
          injectedDeploymentIntegrationPolicy:
              DeploymentIntegrationPolicyV1.create(),
        );

        expect(fakeEvidence.evaluateCalls, 0);
        expect(fakeEvidence.evaluateAndPublishCalls, 0);
        expect(fakeEvidence.publishCalls, 0);
        expect(fakeSupplyChain.evaluateCalls, 0);
        expect(fakeSupplyChain.evaluateAndPublishCalls, 0);
        expect(fakeSupplyChain.publishCalls, 0);
      });
    });
  });
}
