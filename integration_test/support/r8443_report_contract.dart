// R8.4.44A — validação de reportData R8443 (infra de teste; não produção).

import 'dart:convert';
import 'dart:io';

/// Códigos de rejeição estáveis para driver, PowerShell e testes unitários.
class R8443RejectionCodes {
  static const missingReportData = 'R8443_MISSING_REPORTDATA_REJECTED';
  static const emptyReportData = 'R8443_EMPTY_REPORTDATA_REJECTED';
  static const missingRequiredMarker = 'R8443_MISSING_REQUIRED_MARKER_REJECTED';
  static const wrongValue = 'R8443_WRONG_VALUE_REJECTED';
  static const wrongType = 'R8443_WRONG_TYPE_REJECTED';
  static const wrongRunId = 'R8443_WRONG_RUN_ID_REJECTED';
  static const wrongTestCase = 'R8443_WRONG_TEST_CASE_REJECTED';
  static const staleArtifact = 'R8443_STALE_REPORT_ARTIFACT_REJECTED';
  static const invalidJson = 'R8443_INVALID_JSON_REJECTED';
  static const missingFile = 'R8443_MISSING_RESPONSE_FILE_REJECTED';
  static const successTextWithoutEvidence =
      'R8443_SUCCESS_TEXT_WITHOUT_EVIDENCE_REJECTED';
}

class R8443ReportValidationResult {
  const R8443ReportValidationResult({
    required this.ok,
    this.rejectionCode,
    this.message,
    this.normalizedReportData,
  });

  final bool ok;
  final String? rejectionCode;
  final String? message;
  final Map<String, String>? normalizedReportData;

  factory R8443ReportValidationResult.accept(
    Map<String, String> data,
  ) =>
      R8443ReportValidationResult(
        ok: true,
        normalizedReportData: Map<String, String>.from(data),
      );

  factory R8443ReportValidationResult.reject(
    String code,
    String message,
  ) =>
      R8443ReportValidationResult(
        ok: false,
        rejectionCode: code,
        message: message,
      );
}

