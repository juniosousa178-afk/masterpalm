import 'package:masterpalm_platform/interfaces/release_supply_chain_provider.dart';
import 'package:masterpalm_platform/models/observability/telemetry_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_operational_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_query.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_request.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_result.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_snapshot.dart';
import 'package:masterpalm_platform/observability/clocks/system_platform_clock.dart';
import 'package:masterpalm_platform/observability/instrumentation/observable_release_supply_chain_provider.dart';
import 'package:masterpalm_platform/observability/instrumentation/telemetry_instrumentation.dart';
import 'package:masterpalm_platform/observability/observability_collector.dart';
import 'package:masterpalm_platform/observability/sinks/in_memory_telemetry_event_sink.dart';
import 'package:masterpalm_platform/observability/telemetry_timer.dart';
import 'package:test/test.dart';

import 'support/release_supply_chain_test_fixtures.dart';

class _RecordingDelegate implements ReleaseSupplyChainProvider {
  int evaluateCalls = 0;
  ReleaseSupplyChainResult result = ReleaseSupplyChainResult(
    status: ReleaseSupplyChainResultStatus.success,
    snapshot: ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot(),
  );

  @override
  Future<ReleaseSupplyChainResult> evaluate(
    ReleaseSupplyChainRequest request,
  ) async {
    evaluateCalls++;
    return result;
  }

  @override
  Future<ReleaseSupplyChainResult> evaluateAndPublish(
    ReleaseSupplyChainRequest request,
  ) =>
      evaluate(request);

  @override
  Future<void> publish(ReleaseSupplyChainSnapshot snapshot) async {}

  @override
  Future<ReleaseSupplyChainSnapshot?> load(String snapshotId) async =>
      result.snapshot;

  @override
  Future<ReleaseSupplyChainSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? supplyChainPolicyId,
  }) async =>
      result.snapshot;

  @override
  Future<List<ReleaseSupplyChainSnapshot>> query(
    ReleaseSupplyChainQuery query,
  ) async =>
      result.snapshot == null ? const [] : [result.snapshot!];

  @override
  Future<void> invalidate(String snapshotId) async {}
}

void main() {
  group('Release Supply Chain observability audit', () {
    late _RecordingDelegate delegate;
    late InMemoryTelemetryEventSink sink;
    late ObservableReleaseSupplyChainProvider observable;

    setUp(() {
      delegate = _RecordingDelegate();
      sink = InMemoryTelemetryEventSink();
      observable = ObservableReleaseSupplyChainProvider(
        delegate: delegate,
        instrumentation: TelemetryInstrumentation(
          collector: ObservabilityCollector(sink: sink),
          clock: SystemPlatformClock(),
          timerFactory: const DefaultTelemetryTimerFactory(),
        ),
      );
    });

    Future<void> exerciseAll() async {
      final request = ReleaseSupplyChainTestFixtures.passingRequest();
      await observable.evaluate(request);
      await observable.evaluateAndPublish(request);
      final snapshot = delegate.result.snapshot!;
      await observable.publish(snapshot);
      await observable.load(snapshot.metadata.supplyChainSnapshotId);
      await observable.latest(projectId: snapshot.metadata.projectId);
      await observable.query(
        ReleaseSupplyChainQuery(projectId: snapshot.metadata.projectId),
      );
      await observable.invalidate(snapshot.metadata.supplyChainSnapshotId);
    }

    test('all operations emit releaseSupplyChain telemetry', () async {
      await exerciseAll();
      final ops = sink.events
          .where((e) => e.component == TelemetryComponent.releaseSupplyChain)
          .map((e) => e.operation)
          .toSet();
      expect(ops, contains(TelemetryOperation.evaluate));
      expect(ops, contains(TelemetryOperation.publish));
      expect(ops, contains(TelemetryOperation.load));
      expect(ops, contains(TelemetryOperation.latest));
      expect(ops, contains(TelemetryOperation.query));
      expect(ops, contains(TelemetryOperation.invalidate));
    });

    test('observability does not change evaluate result payload', () async {
      final direct = await delegate.evaluate(
        ReleaseSupplyChainTestFixtures.passingRequest(),
      );
      final wrapped = await observable.evaluate(
        ReleaseSupplyChainTestFixtures.passingRequest(),
      );
      expect(wrapped.snapshot?.fingerprint, direct.snapshot?.fingerprint);
      expect(wrapped.status, direct.status);
    });

    test('events include duration timing', () async {
      await observable
          .evaluate(ReleaseSupplyChainTestFixtures.passingRequest());
      expect(
        sink.events.any(
          (e) =>
              e.component == TelemetryComponent.releaseSupplyChain &&
              e.duration != null,
        ),
        isTrue,
      );
    });
  });
}
