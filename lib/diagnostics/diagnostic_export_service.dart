import 'dart:convert';

import 'diagnostic_result.dart';
import 'diagnostic_sanitize.dart';

/// Builds sanitized diagnostic JSON export (no secrets).
class DiagnosticExportService {
  DiagnosticExportService._();

  static String fileNameFor({
    required String storeId,
    DateTime? at,
  }) {
    final ts = (at ?? DateTime.now().toUtc())
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll('.', '');
    final safeStore = storeId
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
        .toUpperCase();
    return 'MASTERPALM_DIAGNOSTIC_${safeStore}_$ts.json';
  }

  static ({String fileName, List<int> bytes, String pretty}) build(
    DiagnosticResult result,
  ) {
    final payload = result.toExportJson();
    final pretty = safeJsonEncode(payload);
    final name = fileNameFor(
      storeId: result.storeId,
      at: result.generatedAt,
    );
    return (fileName: name, bytes: utf8.encode(pretty), pretty: pretty);
  }
}
