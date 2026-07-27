import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/models/observability/telemetry_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_query.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_request.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_result.dart';
import 'package:masterpalm_platform/observability/clocks/system_platform_clock.dart';
import 'package:masterpalm_platform/observability/instrumentation/observable_release_evidence_provider.dart';
import 'package:masterpalm_platform/observability/instrumentation/telemetry_instrumentation.dart';
import 'package:masterpalm_platform/observability/observability_collector.dart';
import 'package:masterpalm_platform/observability/sinks/in_memory_telemetry_event_sink.dart';
import 'package:masterpalm_platform/observability/telemetry_timer.dart';
import 'package:test/test.dart';

import 'support/release_evidence_test_fixtures.dart';

class _RecordingDelegate implements ReleaseEvidenceProvider {
  int evaluateCalls = 0;
  ReleaseEvidenceResult result = ReleaseEvidenceTestFixtures.validResult();

  @override
  Future<ReleaseEvidenceResult> evaluate(ReleaseEvidenceRequest request) async {
    evaluateCalls++;
    return result;
  }

  @override
  Future<ReleaseEvidenceResult> evaluateAndPublish(
    ReleaseEvidenceRequest request,
  ) =>
      evaluate(request);

  @override
  Future<void> publish(ReleaseEvidenceBundle bundle) async {}

  @override
  Future<ReleaseEvidenceBundle?> load(String bundleId) async => result.bundle;

  @override
  Future<ReleaseEvidenceBundle?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async =>
      result.bundle;

  @override
  Future<List<ReleaseEvidenceBundle>> query(ReleaseEvidenceQuery query) async =>
      result.bundle == null ? const [] : [result.bundle!];

  @override
  Future<void> invalidate(String bundleId) async {}
}

void main() {
  group('Release Evidence observability audit', () {
    late _RecordingDelegate delegate;
    late InMemoryTelemetryEventSink sink;
    late ObservableReleaseEvidenceProvider observable;

    setUp(() {
      delegate = _RecordingDelegate();
      sink = InMemoryTelemetryEventSink();
      observable = ObservableReleaseEvidenceProvider(
        delegate: delegate,
        instrumentation: TelemetryInstrumentation(
          collector: ObservabilityCollector(sink: sink),
          clock: SystemPlatformClock(),
          timerFactory: const DefaultTelemetryTimerFactory(),
        ),
      );
    });

    Future<void> exerciseAll() async {
      final request = ReleaseEvidenceTestFixtures.passingRequest();
      await observable.evaluate(request);
      await observable.evaluateAndPublish(request);
      final bundle = delegate.result.bundle!;
      await observable.publish(bundle);
      await observable.load(bundle.metadata.bundleId);
      await observable.latest(projectId: bundle.metadata.projectId);
      await observable
          .query(ReleaseEvidenceQuery(projectId: bundle.metadata.projectId));
      await observable.invalidate(bundle.metadata.bundleId);
    }

    test('all operations emit releaseEvidence telemetry', () async {
      await exerciseAll();
      final ops = sink.events
          .where((e) => e.component == TelemetryComponent.releaseEvidence)
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
        ReleaseEvidenceTestFixtures.passingRequest(),
      );
      final wrapped = await observable.evaluate(
        ReleaseEvidenceTestFixtures.passingRequest(),
      );
      expect(wrapped.bundle?.fingerprint, direct.bundle?.fingerprint);
      expect(wrapped.status, direct.status);
    });

    test('events include duration timing', () async {
      await observable.evaluate(ReleaseEvidenceTestFixtures.passingRequest());
      expect(
        sink.events.any(
          (e) =>
              e.component == TelemetryComponent.releaseEvidence &&
              e.duration != null,
        ),
        isTrue,
      );
    });
  });
}
