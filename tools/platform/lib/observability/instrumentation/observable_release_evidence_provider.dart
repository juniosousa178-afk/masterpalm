import '../../interfaces/release_evidence_provider.dart';
import '../../models/observability/telemetry_enums.dart';
import '../../models/release_evidence/release_evidence_bundle.dart';
import '../../models/release_evidence/release_evidence_query.dart';
import '../../models/release_evidence/release_evidence_request.dart';
import '../../models/release_evidence/release_evidence_result.dart';
import 'telemetry_instrumentation.dart';

/// Observable decorator for [ReleaseEvidenceProvider].
class ObservableReleaseEvidenceProvider implements ReleaseEvidenceProvider {
  ObservableReleaseEvidenceProvider({
    required ReleaseEvidenceProvider delegate,
    required TelemetryInstrumentation instrumentation,
  })  : _delegate = delegate,
        _instrumentation = instrumentation;

  final ReleaseEvidenceProvider _delegate;
  final TelemetryInstrumentation _instrumentation;

  @override
  Future<ReleaseEvidenceResult> evaluate(ReleaseEvidenceRequest request) {
    return _instrumentation.observe(
      component: TelemetryComponent.releaseEvidence,
      operation: TelemetryOperation.evaluate,
      projectId: request.releaseContext.projectId,
      action: () => _delegate.evaluate(request),
      resultingArtifactIds: (result) {
        final id = result.bundle?.metadata.bundleId;
        return id == null ? const [] : [id];
      },
    );
  }

  @override
  Future<ReleaseEvidenceResult> evaluateAndPublish(
    ReleaseEvidenceRequest request,
  ) {
    return _instrumentation.observe(
      component: TelemetryComponent.releaseEvidence,
      operation: TelemetryOperation.evaluate,
      projectId: request.releaseContext.projectId,
      action: () => _delegate.evaluateAndPublish(request),
      resultingArtifactIds: (result) {
        final id = result.bundle?.metadata.bundleId;
        return id == null ? const [] : [id];
      },
    );
  }

  @override
  Future<void> publish(ReleaseEvidenceBundle bundle) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.releaseEvidence,
      operation: TelemetryOperation.publish,
      projectId: bundle.metadata.projectId,
      action: () => _delegate.publish(bundle),
    );
  }

  @override
  Future<ReleaseEvidenceBundle?> load(String bundleId) {
    return _instrumentation.observe(
      component: TelemetryComponent.releaseEvidence,
      operation: TelemetryOperation.load,
      action: () => _delegate.load(bundleId),
      resultingArtifactIds: (bundle) {
        return bundle == null ? const [] : [bundle.metadata.bundleId];
      },
    );
  }

  @override
  Future<ReleaseEvidenceBundle?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) {
    return _instrumentation.observe(
      component: TelemetryComponent.releaseEvidence,
      operation: TelemetryOperation.latest,
      projectId: projectId,
      action: () => _delegate.latest(
        projectId: projectId,
        releaseId: releaseId,
        policyId: policyId,
      ),
      resultingArtifactIds: (bundle) {
        return bundle == null ? const [] : [bundle.metadata.bundleId];
      },
    );
  }

  @override
  Future<List<ReleaseEvidenceBundle>> query(ReleaseEvidenceQuery query) {
    return _instrumentation.observe(
      component: TelemetryComponent.releaseEvidence,
      operation: TelemetryOperation.query,
      projectId: query.projectId,
      action: () => _delegate.query(query),
    );
  }

  @override
  Future<void> invalidate(String bundleId) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.releaseEvidence,
      operation: TelemetryOperation.invalidate,
      action: () => _delegate.invalidate(bundleId),
    );
  }
}
