import '../../interfaces/release_supply_chain_provider.dart';
import '../../models/observability/telemetry_enums.dart';
import '../../models/release_supply_chain/release_supply_chain_query.dart';
import '../../models/release_supply_chain/release_supply_chain_request.dart';
import '../../models/release_supply_chain/release_supply_chain_result.dart';
import '../../models/release_supply_chain/release_supply_chain_snapshot.dart';
import 'telemetry_instrumentation.dart';

/// Observable decorator for [ReleaseSupplyChainProvider].
class ObservableReleaseSupplyChainProvider
    implements ReleaseSupplyChainProvider {
  ObservableReleaseSupplyChainProvider({
    required ReleaseSupplyChainProvider delegate,
    required TelemetryInstrumentation instrumentation,
  })  : _delegate = delegate,
        _instrumentation = instrumentation;

  final ReleaseSupplyChainProvider _delegate;
  final TelemetryInstrumentation _instrumentation;

  @override
  Future<ReleaseSupplyChainResult> evaluate(ReleaseSupplyChainRequest request) {
    return _instrumentation.observe(
      component: TelemetryComponent.releaseSupplyChain,
      operation: TelemetryOperation.evaluate,
      projectId: request.releaseContext.projectId,
      action: () => _delegate.evaluate(request),
      resultingArtifactIds: (result) {
        final id = result.snapshot?.metadata.supplyChainSnapshotId;
        return id == null ? const [] : [id];
      },
    );
  }

  @override
  Future<ReleaseSupplyChainResult> evaluateAndPublish(
    ReleaseSupplyChainRequest request,
  ) {
    return _instrumentation.observe(
      component: TelemetryComponent.releaseSupplyChain,
      operation: TelemetryOperation.evaluate,
      projectId: request.releaseContext.projectId,
      action: () => _delegate.evaluateAndPublish(request),
      resultingArtifactIds: (result) {
        final id = result.snapshot?.metadata.supplyChainSnapshotId;
        return id == null ? const [] : [id];
      },
    );
  }

  @override
  Future<void> publish(ReleaseSupplyChainSnapshot snapshot) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.releaseSupplyChain,
      operation: TelemetryOperation.publish,
      projectId: snapshot.metadata.projectId,
      action: () => _delegate.publish(snapshot),
    );
  }

  @override
  Future<ReleaseSupplyChainSnapshot?> load(String snapshotId) {
    return _instrumentation.observe(
      component: TelemetryComponent.releaseSupplyChain,
      operation: TelemetryOperation.load,
      action: () => _delegate.load(snapshotId),
      resultingArtifactIds: (snapshot) {
        return snapshot == null
            ? const []
            : [snapshot.metadata.supplyChainSnapshotId];
      },
    );
  }

  @override
  Future<ReleaseSupplyChainSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? supplyChainPolicyId,
  }) {
    return _instrumentation.observe(
      component: TelemetryComponent.releaseSupplyChain,
      operation: TelemetryOperation.latest,
      projectId: projectId,
      action: () => _delegate.latest(
        projectId: projectId,
        releaseId: releaseId,
        supplyChainPolicyId: supplyChainPolicyId,
      ),
      resultingArtifactIds: (snapshot) {
        return snapshot == null
            ? const []
            : [snapshot.metadata.supplyChainSnapshotId];
      },
    );
  }

  @override
  Future<List<ReleaseSupplyChainSnapshot>> query(
    ReleaseSupplyChainQuery query,
  ) {
    return _instrumentation.observe(
      component: TelemetryComponent.releaseSupplyChain,
      operation: TelemetryOperation.query,
      projectId: query.projectId,
      action: () => _delegate.query(query),
    );
  }

  @override
  Future<void> invalidate(String snapshotId) {
    return _instrumentation.observeVoid(
      component: TelemetryComponent.releaseSupplyChain,
      operation: TelemetryOperation.invalidate,
      action: () => _delegate.invalidate(snapshotId),
    );
  }
}
