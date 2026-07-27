import 'package:masterpalm_platform/history/mappers/persistent_artifact_history_mapper.dart';
import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';
import 'support/persistent_artifact_operational_fixtures.dart';
import 'support/persistent_artifact_test_fixtures.dart';

void main() {
  group('Persistent Artifact golden snapshots', () {
    test('01 evaluation request golden is stable', () {
      assertPersistentArtifactGolden(
        'evaluation_request',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'evaluation_request',
          'evaluationId': 'eval-golden',
          'projectId': 'proj-a',
          'releaseId': 'rel-a',
        },
        ['schema', 'name', 'evaluationId', 'projectId', 'releaseId'],
      );
    });

    test('02 resolved sources golden is stable', () {
      assertPersistentArtifactGolden(
        'resolved_sources',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'resolved_sources',
          'status': 'unavailable',
          'resolvedCount': 0,
          'unresolvedCount': 4,
        },
        ['schema', 'name', 'status', 'resolvedCount', 'unresolvedCount'],
      );
    });

    test('03 collected material golden is stable', () {
      assertPersistentArtifactGolden(
        'collected_material',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'collected_material',
          'subjectCount': 1,
          'policyCount': 0,
          'sourceReferenceCount': 0,
        },
        [
          'schema',
          'name',
          'subjectCount',
          'policyCount',
          'sourceReferenceCount'
        ],
      );
    });

    test('04 subject golden is stable', () {
      assertPersistentArtifactGolden(
        'subject',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'subject',
          'subjectId': 'subject-pa-001',
          'artifactType': 'releaseEvidence',
          'projectId': 'masterpalm-demo',
        },
        ['schema', 'name', 'subjectId', 'artifactType', 'projectId'],
      );
    });

    test('05 content descriptor golden is stable', () {
      assertPersistentArtifactGolden(
        'content_descriptor',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'content_descriptor',
          'contentId': 'content-pa-001',
          'mediaType': 'application/json',
          'format': 'json',
        },
        ['schema', 'name', 'contentId', 'mediaType', 'format'],
      );
    });

    test('06 version golden is stable', () {
      assertPersistentArtifactGolden(
        'version',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'version',
          'artifactId': 'art-pa-001',
          'versionId': 'ver-pa-001',
          'revision': 1,
        },
        ['schema', 'name', 'artifactId', 'versionId', 'revision'],
      );
    });

    test('07 manifest golden is stable', () {
      assertPersistentArtifactGolden(
        'manifest',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'manifest',
          'manifestId': 'manifest-pa-001',
          'artifactId': 'art-pa-001',
          'versionId': 'ver-pa-001',
        },
        ['schema', 'name', 'manifestId', 'artifactId', 'versionId'],
      );
    });

    test('08 integrity evaluation golden is stable', () {
      assertPersistentArtifactGolden(
        'integrity_evaluation',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'integrity_evaluation',
          'operationType': 'persist',
          'status': 'succeeded',
          'artifactResultCount': 1,
        },
        ['schema', 'name', 'operationType', 'status', 'artifactResultCount'],
      );
    });

    test('09 storage policy evaluation golden is stable', () {
      assertPersistentArtifactGolden(
        'storage_policy_evaluation',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'storage_policy_evaluation',
          'operationType': 'persist',
          'status': 'succeeded',
          'artifactResultCount': 1,
        },
        ['schema', 'name', 'operationType', 'status', 'artifactResultCount'],
      );
    });

    test('10 retention evaluation golden is stable', () {
      assertPersistentArtifactGolden(
        'retention_evaluation',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'retention_evaluation',
          'operationType': 'persist',
          'status': 'succeeded',
          'artifactResultCount': 1,
        },
        ['schema', 'name', 'operationType', 'status', 'artifactResultCount'],
      );
    });

    test('11 replication evaluation golden is stable', () {
      assertPersistentArtifactGolden(
        'replication_evaluation',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'replication_evaluation',
          'operationType': 'persist',
          'status': 'succeeded',
          'artifactResultCount': 1,
        },
        ['schema', 'name', 'operationType', 'status', 'artifactResultCount'],
      );
    });

    test('12 availability evaluation golden is stable', () {
      assertPersistentArtifactGolden(
        'availability_evaluation',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'availability_evaluation',
          'operationType': 'persist',
          'status': 'succeeded',
          'artifactResultCount': 1,
        },
        ['schema', 'name', 'operationType', 'status', 'artifactResultCount'],
      );
    });

    test('13 lifecycle evaluation golden is stable', () {
      assertPersistentArtifactGolden(
        'lifecycle_evaluation',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'lifecycle_evaluation',
          'operationType': 'persist',
          'status': 'succeeded',
          'artifactResultCount': 1,
        },
        ['schema', 'name', 'operationType', 'status', 'artifactResultCount'],
      );
    });

    test('14 publication evaluation golden is stable', () {
      assertPersistentArtifactGolden(
        'publication_evaluation',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'publication_evaluation',
          'operationType': 'persist',
          'status': 'succeeded',
          'artifactResultCount': 1,
        },
        ['schema', 'name', 'operationType', 'status', 'artifactResultCount'],
      );
    });

    test('15 deletion eligible golden is stable', () {
      assertPersistentArtifactGolden(
        'deletion_eligible',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'deletion_eligible',
          'operationType': 'requestDeletion',
          'status': 'succeeded',
          'legalHold': 'false',
        },
        ['schema', 'name', 'operationType', 'status', 'legalHold'],
      );
    });

    test('16 deletion blocked golden is stable', () {
      assertPersistentArtifactGolden(
        'deletion_blocked',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'deletion_blocked',
          'operationType': 'requestDeletion',
          'status': 'blocked',
          'legalHold': 'true',
        },
        ['schema', 'name', 'operationType', 'status', 'legalHold'],
      );
    });

    test('17 tombstone golden is stable', () {
      assertPersistentArtifactGolden(
        'tombstone',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'tombstone',
          'operationType': 'snapshot',
          'status': 'succeeded',
          'tombstone': 'built',
        },
        ['schema', 'name', 'operationType', 'status', 'tombstone'],
      );
    });

    test('18 snapshot available golden is stable', () {
      assertPersistentArtifactGolden(
        'snapshot_available',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'snapshot_available',
          'status': 'published',
          'subjectCount': 1,
          'operationCount': 1,
        },
        ['schema', 'name', 'status', 'subjectCount', 'operationCount'],
      );
    });

    test('19 snapshot partial golden is stable', () {
      assertPersistentArtifactGolden(
        'snapshot_partial',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'snapshot_partial',
          'status': 'evaluated',
          'subjectCount': 1,
          'operationCount': 1,
        },
        ['schema', 'name', 'status', 'subjectCount', 'operationCount'],
      );
    });

    test('20 snapshot failed golden is stable', () {
      assertPersistentArtifactGolden(
        'snapshot_failed',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'snapshot_failed',
          'status': 'failed',
          'subjectCount': 1,
          'operationCount': 1,
        },
        ['schema', 'name', 'status', 'subjectCount', 'operationCount'],
      );
    });

    test('21 snapshot conflicting golden is stable', () {
      assertPersistentArtifactGolden(
        'snapshot_conflicting',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'snapshot_conflicting',
          'status': 'failed',
          'expectedException': 'PersistentArtifactSnapshotConflictException',
        },
        ['schema', 'name', 'status', 'expectedException'],
      );
    });

    test('22 operation result golden is stable', () {
      assertPersistentArtifactGolden(
        'operation_result',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'operation_result',
          'status': 'succeeded',
          'operationType': 'persist',
          'artifactResultCount': 1,
        },
        ['schema', 'name', 'status', 'operationType', 'artifactResultCount'],
      );
    });

    test('23 report golden is stable', () {
      assertPersistentArtifactGolden(
        'report',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'report',
          'reportType': 'persistentArtifacts',
          'projectId': 'proj-a',
          'sectionCountAtLeast': 1,
        },
        ['schema', 'name', 'reportType', 'projectId', 'sectionCountAtLeast'],
      );
    });

    test('24 history comparable golden is stable', () {
      assertPersistentArtifactGolden(
        'history_comparable',
        const {
          'schema': 'persistent-artifact-golden-v1',
          'name': 'history_comparable',
          'artifactType': 'persistentArtifacts',
          'projectId': 'proj-a',
          'fingerprintPresent': true,
        },
        ['schema', 'name', 'artifactType', 'projectId', 'fingerprintPresent'],
      );
    });

    test('runtime cross-check for report and history data', () async {
      final result = await evaluatePassingSnapshot();
      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.persistentArtifacts,
          projectId: result.projectId,
          persistentArtifactSnapshot: result.snapshot!.toJson(),
        ),
      );
      expect(report.document.sections.length, greaterThanOrEqualTo(1));
      final artifact = const PersistentArtifactHistoryMapper()
          .fromMap(result.snapshot!.toJson());
      expect(artifact.fingerprint, isNotEmpty);
      expect(artifact.artifactId, isNotEmpty);
      expect(
          PersistentArtifactTestFixtures.validSnapshot().metadata, isNotEmpty);
      expect(fixtureEvaluationRequest().evaluationId, isNotEmpty);
    });
  });
}
