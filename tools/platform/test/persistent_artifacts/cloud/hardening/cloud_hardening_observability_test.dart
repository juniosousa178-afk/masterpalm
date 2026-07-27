import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/observability/clocks/system_platform_clock.dart';
import 'package:masterpalm_platform/observability/instrumentation/observable_persistent_artifact_provider.dart';
import 'package:masterpalm_platform/observability/instrumentation/telemetry_instrumentation.dart';
import 'package:masterpalm_platform/observability/observability_collector.dart';
import 'package:masterpalm_platform/observability/sinks/in_memory_telemetry_event_sink.dart';
import 'package:masterpalm_platform/observability/telemetry_timer.dart';
import 'package:test/test.dart';

import '../../support/persistent_artifact_operational_fixtures.dart';
import '../../../support/persistent_artifact_offline_cloud_reference_composition.dart';
import 'support/cloud_hardening_helpers.dart';

void main() {
  group('CloudHardeningObservability', () {
    test('provider e observable provider produzem mesmo status', () async {
      final runtime =
          const PersistentArtifactOfflineCloudReferenceComposition().create();
      addTearDown(runtime.dispose);
      final request = CloudHardeningHelpers.putRequest(
        backendId: runtime.backendId,
      );
      final direct = await runtime.provider.putCloudObject(request);
      final sink = InMemoryTelemetryEventSink();
      final observable = ObservablePersistentArtifactProvider(
        delegate: runtime.provider,
        instrumentation: TelemetryInstrumentation(
          collector: ObservabilityCollector(sink: sink),
          clock: SystemPlatformClock(),
          timerFactory: const DefaultTelemetryTimerFactory(),
        ),
      );
      final observed = await observable.putCloudObject(
        request.copyWith(requestId: 'observable-put-2'),
      );
      expect(observed.status, direct.status);
      expect(observed.correlationId, isNotEmpty);
      expect(observed.metadata.containsKey('stackTrace'), isFalse);
    });
  });

  group('CloudHardeningIoGuard', () {
    test('evaluate não executa cloud I/O', () async {
      final runtime =
          const PersistentArtifactOfflineCloudReferenceComposition().create();
      addTearDown(runtime.dispose);
      final before = runtime.bridge.operationCounters.values.fold<int>(
        0,
        (sum, value) => sum + value,
      );
      await runtime.provider.evaluate(fixtureEvaluationRequest());
      final after = runtime.bridge.operationCounters.values.fold<int>(
        0,
        (sum, value) => sum + value,
      );
      expect(after, before);
    });

    test('lib cloud sem dart:io', () {
      final dir = Directory('lib/persistent_artifacts/cloud');
      for (final file in dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        expect(file.readAsStringSync().contains('dart:io'), isFalse);
      }
    });
  });
}
