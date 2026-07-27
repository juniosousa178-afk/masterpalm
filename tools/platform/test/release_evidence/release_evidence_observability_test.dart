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

class _StubReleaseEvidenceProvider implements ReleaseEvidenceProvider {
  int evaluateCalls = 0;

  @override
  Future<ReleaseEvidenceResult> evaluate(ReleaseEvidenceRequest request) async {
    evaluateCalls++;
    return ReleaseEvidenceTestFixtures.validResult();
  }

  @override
  Future<ReleaseEvidenceResult> evaluateAndPublish(
    ReleaseEvidenceRequest request,
  ) =>
      evaluate(request);

  @override
  Future<void> publish(ReleaseEvidenceBundle bundle) async {}

  @override
  Future<ReleaseEvidenceBundle?> load(String bundleId) async => null;

  @override
  Future<ReleaseEvidenceBundle?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async =>
      null;

  @override
  Future<List<ReleaseEvidenceBundle>> query(ReleaseEvidenceQuery query) async =>
      const [];

  @override
  Future<void> invalidate(String bundleId) async {}
}

void main() {
  test('ObservableReleaseEvidenceProvider records evaluate telemetry',
      () async {
    final stub = _StubReleaseEvidenceProvider();
    final sink = InMemoryTelemetryEventSink();
    final instrumentation = TelemetryInstrumentation(
      collector: ObservabilityCollector(sink: sink),
      clock: SystemPlatformClock(),
      timerFactory: const DefaultTelemetryTimerFactory(),
    );
    final observable = ObservableReleaseEvidenceProvider(
      delegate: stub,
      instrumentation: instrumentation,
    );

    await observable.evaluate(ReleaseEvidenceTestFixtures.passingRequest());

    expect(stub.evaluateCalls, 1);
    expect(
      sink.events.any((e) => e.component == TelemetryComponent.releaseEvidence),
      isTrue,
    );
  });
}
