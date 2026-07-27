import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/history/mappers/persistent_artifact_history_mapper.dart';
import 'package:masterpalm_platform/report/report_composer.dart';
import 'package:masterpalm_platform/report/report_input.dart';
import 'package:test/test.dart';

void main() {
  group('PersistentArtifactIntegrations', () {
    test('ReportType inclui persistentArtifacts', () {
      expect(
          ReportType.values.contains(ReportType.persistentArtifacts), isTrue);
    });

    test('ReportComposer gera secao de persistent artifacts', () {
      final doc = const ReportComposer().compose(
        const ReportInput(
          projectId: 'p',
          reportType: ReportType.persistentArtifacts,
          persistentArtifacts: PersistentArtifactReportInputData(
            snapshotId: 's1',
            projectId: 'p',
            releaseId: 'r',
            status: 'evaluated',
            subjectCount: 1,
            sourceCount: 0,
            policyCount: 0,
            operationCount: 1,
          ),
        ),
      );
      expect(
        doc.sections.any((s) => s.id == 'persistent-artifacts-summary'),
        isTrue,
      );
    });

    test('HistoryArtifactType inclui persistentArtifacts', () {
      expect(
        HistoryArtifactType.values
            .contains(HistoryArtifactType.persistentArtifacts),
        isTrue,
      );
    });

    test('DashboardSectionType inclui persistentArtifactsSummary', () {
      expect(
        DashboardSectionType.values
            .contains(DashboardSectionType.persistentArtifactsSummary),
        isTrue,
      );
    });

    test('TelemetryComponent inclui persistentArtifacts', () {
      expect(
        TelemetryComponent.values
            .contains(TelemetryComponent.persistentArtifacts),
        isTrue,
      );
    });

    test('PlatformCore delega persistent artifact provider', () {
      final registry = ProviderRegistry()
        ..registerInstance<PersistentArtifactProvider>(
            _NoopPersistentProvider());
      final core = PlatformCore(
        config: PlatformConfig.forRepo('.'),
        registry: registry,
      );
      expect(core.persistentArtifacts(), isA<PersistentArtifactProvider>());
    });

    for (var i = 0; i < 2; i++) {
      test('integracao cenario $i', () {
        final mapper = const PersistentArtifactHistoryMapper();
        final snapshot = PersistentArtifactInfrastructureSnapshot(
          projectId: 'p',
          status: PersistentArtifactInfrastructureStatus.evaluated,
          createdAt: 't',
          metadata: {'snapshotId': 's$i', 'fingerprint': 'f$i'},
        );
        final artifact = mapper.fromMap(snapshot.toJson());
        expect(artifact.artifactType, HistoryArtifactType.persistentArtifacts);
      });
    }
  });
}

