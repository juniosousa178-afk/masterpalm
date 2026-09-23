import 'diagnostic_enums.dart';
import 'diagnostic_incident.dart';
import 'diagnostic_sanitize.dart';

/// Full diagnostic run result for current tenant.
class DiagnosticResult {
  DiagnosticResult({
    required this.diagnosticId,
    required this.storeId,
    required this.generatedAt,
    required this.health,
    required this.summary,
    required this.incidents,
    required this.buildIdentity,
    this.operationTraces = const [],
    this.stockComparisons = const [],
    this.saleDiagnostics = const [],
    this.pendingDiagnostics = const [],
    this.tombstoneDiagnostics = const [],
    Map<String, dynamic>? extra,
  }) : extra = sanitizeDiagnosticMap(extra ?? const {});

  final String diagnosticId;
  final String storeId;
  final DateTime generatedAt;
  final DiagnosticHealthStatus health;
  final Map<String, dynamic> summary;
  final List<DiagnosticIncident> incidents;
  final Map<String, dynamic> buildIdentity;
  final List<Map<String, dynamic>> operationTraces;
  final List<Map<String, dynamic>> stockComparisons;
  final List<Map<String, dynamic>> saleDiagnostics;
  final List<Map<String, dynamic>> pendingDiagnostics;
  final List<Map<String, dynamic>> tombstoneDiagnostics;
  final Map<String, dynamic> extra;

  int get anomalyCount => incidents.length;
  int get criticalCount =>
      incidents.where((i) => i.severity == DiagnosticSeverity.critical).length;

  Map<String, dynamic> toExportJson() => sanitizeDiagnosticMap({
        'DIAGNOSTIC_ID': diagnosticId,
        'STORE_ID': storeId,
        'GENERATED_AT': generatedAt.toUtc().toIso8601String(),
        'SYSTEM_STATUS': health.wire,
        'DIAGNOSTIC_READ_ONLY_BY_DEFAULT': true,
        'PRODUCTION_DATA_REPAIR': false,
        'summary': summary,
        'buildIdentity': buildIdentity,
        'tenant': {'storeId': storeId},
        'incidents': incidents.map((i) => i.toJson(includeStack: true)).toList(),
        'operationTraces': operationTraces,
        'stockComparisons': stockComparisons,
        'saleDiagnostics': saleDiagnostics,
        'pendingDiagnostics': pendingDiagnostics,
        'tombstoneDiagnostics': tombstoneDiagnostics,
        if (extra.isNotEmpty) 'extra': extra,
      });
}
