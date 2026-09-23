import 'package:uuid/uuid.dart';

import '../core/client_build_identity.dart';
import '../services/loja_id_service.dart';
import 'diagnostic_anomaly_scanner.dart';
import 'diagnostic_enums.dart';
import 'diagnostic_error_classifier.dart';
import 'diagnostic_export_service.dart';
import 'diagnostic_incident.dart';
import 'diagnostic_incident_history.dart';
import 'diagnostic_result.dart';
import 'diagnostic_sanitize.dart';
import 'diagnostic_trace_service.dart';

/// Facade for the System Diagnostic Center (read-only by default).
class DiagnosticCenterService {
  DiagnosticCenterService({DiagnosticAnomalyScanner? scanner})
      : _scanner = scanner ?? DiagnosticAnomalyScanner();

  final DiagnosticAnomalyScanner _scanner;

  DiagnosticResult? lastResult;
  DateTime? lastDiagnosticAt;

  Future<String?> currentStoreId() => LojaIdService.get();

  Map<String, dynamic> buildIdentity() => clientBuildProofMap();

  Future<DiagnosticResult> runDiagnostic({String? storeId}) async {
    final result = await _scanner.scanCurrentStore(
      storeIdOverride: storeId,
      recordIncidents: true,
    );
    lastResult = result;
    lastDiagnosticAt = result.generatedAt;
    await DiagnosticIncidentHistory.ensureHydrated();
    // Persist last summary per store (local only).
    await DiagnosticIncidentHistory.record(
      DiagnosticIncident(
        incidentId: const Uuid().v4(),
        traceId: result.diagnosticId,
        storeId: result.storeId,
        timestamp: result.generatedAt,
        severity: result.health == DiagnosticHealthStatus.critical
            ? DiagnosticSeverity.critical
            : result.health == DiagnosticHealthStatus.warning
                ? DiagnosticSeverity.warning
                : DiagnosticSeverity.info,
        module: DiagnosticModule.system,
        operationType: 'diagnostic_run',
        classification: 'DIAGNOSTIC_RUN',
        rootCauseStatus: DiagnosticRootCauseStatus.classifiedNotConfirmed,
        userTitle: 'Diagnóstico executado',
        userMessage: 'Varredura somente-leitura concluída para esta loja.',
        safeNextAction: result.health == DiagnosticHealthStatus.healthy
            ? 'Nenhuma ação necessária.'
            : 'Revise os incidentes e exporte o diagnóstico se precisar de suporte.',
        metadataSanitized: {
          'SYSTEM_STATUS': result.health.wire,
          'ANOMALY_COUNT': result.anomalyCount,
          'CRITICAL_COUNT': result.criticalCount,
        },
        buildId: result.buildIdentity['CLIENT_BUILD_ID']?.toString(),
        appVersion: result.buildIdentity['APP_VERSION']?.toString(),
        gitCommit: result.buildIdentity['CLIENT_GIT_COMMIT']?.toString(),
      ),
    );
    return result;
  }

  Future<List<DiagnosticIncident>> recentErrors({
    String? storeId,
    int limit = 50,
  }) async {
    await DiagnosticIncidentHistory.ensureHydrated();
    final sid = storeId ?? await currentStoreId();
    return DiagnosticIncidentHistory.recent(storeId: sid, limit: limit)
        .where((i) =>
            i.severity == DiagnosticSeverity.warning ||
            i.severity == DiagnosticSeverity.critical)
        .toList();
  }

  ({String fileName, List<int> bytes, String pretty}) exportLast() {
    final r = lastResult;
    if (r == null) {
      throw StateError('Execute o diagnóstico antes de exportar');
    }
    return DiagnosticExportService.build(r);
  }

  /// Record a runtime failure into incident history (still no stock mutation).
  Future<DiagnosticIncident> recordRuntimeError({
    required String storeId,
    required DiagnosticModule module,
    required String operationType,
    required Object error,
    StackTrace? stack,
    String? stage,
    String? saleId,
    String? stockOperationId,
    String? sourceOperationId,
    List<String> productIds = const [],
    Map<String, dynamic>? metadata,
    bool online = true,
  }) async {
    final classified = DiagnosticErrorClassifier.classify(
      error,
      stack: stack,
      online: online,
    );
    final build = clientBuildProofMap();
    final incident = DiagnosticIncident(
      incidentId: const Uuid().v4(),
      traceId: DiagnosticTraceService.activeTraceId ?? const Uuid().v4(),
      storeId: storeId,
      userIdHash: null,
      timestamp: DateTime.now().toUtc(),
      severity: classified.severity,
      module: module,
      operationType: operationType,
      classification: classified.classification,
      rootCauseStatus: classified.rootCauseStatus,
      userTitle: classified.userTitle,
      userMessage: classified.userMessage,
      safeNextAction: classified.safeNextAction,
      technicalMessage: classified.technicalMessage,
      firebaseCode: classified.firebaseCode,
      httpCode: classified.httpCode,
      functionName: classified.functionName,
      sourceOperationId: sourceOperationId,
      stockOperationId: stockOperationId,
      productIds: productIds,
      saleId: saleId,
      stage: stage,
      stackFrames: stackFramesList(stack),
      appVersion: build['APP_VERSION']?.toString(),
      gitCommit: build['CLIENT_GIT_COMMIT']?.toString(),
      buildId: build['CLIENT_BUILD_ID']?.toString(),
      online: online,
      metadataSanitized: metadata,
    );
    await DiagnosticIncidentHistory.record(incident);
    return incident;
  }

  /// Optional server telemetry — **disabled** until reviewed.
  static const bool serverTelemetryEnabled = false;
}
