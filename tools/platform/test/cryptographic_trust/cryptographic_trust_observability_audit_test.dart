import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_query.dart';
import 'package:masterpalm_platform/models/observability/telemetry_enums.dart';
import 'package:masterpalm_platform/observability/clocks/system_platform_clock.dart';
import 'package:masterpalm_platform/observability/instrumentation/observable_cryptographic_trust_provider.dart';
import 'package:masterpalm_platform/observability/instrumentation/telemetry_instrumentation.dart';
import 'package:masterpalm_platform/observability/observability_collector.dart';
import 'package:masterpalm_platform/observability/sinks/in_memory_telemetry_event_sink.dart';
import 'package:masterpalm_platform/observability/telemetry_timer.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';

void main() {
  group('Cryptographic Trust observability audit', () {
    late CryptographicTrustTestStack stack;
    late InMemoryTelemetryEventSink sink;
    late ObservableCryptographicTrustProvider observable;

    setUp(() async {
      stack = CryptographicTrustOperationalFixtures.createTestStack();
      await stack.registerTestKeys();
      sink = InMemoryTelemetryEventSink();
      observable = ObservableCryptographicTrustProvider(
        delegate: stack.provider,
        instrumentation: TelemetryInstrumentation(
          collector: ObservabilityCollector(sink: sink),
          clock: SystemPlatformClock(),
          timerFactory: const DefaultTelemetryTimerFactory(),
        ),
      );
    });

    Future<void> exerciseAll() async {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest();
      await observable.evaluate(request);
      final published = await observable.evaluateAndPublish(request);
      final snapshot = published.snapshot!;
      await observable.publish(snapshot);
      await observable.load(snapshot.metadata.cryptographicTrustSnapshotId);
      await observable.latest(projectId: snapshot.metadata.projectId);
      await observable.query(
        CryptographicTrustQuery(projectId: snapshot.metadata.projectId),
      );
      await observable
          .invalidate(snapshot.metadata.cryptographicTrustSnapshotId);
    }

    test('all operations emit cryptographicTrust telemetry', () async {
      await exerciseAll();
      final ops = sink.events
          .where((e) => e.component == TelemetryComponent.cryptographicTrust)
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
      final request = CryptographicTrustOperationalFixtures.evaluationRequest();
      final direct = await stack.provider.evaluate(request);
      final wrapped = await observable.evaluate(request);
      expect(wrapped.snapshot?.fingerprint, direct.snapshot?.fingerprint);
      expect(wrapped.status, direct.status);
    });

    test('events include duration timing', () async {
      await observable.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(
        sink.events.any(
          (e) =>
              e.component == TelemetryComponent.cryptographicTrust &&
              e.duration != null,
        ),
        isTrue,
      );
    });
  });
}
