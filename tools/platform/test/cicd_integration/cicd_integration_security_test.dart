import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/cicd_integration/cicd_integration_canonical_serializer.dart';
import 'package:masterpalm_platform/models/observability/telemetry_attributes.dart';
import 'package:masterpalm_platform/models/observability/telemetry_enums.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/observability/telemetry_data_sanitizer.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/cicd_integration_hardening_helpers.dart';
import 'support/pipeline_test_fixtures.dart';

void main() {
  group('CI/CD Integration security review', () {
    const sentinelSecret = 'SECRET_TOKEN_SHOULD_NOT_APPEAR';
    const sentinelApiKey = 'API_KEY_SHOULD_NOT_APPEAR';

    test('snapshot json omits sentinel when not in domain inputs', () async {
      final result = await evaluatePassingSnapshot();
      final encoded = jsonEncode(result.snapshot!.toJson());
      expect(encoded.contains(sentinelSecret), isFalse);
      expect(encoded.contains(sentinelApiKey), isFalse);
    });

    test('canonical snapshot fingerprint omits sentinel', () async {
      final result = await evaluatePassingSnapshot();
      const serializer = CicdIntegrationCanonicalSerializer();
      final fp = serializer.snapshotFingerprint(result.snapshot!);
      expect(fp.contains(sentinelSecret), isFalse);
    });

    test('report output omits sentinel strings', () async {
      final result = await evaluatePassingSnapshot();
      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.cicdIntegration,
          projectId: result.snapshot!.metadata.projectId,
          cicdIntegrationSnapshot: result.snapshot!.toJson(),
        ),
      );
      final encoded = jsonEncode(report.document.toJson());
      expect(encoded.contains(sentinelSecret), isFalse);
    });

    test('sha256 placeholders are sentinel strings not crypto claims', () {
      expect(PipelineTestFixtures.sha256Placeholder, hasLength(64));
      expect(
        PipelineTestFixtures.validArtifact().fingerprint,
        PipelineTestFixtures.sha256Placeholder,
      );
    });

    test('no pipeline execution is assumed in snapshot limitations', () async {
      final result = await evaluatePassingSnapshot();
      final limitations = result.snapshot?.metadata.limitations ?? const [];
      expect(
        limitations.any((l) => l.contains('no-pipeline-execution')),
        isTrue,
      );
    });

    test('telemetry sanitizer redacts secret attributes', () {
      const sanitizer = TelemetryDataSanitizer();
      final result = sanitizer.sanitize(
        TelemetryStringAttribute(
          key: 'secretToken',
          stringValue: sentinelSecret,
          classification: TelemetryAttributeClassification.internal,
        ),
      );
      expect(result.wasRejected || result.wasRedacted, isTrue);
    });

    group('lib/cicd_integration static checks', () {
      late List<File> sourceFiles;

      setUpAll(() {
        final libDir = Directory(p.join('lib', 'cicd_integration'));
        sourceFiles = libDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList();
        expect(sourceFiles, isNotEmpty);
      });

      test('source resolver does not invoke upstream evaluate', () {
        final resolver = sourceFiles.firstWhere(
            (f) => f.path.endsWith('cicd_integration_source_resolver.dart'));
        final content = resolver.readAsStringSync();
        expect(content.contains('.evaluate('), isFalse);
        expect(content.contains('.evaluateAndPublish('), isFalse);
      });

      test('engine does not execute remote pipelines', () {
        final engine = sourceFiles
            .firstWhere((f) => f.path.endsWith('cicd_integration_engine.dart'));
        final content = engine.readAsStringSync();
        expect(content.contains('Process.run'), isFalse);
        expect(content.contains('http.get'), isFalse);
        expect(content.contains('HttpClient'), isFalse);
      });

      test('lib sources do not embed hardcoded secrets', () {
        for (final file in sourceFiles) {
          final content = file.readAsStringSync();
          expect(content.contains(sentinelSecret), isFalse, reason: file.path);
          expect(content.contains(sentinelApiKey), isFalse, reason: file.path);
        }
      });

      test('collector does not rebuild upstream snapshots', () {
        final collector = sourceFiles.firstWhere(
            (f) => f.path.endsWith('cicd_integration_collector.dart'));
        final content = collector.readAsStringSync();
        expect(content.contains('ReleaseEvidenceProvider'), isFalse);
        expect(content.contains('ReleaseSupplyChainProvider'), isFalse);
      });
    });
  });
}
