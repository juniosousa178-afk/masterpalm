import 'package:masterpalm_platform/cicd_integration/cicd_integration_canonical_serializer.dart';
import 'package:masterpalm_platform/cicd_integration/policies/deployment_integration_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_execution_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_integration_policy_v1.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_operational_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_policy_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_query.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_request.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_result.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_snapshot.dart';
import 'package:masterpalm_platform/models/cicd_integration/deployment_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_models.dart';
import 'package:test/test.dart';

import 'support/cicd_integration_hardening_helpers.dart';
import 'support/cicd_integration_operational_fixtures.dart';
import 'support/pipeline_test_fixtures.dart';

void main() {
  group('CI/CD Integration serialization audit', () {
    const serializer = CicdIntegrationCanonicalSerializer();

    void roundTrip<T>({
      required T original,
      required Map<String, dynamic> Function(T) toJson,
      required T Function(Map<String, dynamic>) fromJson,
      void Function(T restored)? assertEqual,
    }) {
      final json = toJson(original);
      final restored = fromJson(Map<String, dynamic>.from(json));
      assertEqual?.call(restored);
    }

    test('CicdIntegrationSnapshot roundtrip', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      roundTrip<CicdIntegrationSnapshot>(
        original: snapshot,
        toJson: (s) => s.toJson(),
        fromJson: CicdIntegrationSnapshot.fromJson,
        assertEqual: (r) {
          expect(
            r.metadata.cicdIntegrationSnapshotId,
            snapshot.metadata.cicdIntegrationSnapshotId,
          );
          expect(r.fingerprint, isNotEmpty);
        },
      );
    });

    test('PipelineDefinition roundtrip', () {
      roundTrip<PipelineDefinition>(
        original: PipelineTestFixtures.validDefinition(),
        toJson: (d) => d.toJson(),
        fromJson: PipelineDefinition.fromJson,
        assertEqual: (r) => expect(r.fingerprint, isNotEmpty),
      );
    });

    test('PipelineExecution roundtrip', () {
      roundTrip<PipelineExecution>(
        original: PipelineTestFixtures.validExecution(),
        toJson: (e) => e.toJson(),
        fromJson: PipelineExecution.fromJson,
        assertEqual: (r) => expect(r.status, PipelineStatus.succeeded),
      );
    });

    test('DeploymentPlan roundtrip', () {
      roundTrip<DeploymentPlan>(
        original: PipelineTestFixtures.validDeploymentPlan(),
        toJson: (p) => p.toJson(),
        fromJson: DeploymentPlan.fromJson,
        assertEqual: (r) => expect(r.strategy, DeploymentStrategy.rolling),
      );
    });

    test('DeploymentResult roundtrip', () {
      roundTrip<DeploymentResult>(
        original: PipelineTestFixtures.validDeploymentResult(),
        toJson: (r) => r.toJson(),
        fromJson: DeploymentResult.fromJson,
        assertEqual: (r) => expect(r.status, DeploymentResultStatus.succeeded),
      );
    });

    test('CicdIntegrationRequest roundtrip preserves useLatest', () {
      final request =
          CicdIntegrationOperationalFixtures.passingRequest().copyWith(
        useLatest: true,
      );
      final json = request.toJson();
      final restored = CicdIntegrationRequest.fromJson(json);
      expect(restored.useLatest, isTrue);
      expect(restored.requestedAt,
          CicdIntegrationOperationalFixtures.referenceTime);
    });

    test('CicdIntegrationResult roundtrip', () async {
      final original = (await evaluatePassingSnapshot());
      roundTrip<CicdIntegrationResult>(
        original: original,
        toJson: (r) => r.toJson(),
        fromJson: CicdIntegrationResult.fromJson,
        assertEqual: (r) =>
            expect(r.status, CicdIntegrationResultStatus.success),
      );
    });

    test('policies roundtrip via json', () {
      final pipelineIntegration = PipelineIntegrationPolicyV1.create();
      final pipelineExecution = PipelineExecutionPolicyV1.create();
      final deploymentIntegration = DeploymentIntegrationPolicyV1.create();

      final pipelineIntegrationRestored =
          RegisteredPipelineIntegrationPolicy.fromJson(
              pipelineIntegration.toJson());
      final pipelineExecutionRestored =
          RegisteredPipelineExecutionPolicy.fromJson(
              pipelineExecution.toJson());
      final deploymentIntegrationRestored =
          RegisteredDeploymentIntegrationPolicy.fromJson(
        deploymentIntegration.toJson(),
      );

      expect(
        pipelineIntegrationRestored.metadata.policyId,
        pipelineIntegration.metadata.policyId,
      );
      expect(
        pipelineExecutionRestored.metadata.policyId,
        pipelineExecution.metadata.policyId,
      );
      expect(
        deploymentIntegrationRestored.metadata.policyId,
        deploymentIntegration.metadata.policyId,
      );
    });

    test('enum wire names roundtrip', () {
      for (final status in CicdIntegrationSnapshotStatus.values) {
        expect(
          CicdIntegrationSnapshotStatusX.fromWireName(status.wireName),
          status,
        );
      }
      for (final status in CicdIntegrationResultStatus.values) {
        expect(
          CicdIntegrationResultStatusX.fromWireName(status.wireName),
          status,
        );
      }
      for (final mode in CicdIntegrationSourceResolutionMode.values) {
        expect(
          CicdIntegrationSourceResolutionModeX.fromWireName(mode.wireName),
          mode,
        );
      }
    });

    test('referenceTime uses UTC Z suffix in fixtures', () {
      expect(CicdIntegrationOperationalFixtures.referenceTime.endsWith('Z'),
          isTrue);
    });

    test('unknown enum throws FormatException', () {
      expect(
        () => CicdIntegrationSnapshotStatusX.fromWireName('not-a-status'),
        throwsFormatException,
      );
    });

    test('canonical serializer map ordering is deterministic', () {
      final request = CicdIntegrationOperationalFixtures.passingRequest();
      final json = request.toJson();
      final shuffled = {
        'releaseId': json['releaseId'],
        'projectId': json['projectId'],
        'requestId': json['requestId'],
        ...json,
      };
      expect(
        serializer.normalizeJsonString(shuffled),
        serializer.normalizeJsonString(json),
      );
    });

    test('comparable json roundtrip preserves fingerprint', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final fp = serializer.snapshotFingerprint(snapshot);
      final restored = CicdIntegrationSnapshot.fromJson(snapshot.toJson());
      expect(serializer.snapshotFingerprint(restored), fp);
    });

    test('CicdIntegrationQuery roundtrip', () {
      const query = CicdIntegrationQuery(
        projectId: CicdIntegrationOperationalFixtures.projectId,
        status: CicdIntegrationSnapshotStatus.complete,
        sortDirection: CicdIntegrationQuerySortDirection.descending,
        limit: 10,
        offset: 0,
      );
      roundTrip<CicdIntegrationQuery>(
        original: query,
        toJson: (q) => q.toJson(),
        fromJson: CicdIntegrationQuery.fromJson,
        assertEqual: (r) => expect(r.limit, 10),
      );
    });
  });
}
