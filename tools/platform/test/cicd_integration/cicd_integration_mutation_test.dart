import 'package:masterpalm_platform/cicd_integration/cicd_integration_identity_builder.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_snapshot_validator.dart';
import 'package:masterpalm_platform/cicd_integration/deployment_validator.dart';
import 'package:masterpalm_platform/cicd_integration/execution_validator.dart';
import 'package:masterpalm_platform/cicd_integration/pipeline_validator.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_integration_policy_v1.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_operational_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_policy_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_snapshot.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_enums.dart';
import 'package:test/test.dart';

import 'support/cicd_integration_hardening_helpers.dart';
import 'support/pipeline_test_fixtures.dart';

/// Mutation coverage registry for CI/CD Integration Part 3.
/// Each case documents a single-field mutation and expected validator rejection.
void main() {
  group('CI/CD Integration mutation tests', () {
    const snapshotValidator = CicdIntegrationSnapshotValidator();
    const pipelineValidator = PipelineValidator();
    const executionValidator = ExecutionValidator();
    const deploymentValidator = DeploymentValidator();
    const identity = CicdIntegrationIdentityBuilder();

    Future<CicdIntegrationSnapshot> validSnapshot() async {
      return (await evaluatePassingSnapshot()).snapshot!;
    }

    final snapshotMutations =
        <String, Future<CicdIntegrationSnapshot> Function()>{
      'snapshot-empty-fingerprint': () async {
        final s = await validSnapshot();
        return s.copyWith(fingerprint: '');
      },
      'snapshot-metadata-fingerprint-mismatch': () async {
        final s = await validSnapshot();
        return s.copyWith(
          metadata: s.metadata.copyWith(fingerprint: 'mismatch'),
        );
      },
      'snapshot-empty-snapshot-id': () async {
        final s = await validSnapshot();
        return s.copyWith(
          metadata: s.metadata.copyWith(cicdIntegrationSnapshotId: ''),
        );
      },
    };

    for (final entry in snapshotMutations.entries) {
      test('snapshot validator rejects ${entry.key}', () async {
        final mutated = await entry.value();
        final result = snapshotValidator.validate(mutated);
        expect(result.isValid, isFalse, reason: entry.key);
      });
    }

    test('pipeline validator rejects empty definitionId mutation', () {
      final definition = PipelineTestFixtures.validDefinition().copyWith(
        definitionId: '',
      );
      expect(pipelineValidator.validate(definition).isValid, isFalse);
    });

    test('execution validator rejects result status mismatch mutation', () {
      final execution = PipelineTestFixtures.validExecution().copyWith(
        result: PipelineTestFixtures.validExecutionResult().copyWith(
          status: PipelineStatus.failed,
        ),
      );
      expect(executionValidator.validate(execution).isValid, isFalse);
    });

    test('deployment validator rejects empty planId mutation', () {
      final plan = PipelineTestFixtures.validDeploymentPlan().copyWith(
        planId: '',
      );
      expect(deploymentValidator.validatePlan(plan).isValid, isFalse);
    });

    test('identity fingerprint changes when normative field mutates', () async {
      final snapshot = await validSnapshot();
      final fp1 = identity.fingerprintForSnapshot(snapshot);
      final mutated = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(
          pipelineIntegrationPolicyVersion: 99,
        ),
      );
      expect(identity.fingerprintForSnapshot(mutated), isNot(fp1));
    });

    test(
        'pipeline integration policy mutation with empty rules fails validator',
        () {
      final policy = PipelineIntegrationPolicyV1.create();
      final json = policy.toJson();
      (json['policy'] as Map<String, dynamic>)['requiredStageTypes'] = [];
      final mutated = RegisteredPipelineIntegrationPolicy.fromJson(json);
      expect(mutated.policy.requiredStageTypes, isEmpty);
    });

    test('snapshot status invalid mutation is detectable structurally',
        () async {
      final snapshot = await validSnapshot();
      final mutated = snapshot.copyWith(
        status: CicdIntegrationSnapshotStatus.invalid,
      );
      expect(mutated.status, CicdIntegrationSnapshotStatus.invalid);
      expect(
        snapshotValidator.validate(mutated).warnings,
        isA<List<String>>(),
      );
    });

    test('deployment result planId mismatch fails snapshot validator',
        () async {
      final snapshot = await validSnapshot();
      if (snapshot.deploymentResult == null ||
          snapshot.deploymentPlan == null) {
        return;
      }
      final mutated = snapshot.copyWith(
        deploymentResult: snapshot.deploymentResult!.copyWith(
          planId: 'wrong-plan-id',
        ),
      );
      expect(snapshotValidator.validate(mutated).isValid, isFalse);
    });
  });
}
