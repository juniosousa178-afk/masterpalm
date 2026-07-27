import 'package:masterpalm_platform/interfaces/dashboard_provider.dart';
import 'package:masterpalm_platform/interfaces/mes_provider.dart';
import 'package:masterpalm_platform/interfaces/metrics_provider.dart';
import 'package:masterpalm_platform/interfaces/observability_provider.dart';
import 'package:masterpalm_platform/interfaces/score_provider.dart';
import 'package:masterpalm_platform/models/dashboard/dashboard_enums.dart';
import 'package:masterpalm_platform/models/dashboard/dashboard_request.dart';
import 'package:masterpalm_platform/models/dashboard/dashboard_snapshot.dart';
import 'package:masterpalm_platform/models/mes/mes_policy.dart';
import 'package:masterpalm_platform/models/mes/mes_request.dart';
import 'package:masterpalm_platform/models/mes/mes_snapshot.dart';
import 'package:masterpalm_platform/models/metrics/metrics_request.dart';
import 'package:masterpalm_platform/models/metrics/metrics_snapshot.dart';
import 'package:masterpalm_platform/models/observability/telemetry_event.dart';
import 'package:masterpalm_platform/models/observability/telemetry_request.dart';
import 'package:masterpalm_platform/models/observability/telemetry_snapshot.dart';
import 'package:masterpalm_platform/models/score/score_policy.dart';
import 'package:masterpalm_platform/models/score/score_request.dart';
import 'package:masterpalm_platform/models/score/score_snapshot.dart';

/// Thrown when a fake provider detects an origin engine invocation.
class OriginEngineInvocationError implements Exception {
  OriginEngineInvocationError(this.provider, this.method);

  final String provider;
  final String method;

  @override
  String toString() => 'Origin engine must not be invoked: $provider.$method';
}

class FakeMetricsProvider implements MetricsProvider {
  FakeMetricsProvider({
    this.loaded,
    this.throwOnLoad = false,
    this.recoverableLoadError = false,
  });

  MetricsSnapshot? loaded;
  bool throwOnLoad;
  bool recoverableLoadError;
  int loadCalls = 0;
  int calculateCalls = 0;

  @override
  Future<MetricsResult> calculate(MetricsRequest request) async {
    calculateCalls++;
    throw OriginEngineInvocationError('MetricsProvider', 'calculate');
  }

  @override
  Future<MetricsSnapshot?> load() async {
    loadCalls++;
    if (throwOnLoad) {
      if (recoverableLoadError) {
        throw StateError('recoverable metrics load failure');
      }
      throw OriginEngineInvocationError('MetricsProvider', 'load');
    }
    return loaded;
  }

  @override
  Future<void> publish(MetricsSnapshot snapshot) async {}

  @override
  Future<void> invalidate() async {}

  @override
  Set<String> get supportedMetricIds => const {};
}

class FakeScoreProvider implements ScoreProvider {
  FakeScoreProvider({
    this.byId = const {},
    this.latestSnapshot,
    this.throwOnLoad = false,
  });

  final Map<String, EngineeringScoreSnapshot> byId;
  EngineeringScoreSnapshot? latestSnapshot;
  bool throwOnLoad;
  int calculateCalls = 0;
  int loadCalls = 0;
  int latestCalls = 0;

  @override
  Future<ScoreResult> calculate(ScoreRequest request) async {
    calculateCalls++;
    throw OriginEngineInvocationError('ScoreProvider', 'calculate');
  }

  @override
  Future<void> publish(EngineeringScoreSnapshot snapshot) async {}

  @override
  Future<EngineeringScoreSnapshot?> load({required String snapshotId}) async {
    loadCalls++;
    if (throwOnLoad) {
      throw StateError('score load failure');
    }
    return byId[snapshotId];
  }

  @override
  Future<EngineeringScoreSnapshot?> latest({
    required String projectId,
    String? policyId,
  }) async {
    latestCalls++;
    return latestSnapshot;
  }

