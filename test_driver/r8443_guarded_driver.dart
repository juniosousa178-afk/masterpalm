// R8.4.44A — driver dedicado R8443 com validação anti-falso-verde de reportData.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

import '../integration_test/support/r8443_report_contract.dart';

const _expectedRunIdDefine = String.fromEnvironment(
  'R8443_RUN_ID',
  defaultValue: '',
);
const _expectedTestCaseIdDefine = String.fromEnvironment(
  'R8443_TEST_CASE_ID',
  defaultValue: '',
);
const _responseFileDefine = String.fromEnvironment(
  'R8443_RESPONSE_FILE',
  defaultValue: '',
);

String _envOrDefine(String defineValue, String envKey) {
  if (defineValue.isNotEmpty) return defineValue;
  return Platform.environment[envKey] ?? '';
}

Future<void> _writeEvidenceFile(
  Map<String, String> reportData,
  String responseFile,
) async {
  if (responseFile.isEmpty) {
    throw StateError('R8443_RESPONSE_FILE não definido');
  }
  final envelope = <String, dynamic>{
    'schemaVersion': reportData['schemaVersion'] ?? '1',
    'runId': reportData['runId'],
    'testCaseId': reportData['testCaseId'],
    'reportTimestampMs': reportData['reportTimestampMs'],
    'reportData': reportData,
    'driverAcceptedAtMs': DateTime.now().millisecondsSinceEpoch,
  };
  final file = File(responseFile);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(envelope),
  );
}

Future<void> main() async {
  final expectedRunId = _envOrDefine(_expectedRunIdDefine, 'R8443_RUN_ID');
  final expectedTestCaseId =
      _envOrDefine(_expectedTestCaseIdDefine, 'R8443_TEST_CASE_ID');
  final responseFile = _envOrDefine(_responseFileDefine, 'R8443_RESPONSE_FILE');

  if (expectedRunId.isEmpty || expectedTestCaseId.isEmpty) {
    stderr.writeln(
      'R8443 driver: defina R8443_RUN_ID e R8443_TEST_CASE_ID (env ou dart-define)',
    );
    exit(2);
  }

  await integrationDriver(
    responseDataCallback: (Map<String, dynamic>? data) async {
      final result = validateR8443ReportData(
        data,
        expectedTestCaseId: expectedTestCaseId,
        expectedRunId: expectedRunId,
      );
      if (!result.ok) {
        stderr.writeln(
          '${result.rejectionCode}=true ${result.message}',
        );
        throw StateError(result.rejectionCode ?? 'R8443_INVALID');
      }
      print('R8443_VALID_REPORT_ACCEPTED=true');
      await _writeEvidenceFile(result.normalizedReportData!, responseFile);
    },
  );
}
