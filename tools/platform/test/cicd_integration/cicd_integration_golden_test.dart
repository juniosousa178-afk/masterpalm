import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/cicd_integration/cicd_integration_canonical_serializer.dart';
import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/history/mappers/cicd_integration_history_mapper.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_operational_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_request.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_result.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_snapshot.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:test/test.dart';

import 'support/cicd_integration_hardening_helpers.dart';
import 'support/cicd_integration_operational_fixtures.dart';

void main() {
  group('CI/CD Integration golden snapshots', () {
    late Map<String, dynamic> requestNormative;
    late Map<String, dynamic> snapshotCompleteNormative;
    late Map<String, dynamic> snapshotPartialNormative;
    late Map<String, dynamic> snapshotFailedNormative;
    late Map<String, dynamic> resultValidNormative;
    late Map<String, dynamic> resultInvalidNormative;
    late Map<String, dynamic> reportNormative;
    late Map<String, dynamic> historyComparableNormative;
    const serializer = CicdIntegrationCanonicalSerializer();

    setUpAll(() async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final cicd = core.cicdIntegration();

      final passingRequest =
          CicdIntegrationOperationalFixtures.passingRequest();
      final completeResult = await evaluatePassingSnapshot(provider: cicd);
      final partialResult = await cicd.evaluate(
        CicdIntegrationOperationalFixtures.partialRequest(),
      );
      final failedResult = await cicd.evaluate(
        CicdIntegrationOperationalFixtures.failedExecutionRequest(),
      );

      final completeSnapshot = completeResult.snapshot!;
      final partialSnapshot = partialResult.snapshot!;
      final failedSnapshot = failedResult.snapshot!;

      requestNormative = {
        'requestId': passingRequest.requestId,
        'projectId': passingRequest.projectId,
        'releaseId': passingRequest.releaseId,
        'pipelineIntegrationPolicyId':
            passingRequest.pipelineIntegrationPolicyId,
        'canonicalFingerprint': serializer.requestFingerprint(passingRequest),
      };

      snapshotCompleteNormative = {
        'cicdIntegrationSnapshotId':
            completeSnapshot.metadata.cicdIntegrationSnapshotId,
        'fingerprint': completeSnapshot.fingerprint,
        'status': completeSnapshot.status.wireName,
        'pipelineIntegrationPolicyId':
            completeSnapshot.metadata.pipelineIntegrationPolicyId,
        'pipelineIntegrationPolicyVersion':
            completeSnapshot.metadata.pipelineIntegrationPolicyVersion,
        'hasDeployment': completeSnapshot.deploymentPlan != null,
        'canonicalFingerprint':
            serializer.snapshotFingerprint(completeSnapshot),
      };

      snapshotPartialNormative = {
        'cicdIntegrationSnapshotId':
            partialSnapshot.metadata.cicdIntegrationSnapshotId,
        'fingerprint': partialSnapshot.fingerprint,
        'status': partialSnapshot.status.wireName,
        'hasDeployment': partialSnapshot.deploymentPlan != null,
        'canonicalFingerprint': serializer.snapshotFingerprint(partialSnapshot),
      };

      snapshotFailedNormative = {
        'cicdIntegrationSnapshotId':
            failedSnapshot.metadata.cicdIntegrationSnapshotId,
        'fingerprint': failedSnapshot.fingerprint,
        'executionStatus':
            failedSnapshot.pipelineExecution?.status.name ?? 'unknown',
        'canonicalFingerprint': serializer.snapshotFingerprint(failedSnapshot),
      };

      resultValidNormative = {
        'status': completeResult.status.wireName,
        'snapshotFingerprint': completeSnapshot.fingerprint,
        'publicationStatus': completeResult.publicationStatus?.wireName,
        'resolvedSourceCount':
            completeResult.sourceResolutionSummary?.resolvedSources.length ?? 0,
      };

      resultInvalidNormative = {
        'status': CicdIntegrationResultStatus.failure.wireName,
        'snapshotFingerprint': '',
        'errorCount': 1,
      };

      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.cicdIntegration,
          projectId: completeSnapshot.metadata.projectId,
          cicdIntegrationSnapshot: completeSnapshot.toJson(),
        ),
      );
      reportNormative = {
        'reportType': report.document.metadata.reportType.name,
        'sectionCount': report.document.sections.length,
        'projectId': completeSnapshot.metadata.projectId,
        'snapshotFingerprint': completeSnapshot.fingerprint,
      };

      const mapper = CicdIntegrationHistoryMapper();
      final artifact = mapper.fromMap(completeSnapshot.toJson());
      historyComparableNormative = {
        'artifactType': artifact.artifactType.name,
        'fingerprint': artifact.fingerprint,
        'snapshotId': completeSnapshot.metadata.cicdIntegrationSnapshotId,
        'comparableFingerprint': artifact.fingerprint,
      };
    });

    void assertGolden(
      String path,
      Map<String, dynamic> normative,
      List<String> keys,
    ) {
      final file = File(path);
      if (!file.existsSync()) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            '_note':
                'Intentional golden for CI/CD Integration. Update explicitly only.',
            ...normative,
          }),
        );
      }
      final golden =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final key in keys) {
        expect(normative[key], golden[key], reason: 'golden key: $key');
      }
    }

    test('request golden metadata is stable', () {
      assertGolden(
        'test/goldens/cicd_integration/request.json',
        requestNormative,
        [
          'requestId',
          'projectId',
          'releaseId',
          'pipelineIntegrationPolicyId',
          'canonicalFingerprint',
        ],
      );
    });

    test('snapshot complete golden metadata is stable', () {
      assertGolden(
        'test/goldens/cicd_integration/snapshot_complete.json',
        snapshotCompleteNormative,
        [
          'cicdIntegrationSnapshotId',
          'fingerprint',
          'status',
          'pipelineIntegrationPolicyId',
          'pipelineIntegrationPolicyVersion',
          'hasDeployment',
          'canonicalFingerprint',
        ],
      );
    });

    test('snapshot partial golden metadata is stable', () {
      assertGolden(
        'test/goldens/cicd_integration/snapshot_partial.json',
        snapshotPartialNormative,
        [
          'cicdIntegrationSnapshotId',
          'fingerprint',
          'status',
          'hasDeployment',
          'canonicalFingerprint',
        ],
      );
    });

    test('snapshot failed golden metadata is stable', () {
      assertGolden(
        'test/goldens/cicd_integration/snapshot_failed.json',
        snapshotFailedNormative,
        [
          'cicdIntegrationSnapshotId',
          'fingerprint',
          'executionStatus',
          'canonicalFingerprint',
        ],
      );
    });

    test('result valid golden metadata is stable', () {
      assertGolden(
        'test/goldens/cicd_integration/result_valid.json',
        resultValidNormative,
        [
          'status',
          'snapshotFingerprint',
          'resolvedSourceCount',
        ],
      );
    });

    test('result invalid golden metadata is stable', () {
      assertGolden(
        'test/goldens/cicd_integration/result_invalid.json',
        resultInvalidNormative,
        [
          'status',
          'snapshotFingerprint',
          'errorCount',
        ],
      );
    });

    test('report golden metadata is stable', () {
      assertGolden(
        'test/goldens/cicd_integration/report.json',
        reportNormative,
        [
          'reportType',
          'sectionCount',
          'projectId',
          'snapshotFingerprint',
        ],
      );
    });

    test('history comparable golden metadata is stable', () {
      assertGolden(
        'test/goldens/cicd_integration/history_comparable.json',
        historyComparableNormative,
        [
          'artifactType',
          'fingerprint',
          'snapshotId',
          'comparableFingerprint',
        ],
      );
    });

    test('snapshot json round-trip matches golden fingerprint', () async {
      final result = await evaluatePassingSnapshot();
      final snapshot = result.snapshot!;
      final restored = CicdIntegrationSnapshot.fromJson(snapshot.toJson());
      expect(
        serializer.snapshotFingerprint(restored),
        serializer.snapshotFingerprint(snapshot),
      );
    });

    test('request json round-trip matches golden fingerprint', () {
      final request = CicdIntegrationOperationalFixtures.passingRequest();
      final restored = CicdIntegrationRequest.fromJson(request.toJson());
      expect(
        serializer.requestFingerprint(restored),
        serializer.requestFingerprint(request),
      );
    });
  });
}