  @override
  Future<void> invalidate(String snapshotId) async {}

  @override
  Set<String> get supportedPolicyIds => const {};

  @override
  ScorePolicy? getPolicy(String policyId) => null;
}

class FakeMESProvider implements MESProvider {
  FakeMESProvider({
    this.byId = const {},
    this.latestSnapshot,
  });

  final Map<String, MESSnapshot> byId;
  MESSnapshot? latestSnapshot;
  int calculateCalls = 0;

  @override
  Future<MESResult> calculate(MESRequest request) async {
    calculateCalls++;
    throw OriginEngineInvocationError('MESProvider', 'calculate');
  }

  @override
  Future<void> publish(MESSnapshot snapshot) async {}

  @override
  Future<MESSnapshot?> load(String snapshotId) async => byId[snapshotId];

  @override
  Future<MESSnapshot?> latest({
    required String projectId,
    int? policyVersion,
  }) async =>
      latestSnapshot;

  @override
  Future<MESEligibility> checkEligibility(MESRequest request) async {
    throw OriginEngineInvocationError('MESProvider', 'checkEligibility');
  }

  @override
  Future<void> invalidate(String snapshotId) async {}

  @override
  Set<String> get supportedPolicyIds => const {};

  @override
  MESPolicy? getPolicy(String policyId, {int? policyVersion}) => null;

  @override
  MESPolicy? getCandidatePolicy() => null;

  @override
  MESPolicy? getActivePolicy() => null;
}

class FakeObservabilityProvider implements ObservabilityProvider {
  FakeObservabilityProvider({
    this.byId = const {},
    this.latestSnapshot,
    this.enabled = true,
  });

  final Map<String, TelemetrySnapshot> byId;
  TelemetrySnapshot? latestSnapshot;
  bool enabled;
  int captureCalls = 0;

  @override
  Future<TelemetrySnapshotResult> capture(
    TelemetrySnapshotRequest request,
  ) async {
    captureCalls++;
    throw OriginEngineInvocationError('ObservabilityProvider', 'capture');
  }

  @override
  Future<void> emit(TelemetryEvent event) async {}

  @override
  Future<void> publish(TelemetrySnapshot snapshot) async {}

  @override
  Future<TelemetrySnapshot?> load(String snapshotId) async => byId[snapshotId];

  @override
  Future<TelemetrySnapshot?> latest({
    String? projectId,
    String? correlationId,
  }) async =>
      latestSnapshot;

  @override
  Future<List<TelemetrySnapshot>> query(TelemetryQuery query) async => const [];

  @override
  Future<List<TelemetryEvent>> queryEvents(TelemetryEventQuery query) async =>
      const [];

  @override
  Future<void> invalidate(String snapshotId) async {}

  @override
  bool get isEnabled => enabled;
}

class FakeDashboardProvider implements DashboardProvider {
  FakeDashboardProvider({
    this.byId = const {},
    this.latestSnapshot,
  });

  final Map<String, DashboardSnapshot> byId;
  DashboardSnapshot? latestSnapshot;
  int buildCalls = 0;

  @override
  Future<DashboardResult> build(DashboardRequest request) async {
    buildCalls++;
    throw OriginEngineInvocationError('DashboardProvider', 'build');
  }

  @override
  Future<void> publish(DashboardSnapshot snapshot) async {}

  @override
  Future<DashboardSnapshot?> load(String snapshotId) async => byId[snapshotId];

  @override
  Future<DashboardSnapshot?> latest({
    required String projectId,
    String? branch,
  }) async =>
      latestSnapshot;

  @override
  Future<List<DashboardSnapshot>> query(DashboardQuery query) async => const [];

  @override
  Future<void> invalidate(String snapshotId) async {}

  @override
  Set<DashboardSectionType> get supportedSections =>
      DashboardSectionType.values.toSet();
}