class _NoopPersistentProvider implements PersistentArtifactProvider {
  @override
  Future<PersistentArtifactCloudMultipartOperationResult> abortCloudMultipart(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<PersistentArtifactCloudMultipartOperationResult> beginCloudMultipart(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<PersistentArtifactOperationResult> buildTombstone(
    PersistentArtifactEvaluationRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<PersistentArtifactCloudObjectMetadataResult> copyCloudObject(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<PersistentArtifactCloudObjectMetadataResult> cloudObjectExists(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<PersistentArtifactCloudMultipartOperationResult>
      completeCloudMultipart(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
          throw UnimplementedError();
  @override
  Future<PersistentArtifactCloudObjectMetadataResult> deleteCloudObject(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<void> deleteContent(PersistentArtifactContentHandle handle,
      {bool force = false}) async {}
  @override
  Future<PersistentArtifactEvaluationResult> evaluate(
          PersistentArtifactEvaluationRequest request) async =>
      throw UnimplementedError();
  @override
  Future<PersistentArtifactEvaluationResult> evaluateAndPublish(
          PersistentArtifactEvaluationRequest request) async =>
      throw UnimplementedError();
  @override
  Future<PersistentArtifactOperationResult> evaluateAvailability(
          PersistentArtifactEvaluationRequest request) async =>
      throw UnimplementedError();
  @override
  Future<PersistentArtifactOperationResult> evaluateDeletion(
          PersistentArtifactEvaluationRequest request,
          {bool force = false}) async =>
      throw UnimplementedError();
  @override
  Future<PersistentArtifactOperationResult> evaluateIntegrity(
          PersistentArtifactEvaluationRequest request) async =>
      throw UnimplementedError();
  @override
  Future<PersistentArtifactOperationResult> evaluateLifecycle(
          PersistentArtifactEvaluationRequest request) async =>
      throw UnimplementedError();
  @override
  Future<PersistentArtifactOperationResult> evaluatePublication(
          PersistentArtifactEvaluationRequest request) async =>
      throw UnimplementedError();
  @override
  Future<PersistentArtifactOperationResult> evaluateReplication(
          PersistentArtifactEvaluationRequest request) async =>
      throw UnimplementedError();
  @override
  Future<PersistentArtifactOperationResult> evaluateRetention(
          PersistentArtifactEvaluationRequest request) async =>
      throw UnimplementedError();
  @override
  Future<PersistentArtifactCloudObjectMetadataResult> getCloudObject(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<PersistentArtifactCloudObjectMetadataResult> headCloudObject(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<void> invalidate(String snapshotId) async {}
  @override
  Future<PersistentArtifactInfrastructureSnapshot?> latest(
          {required String projectId, String? releaseId}) async =>
      null;
  @override
  Future<PersistentArtifactInfrastructureSnapshot?> load(
          String snapshotId) async =>
      null;
  @override
  Future<PersistentArtifactCloudObjectListResult> listCloudObjects(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<void> publish(
      PersistentArtifactInfrastructureSnapshot snapshot) async {}
  @override
  Future<List<PersistentArtifactInfrastructureSnapshot>> query(
          PersistentArtifactQuery query) async =>
      const [];
  @override
  Future<List<int>> readContent(PersistentArtifactContentHandle handle) async =>
      const [];
  @override
  Future<PersistentArtifactContentHandle> writeContent(
          {required String contentId, required List<int> bytes}) async =>
      const InMemoryPersistentArtifactContentHandle(
          handleId: 'h', backendId: 'b');
  @override
  Future<PersistentArtifactCloudObjectMetadataResult> putCloudObject(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ContentExistsResult> contentExists(
          ContentExistsRequest request) async =>
      throw UnimplementedError();

  @override
  Future<ContentMetadataResult> contentMetadata(
    ContentMetadataRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<PersistentArtifactPhysicalResult> discardTemporaryObject(
    DiscardTemporaryObjectRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<PersistentArtifactPhysicalResult> invalidatePhysicalManifest(
    InvalidatePhysicalManifestRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<RecoveryInspectionResult> inspectInterruptedOperations(
    String backendId,
  ) async =>
      throw UnimplementedError();

  @override
  Future<RecoveryInspectionResult> inspectOrphanTemporaryObjects(
    String backendId,
  ) async =>
      throw UnimplementedError();

  @override
  Future<LoadPhysicalManifestResult> latestPhysicalManifest(
    LatestPhysicalManifestRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<LoadPhysicalManifestResult> loadPhysicalManifest(
    LoadPhysicalManifestRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<QueryPhysicalManifestsResult> queryPhysicalManifests(
    QueryPhysicalManifestsRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<QuarantineContentResult> quarantineContent(
    QuarantineContentRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<PersistentArtifactPhysicalResult> recoverTemporaryObject(
    RecoverTemporaryObjectRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ReadPhysicalContentResult> readPhysicalContent(
    ReadPhysicalContentRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<ResolvePhysicalLocationResult> resolvePhysicalLocation(
    ResolvePhysicalLocationRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<SavePhysicalManifestResult> savePhysicalManifest(
    SavePhysicalManifestRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<PersistentArtifactPhysicalResult> unregisterBackend(
    UnregisterBackendRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<PersistentArtifactCloudMultipartOperationResult> uploadCloudPart(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      throw UnimplementedError();

  @override
  Future<WritePhysicalContentResult> writePhysicalContent(
    WritePhysicalContentRequest request,
  ) async =>
      throw UnimplementedError();
}