Map<String, dynamic> loadR8443ManifestFromProjectRoot({
  String manifestRelativePath =
      'integration_test/support/r8443_report_manifest.json',
}) {
  final file = File(manifestRelativePath);
  if (!file.existsSync()) {
    throw StateError('Manifesto R8443 ausente: ${file.path}');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

String _stringValue(Map<String, dynamic> data, String key) {
  final v = data[key];
  if (v == null) return '';
  return v.toString();
}

/// Valida o mapa plano enviado pelo integration_test (reportData).
R8443ReportValidationResult validateR8443ReportData(
  Map<String, dynamic>? data, {
  required String expectedTestCaseId,
  required String expectedRunId,
  Map<String, dynamic>? manifest,
}) {
  if (data == null) {
    return R8443ReportValidationResult.reject(
      R8443RejectionCodes.missingReportData,
      'reportData null',
    );
  }
  if (data.isEmpty) {
    return R8443ReportValidationResult.reject(
      R8443RejectionCodes.emptyReportData,
      'reportData vazio',
    );
  }

  manifest ??= loadR8443ManifestFromProjectRoot();
  final schemaVersion = manifest['schemaVersion']?.toString() ?? '1';
  final cases = manifest['cases'] as Map<String, dynamic>?;
  if (cases == null || !cases.containsKey(expectedTestCaseId)) {
    return R8443ReportValidationResult.reject(
      R8443RejectionCodes.wrongTestCase,
      'testCaseId desconhecido no manifesto: $expectedTestCaseId',
    );
  }

  final caseDef = cases[expectedTestCaseId] as Map<String, dynamic>;
  final productionCounters =
      manifest['productionCounters'] as Map<String, dynamic>? ?? {};

  final envelopeKeys = (manifest['envelopeKeys'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ??
      ['schemaVersion', 'runId', 'testCaseId', 'reportTimestampMs'];

  for (final key in envelopeKeys) {
    if (!data.containsKey(key)) {
      return R8443ReportValidationResult.reject(
        R8443RejectionCodes.missingRequiredMarker,
        'envelope ausente: $key',
      );
    }
    if (data[key] is! String && data[key] != null) {
      return R8443ReportValidationResult.reject(
        R8443RejectionCodes.wrongType,
        '$key deve ser string',
      );
    }
  }

  final gotSchema = _stringValue(data, 'schemaVersion');
  if (gotSchema != schemaVersion) {
    return R8443ReportValidationResult.reject(
      R8443RejectionCodes.wrongValue,
      'schemaVersion=$gotSchema esperado=$schemaVersion',
    );
  }

  final gotRunId = _stringValue(data, 'runId');
  if (gotRunId.isEmpty) {
    return R8443ReportValidationResult.reject(
      R8443RejectionCodes.missingRequiredMarker,
      'runId vazio',
    );
  }
  if (expectedRunId.isNotEmpty && gotRunId != expectedRunId) {
    return R8443ReportValidationResult.reject(
      R8443RejectionCodes.wrongRunId,
      'runId=$gotRunId esperado=$expectedRunId',
    );
  }

  final gotTestCase = _stringValue(data, 'testCaseId');
  if (gotTestCase.isEmpty) {
    return R8443ReportValidationResult.reject(
      R8443RejectionCodes.missingRequiredMarker,
      'testCaseId vazio',
    );
  }
  if (gotTestCase != expectedTestCaseId) {
    return R8443ReportValidationResult.reject(
      R8443RejectionCodes.wrongTestCase,
      'testCaseId=$gotTestCase esperado=$expectedTestCaseId',
    );
  }

  for (final entry in productionCounters.entries) {
    final key = entry.key;
    final expected = entry.value.toString();
    if (!data.containsKey(key)) {
      return R8443ReportValidationResult.reject(
        R8443RejectionCodes.missingRequiredMarker,
        'contador produção ausente: $key',
      );
    }
    final got = _stringValue(data, key);
    if (got != expected) {
      return R8443ReportValidationResult.reject(
        R8443RejectionCodes.wrongValue,
        '$key=$got esperado=$expected',
      );
    }
  }

  final requiredMarkers =
      caseDef['requiredMarkers'] as Map<String, dynamic>? ?? {};
  for (final entry in requiredMarkers.entries) {
    final key = entry.key;
    final expected = entry.value.toString();
    if (!data.containsKey(key)) {
      return R8443ReportValidationResult.reject(
        R8443RejectionCodes.missingRequiredMarker,
        'marcador ausente: $key',
      );
    }
    if (data[key] is! String && data[key] != null) {
      return R8443ReportValidationResult.reject(
        R8443RejectionCodes.wrongType,
        '$key deve ser string',
      );
    }
    final got = _stringValue(data, key);
    if (got != expected) {
      return R8443ReportValidationResult.reject(
        R8443RejectionCodes.wrongValue,
        '$key=$got esperado=$expected',
      );
    }
  }

  final normalized = <String, String>{};
  for (final entry in data.entries) {
    normalized[entry.key] = entry.value?.toString() ?? '';
  }
  return R8443ReportValidationResult.accept(normalized);
}

/// Valida arquivo de evidência gravado pelo driver (JSON com reportData aninhado ou plano).
R8443ReportValidationResult validateR8443EvidenceFile(
  String filePath, {
  required String expectedTestCaseId,
  required String expectedRunId,
  int? phaseStartMs,
  Map<String, dynamic>? manifest,
}) {
  final file = File(filePath);
  if (!file.existsSync()) {
    return R8443ReportValidationResult.reject(
      R8443RejectionCodes.missingFile,
      'arquivo inexistente: $filePath',
    );
  }

  Map<String, dynamic> decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    return R8443ReportValidationResult.reject(
      R8443RejectionCodes.invalidJson,
      '$e',
    );
  }

  Map<String, dynamic>? reportData;
  if (decoded.containsKey('reportData')) {
    final inner = decoded['reportData'];
    if (inner is Map) {
      reportData = Map<String, dynamic>.from(inner);
    }
  } else {
    reportData = decoded;
  }

  final result = validateR8443ReportData(
    reportData,
    expectedTestCaseId: expectedTestCaseId,
    expectedRunId: expectedRunId,
    manifest: manifest,
  );
  if (!result.ok) {
    return result;
  }

  if (phaseStartMs != null) {
    final ts = int.tryParse(result.normalizedReportData?['reportTimestampMs'] ?? '');
    if (ts == null || ts < phaseStartMs) {
      return R8443ReportValidationResult.reject(
        R8443RejectionCodes.staleArtifact,
        'reportTimestampMs=$ts phaseStartMs=$phaseStartMs',
      );
    }
  }

  return result;
}
