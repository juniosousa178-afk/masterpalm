import 'package:masterpalm_platform/interfaces/cicd_integration_provider.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_query.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_request.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_result.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_snapshot.dart';
import 'package:masterpalm_platform/models/observability/telemetry_enums.dart';
import 'package:masterpalm_platform/observability/clocks/system_platform_clock.dart';
import 'package:masterpalm_platform/observability/instrumentation/observable_cicd_integration_provider.dart';
import 'package:masterpalm_platform/observability/instrumentation/telemetry_instrumentation.dart';
import 'package:masterpalm_platform/observability/observability_collector.dart';
import 'package:masterpalm_platform/observability/sinks/in_memory_telemetry_event_sink.dart';
import 'package:masterpalm_platform/observability/telemetry_timer.dart';
import 'package:test/test.dart';

import 'support/cicd_integration_hardening_helpers.dart';
import 'support/cicd_integration_operational_fixtures.dart';

class _RecordingDelegate implements CicdIntegrationProvider {
  int evaluateCalls = 0;
  CicdIntegrationResult? result;

  @override
  Future<CicdIntegrationResult> evaluate(
    CicdIntegrationRequest request,
  ) async {
    evaluateCalls++;
    result ??= await evaluatePassingSnapshot();
    return result!;
  }

  @override
  Future<CicdIntegrationResult> evaluateAndPublish(
    CicdIntegrationRequest request,
  ) =>
      evaluate(request);

  @override
  Future<void> publish(CicdIntegrationSnapshot snapshot) async {}

  @override
  Future<CicdIntegrationSnapshot?> load(String snapshotId) async =>
      result?.snapshot;

  @override
  Future<CicdIntegrationSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? pipelineIntegrationPolicyId,
  }) async =>
      result?.snapshot;

  @override
  Future<List<CicdIntegrationSnapshot>> query(
    CicdIntegrationQuery query,
  ) async =>
      result?.snapshot == null ? const [] : [result!.snapshot!];

  @override
  Future<void> invalidate(String snapshotId) async {}
}

void main() {
  group('CI/CD Integration observability audit', () {
    late _RecordingDelegate delegate;
    late InMemoryTelemetryEventSink sink;
    late ObservableCicdIntegrationProvider observable;

    setUp(() {
      delegate = _RecordingDelegate();
      sink = InMemoryTelemetryEventSink();
      observable = ObservableCicdIntegrationProvider(
        delegate: delegate,
        instrumentation: TelemetryInstrumentation(
          collector: ObservabilityCollector(sink: sink),
          clock: SystemPlatformClock(),
          timerFactory: const DefaultTelemetryTimerFactory(),
        ),
      );
    });

    Future<void> exerciseAll() async {
      final request = CicdIntegrationOperationalFixtures.passingRequest();
      await observable.evaluate(request);
      await observable.evaluateAndPublish(request);
      final snapshot = delegate.result!.snapshot!;
      await observable.publish(snapshot);
      await observable.load(snapshot.metadata.cicdIntegrationSnapshotId);
      await observable.latest(projectId: snapshot.metadata.projectId);
      await observable.query(
        CicdIntegrationQuery(projectId: snapshot.metadata.projectId),
      );
      await observable.invalidate(snapshot.metadata.cicdIntegrationSnapshotId);
    }

    test('all operations emit cicdIntegration telemetry', () async {
      await exerciseAll();
      final ops = sink.events
          .where((e) => e.component == TelemetryComponent.cicdIntegration)
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
        CicdIntegrationOperationalFixtures.passingRequest(),
      );
      final wrapped = await observable.evaluate(
        CicdIntegrationOperationalFixtures.passingRequest(),
      );
      expect(wrapped.snapshot?.fingerprint, direct.snapshot?.fingerprint);
      expect(wrapped.status, direct.status);
    });

    test('events include duration timing', () async {
      await observable.evaluate(
        CicdIntegrationOperationalFixtures.passingRequest(),
      );
      expect(
        sink.events.any(
          (e) =>
              e.component == TelemetryComponent.cicdIntegration &&
              e.duration != null,
        ),
        isTrue,
      );
    });
  });
}
