import 'package:masterpalm_platform/cicd_integration/deployment_validator.dart';
import 'package:masterpalm_platform/cicd_integration/execution_validator.dart';
import 'package:masterpalm_platform/cicd_integration/pipeline_validator.dart';
import 'package:masterpalm_platform/models/cicd_integration/deployment_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_validation_result.dart';
import 'package:test/test.dart';

import 'support/pipeline_test_fixtures.dart';

void main() {
  group('CI/CD integration validators', () {
    test('pipeline validator accepts valid definition', () {
      final result = const PipelineValidator().validate(
        PipelineTestFixtures.validDefinition(),
      );
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('pipeline validator rejects empty definitionId', () {
      final definition =
          PipelineTestFixtures.validDefinition().copyWith(definitionId: '');
      final result = const PipelineValidator().validate(definition);
      expect(result.isValid, isFalse);
      expect(result.errors, isNotEmpty);
    });

    test('pipeline validator rejects duplicate stageId', () {
      final stage = PipelineTestFixtures.validBuildStage();
      final definition = PipelineTestFixtures.validDefinition().copyWith(
        stages: [stage, stage],
      );
      final result = const PipelineValidator().validate(definition);
      expect(result.isValid, isFalse);
    });

    test('pipeline validator rejects duplicate stepId', () {
      final step = PipelineTestFixtures.validBuildStep();
      final stage = PipelineTestFixtures.validBuildStage().copyWith(
        steps: [step, step],
      );
      final definition = PipelineTestFixtures.validDefinition().copyWith(
        stages: [stage],
      );
      final result = const PipelineValidator().validate(definition);
      expect(result.isValid, isFalse);
    });

    test('pipeline validator rejects invalid version', () {
      final definition =
          PipelineTestFixtures.validDefinition().copyWith(version: 0);
      final result = const PipelineValidator().validate(definition);
      expect(result.isValid, isFalse);
    });

    test('deployment validator accepts valid plan', () {
      final result = const DeploymentValidator().validatePlan(
        PipelineTestFixtures.validDeploymentPlan(),
      );
      expect(result.isValid, isTrue);
    });

    test('deployment validator rejects empty planId', () {
      final plan =
          PipelineTestFixtures.validDeploymentPlan().copyWith(planId: '');
      final result = const DeploymentValidator().validatePlan(plan);
      expect(result.isValid, isFalse);
    });

    test('deployment validator rejects invalid deployment window', () {
      final window = PipelineTestFixtures.validDeploymentWindow().copyWith(
        startAt: '2026-07-22T18:00:00.000Z',
        endAt: '2026-07-22T10:00:00.000Z',
      );
      final plan = PipelineTestFixtures.validDeploymentPlan().copyWith(
        windows: [window],
      );
      final result = const DeploymentValidator().validatePlan(plan);
      expect(result.isValid, isFalse);
    });

    test('deployment validator rejects empty target uri', () {
      final target =
          PipelineTestFixtures.validDeploymentTarget().copyWith(uri: '');
      final plan = PipelineTestFixtures.validDeploymentPlan().copyWith(
        targets: [target],
      );
      final result = const DeploymentValidator().validatePlan(plan);
      expect(result.isValid, isFalse);
    });

    test('deployment validator accepts valid result', () {
      final result = const DeploymentValidator().validateResult(
        PipelineTestFixtures.validDeploymentResult(),
      );
      expect(result.isValid, isTrue);
    });

    test('deployment validator rejects terminal result without completedAt',
        () {
      final depResult = DeploymentResult(
        resultId: 'dep-result-001',
        planId: 'plan-001',
        status: DeploymentResultStatus.succeeded,
        startedAt: PipelineTestFixtures.referenceTime,
      );
      final result = const DeploymentValidator().validateResult(depResult);
      expect(result.isValid, isFalse);
    });

    test('execution validator accepts valid execution', () {
      final result = const ExecutionValidator().validate(
        PipelineTestFixtures.validExecution(),
      );
      expect(result.isValid, isTrue);
    });

    test('execution validator rejects empty executionId', () {
      final execution =
          PipelineTestFixtures.validExecution().copyWith(executionId: '');
      final result = const ExecutionValidator().validate(execution);
      expect(result.isValid, isFalse);
    });

    test('execution validator rejects terminal status without completedAt', () {
      final execution = PipelineExecution(
        executionId: 'exec-001',
        definitionId: 'def-ci-001',
        status: PipelineStatus.succeeded,
        startedAt: PipelineTestFixtures.referenceTime,
      );
      final result = const ExecutionValidator().validate(execution);
      expect(result.isValid, isFalse);
    });

    test('execution validator rejects mismatched result status', () {
      final execution = PipelineTestFixtures.validExecution().copyWith(
        result: PipelineTestFixtures.validExecutionResult().copyWith(
          status: PipelineStatus.failed,
        ),
      );
      final result = const ExecutionValidator().validate(execution);
      expect(result.isValid, isFalse);
    });

    test('execution validator rejects success outcome with failed status', () {
      final execution = PipelineTestFixtures.validExecution().copyWith(
        status: PipelineStatus.failed,
        result: PipelineTestFixtures.validExecutionResult().copyWith(
          status: PipelineStatus.failed,
          outcome: PipelineExecutionOutcome.success,
        ),
      );
      final result = const ExecutionValidator().validate(execution);
      expect(result.isValid, isFalse);
    });

    test('validation result roundtrip via json', () {
      final original = PipelineValidationResult(
        isValid: false,
        errors: const ['error'],
        warnings: const ['warn'],
        issues: const [
          PipelineValidationIssue(
            code: 'CICD_TEST',
            path: 'test',
            severity: PipelineValidationSeverity.critical,
            message: 'test issue',
          ),
        ],
      );
      final restored = PipelineValidationResult.fromJson(original.toJson());
      expect(restored, equals(original));
    });
  });
}
