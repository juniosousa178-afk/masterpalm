// R8.4.44A — testes unitários do validador R8443.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/r8443_report_contract.dart';

void main() {
  final manifest = loadR8443ManifestFromProjectRoot();
  const runId = 'unit-run-001';
  const testCaseId = 'phase_a';

  Map<String, dynamic> fullPhaseAReport() => {
        'schemaVersion': '1',
        'runId': runId,
        'testCaseId': testCaseId,
        'reportTimestampMs': '${DateTime.now().millisecondsSinceEpoch}',
        'PRODUCTION_REQUEST_ATTEMPTED_COUNT': '0',
        'PRODUCTION_REQUEST_COMPLETED_COUNT': '0',
        'SESSION_PHASE_A_AUTHENTICATED': 'true',
        'SESSION_PHASE_A_HOME_READY': 'true',
        'SESSION_PHASE_A_UID_MATCH': 'true',
        'uid': 'qa-uid',
      };

  test('null reportData', () {
    final r = validateR8443ReportData(
      null,
      expectedTestCaseId: testCaseId,
      expectedRunId: runId,
      manifest: manifest,
    );
    expect(r.ok, isFalse);
    expect(r.rejectionCode, R8443RejectionCodes.missingReportData);
  });

  test('empty reportData', () {
    final r = validateR8443ReportData(
      <String, dynamic>{},
      expectedTestCaseId: testCaseId,
      expectedRunId: runId,
      manifest: manifest,
    );
    expect(r.ok, isFalse);
    expect(r.rejectionCode, R8443RejectionCodes.emptyReportData);
  });

  test('missing required marker', () {
    final data = fullPhaseAReport();
    data.remove('SESSION_PHASE_A_AUTHENTICATED');
    final r = validateR8443ReportData(
      data,
      expectedTestCaseId: testCaseId,
      expectedRunId: runId,
      manifest: manifest,
    );
    expect(r.ok, isFalse);
    expect(r.rejectionCode, R8443RejectionCodes.missingRequiredMarker);
  });

  test('wrong marker value', () {
    final data = fullPhaseAReport();
    data['SESSION_PHASE_A_HOME_READY'] = 'false';
    final r = validateR8443ReportData(
      data,
      expectedTestCaseId: testCaseId,
      expectedRunId: runId,
      manifest: manifest,
    );
    expect(r.ok, isFalse);
    expect(r.rejectionCode, R8443RejectionCodes.wrongValue);
  });

  test('wrong type on marker', () {
    final data = fullPhaseAReport();
    data['SESSION_PHASE_A_AUTHENTICATED'] = 1;
    final r = validateR8443ReportData(
      data,
      expectedTestCaseId: testCaseId,
      expectedRunId: runId,
      manifest: manifest,
    );
    expect(r.ok, isFalse);
    expect(r.rejectionCode, R8443RejectionCodes.wrongType);
  });

  test('wrong runId', () {
    final data = fullPhaseAReport();
    data['runId'] = 'other-run';
    final r = validateR8443ReportData(
      data,
      expectedTestCaseId: testCaseId,
      expectedRunId: runId,
      manifest: manifest,
    );
    expect(r.ok, isFalse);
    expect(r.rejectionCode, R8443RejectionCodes.wrongRunId);
  });

  test('wrong testCaseId', () {
    final data = fullPhaseAReport();
    data['testCaseId'] = 'phase_b';
    final r = validateR8443ReportData(
      data,
      expectedTestCaseId: testCaseId,
      expectedRunId: runId,
      manifest: manifest,
    );
    expect(r.ok, isFalse);
    expect(r.rejectionCode, R8443RejectionCodes.wrongTestCase);
  });

  test('valid phase_a report', () {
    final r = validateR8443ReportData(
      fullPhaseAReport(),
      expectedTestCaseId: testCaseId,
      expectedRunId: runId,
      manifest: manifest,
    );
    expect(r.ok, isTrue);
    expect(r.normalizedReportData, isNotNull);
  });

  test('invalid json file', () async {
    final dir = Directory.systemTemp.createTempSync('r8443-json');
    final path = '${dir.path}/bad.json';
    File(path).writeAsStringSync('{not json');
    final r = validateR8443EvidenceFile(
      path,
      expectedTestCaseId: testCaseId,
      expectedRunId: runId,
      manifest: manifest,
    );
    expect(r.ok, isFalse);
    expect(r.rejectionCode, R8443RejectionCodes.invalidJson);
    dir.deleteSync(recursive: true);
  });

  test('missing file', () {
    final r = validateR8443EvidenceFile(
      '${Directory.systemTemp.path}/r8443-nonexistent-${DateTime.now().millisecondsSinceEpoch}.json',
      expectedTestCaseId: testCaseId,
      expectedRunId: runId,
      manifest: manifest,
    );
    expect(r.ok, isFalse);
    expect(r.rejectionCode, R8443RejectionCodes.missingFile);
  });

  test('stale artifact timestamp', () async {
    final dir = Directory.systemTemp.createTempSync('r8443-stale');
    final path = '${dir.path}/stale.json';
    final data = fullPhaseAReport();
    data['reportTimestampMs'] = '1000';
    final envelope = {'reportData': data};
    File(path).writeAsStringSync(jsonEncode(envelope));
    final phaseStart = DateTime.now().millisecondsSinceEpoch;
    final r = validateR8443EvidenceFile(
      path,
      expectedTestCaseId: testCaseId,
      expectedRunId: runId,
      phaseStartMs: phaseStart,
      manifest: manifest,
    );
    expect(r.ok, isFalse);
    expect(r.rejectionCode, R8443RejectionCodes.staleArtifact);
    dir.deleteSync(recursive: true);
  });

  test('valid evidence file', () async {
    final dir = Directory.systemTemp.createTempSync('r8443-ok');
    final path = '${dir.path}/ok.json';
    final data = fullPhaseAReport();
    final envelope = {'reportData': data};
    File(path).writeAsStringSync(jsonEncode(envelope));
    final phaseStart = DateTime.now().millisecondsSinceEpoch - 5000;
    final r = validateR8443EvidenceFile(
      path,
      expectedTestCaseId: testCaseId,
      expectedRunId: runId,
      phaseStartMs: phaseStart,
      manifest: manifest,
    );
    expect(r.ok, isTrue);
    dir.deleteSync(recursive: true);
  });

  test('control_positive case', () {
    const cpRun = 'control-pos-run';
    final data = {
      'schemaVersion': '1',
      'runId': cpRun,
      'testCaseId': 'control_positive',
      'reportTimestampMs': '${DateTime.now().millisecondsSinceEpoch}',
      'PRODUCTION_REQUEST_ATTEMPTED_COUNT': '0',
      'PRODUCTION_REQUEST_COMPLETED_COUNT': '0',
      'R8443_CONTROL_POSITIVE_GREEN': 'true',
    };
    final r = validateR8443ReportData(
      data,
      expectedTestCaseId: 'control_positive',
      expectedRunId: cpRun,
      manifest: manifest,
    );
    expect(r.ok, isTrue);
  });
}
