import 'package:masterpalm_platform/models/cicd_integration/deployment_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_fingerprint.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_integration_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_validation_result.dart';
import 'package:test/test.dart';

import 'support/pipeline_test_fixtures.dart';

void main() {
  group('CI/CD integration models', () {
    test('pipeline definition roundtrip via json', () {
      final definition = PipelineTestFixtures.validDefinition();
      final restored = PipelineDefinition.fromJson(definition.toJson());
      expect(restored.definitionId, definition.definitionId);
      expect(restored.stages, hasLength(1));
      expect(restored, equals(definition));
    });

    test('pipeline execution roundtrip via json', () {
      final execution = PipelineTestFixtures.validExecution();
      final restored = PipelineExecution.fromJson(execution.toJson());
      expect(restored.executionId, execution.executionId);
      expect(restored.result, isNotNull);
      expect(restored, equals(execution));
    });

    test('pipeline reference roundtrip via json', () {
      final reference = PipelineTestFixtures.validReference();
      final restored = PipelineReference.fromJson(reference.toJson());
      expect(restored.referenceId, reference.referenceId);
      expect(restored, equals(reference));
    });

    test('pipeline capability roundtrip via json', () {
      final capability = PipelineTestFixtures.validCapability();
      final restored = PipelineCapability.fromJson(capability.toJson());
      expect(restored.capabilityId, capability.capabilityId);
      expect(restored, equals(capability));
    });

    test('pipeline metadata roundtrip via json', () {
      final metadata = PipelineTestFixtures.validMetadata();
      final restored = PipelineMetadata.fromJson(metadata.toJson());
      expect(restored.metadataId, metadata.metadataId);
      expect(restored, equals(metadata));
    });

    test('deployment plan roundtrip via json', () {
      final plan = PipelineTestFixtures.validDeploymentPlan();
      final restored = DeploymentPlan.fromJson(plan.toJson());
      expect(restored.planId, plan.planId);
      expect(restored.targets, hasLength(1));
      expect(restored, equals(plan));
    });

    test('deployment result roundtrip via json', () {
      final result = PipelineTestFixtures.validDeploymentResult();
      final restored = DeploymentResult.fromJson(result.toJson());
      expect(restored.resultId, result.resultId);
      expect(restored, equals(result));
    });

    test('validation result roundtrip via json', () {
      const original = PipelineValidationResult(
        isValid: false,
        errors: ['error'],
        warnings: ['warn'],
        issues: [
          PipelineValidationIssue(
            code: 'X',
            path: 'p',
            severity: PipelineValidationSeverity.error,
            message: 'm',
          ),
        ],
      );
      final restored = PipelineValidationResult.fromJson(original.toJson());
      expect(restored, equals(original));
    });

    test('copyWith updates pipeline definition name', () {
      final definition = PipelineTestFixtures.validDefinition();
      final updated = definition.copyWith(name: 'Updated Pipeline');
      expect(updated.name, 'Updated Pipeline');
      expect(definition.name, 'CI Pipeline');
    });

    test('enum wireName roundtrip', () {
      expect(
        PipelineStatus.succeeded,
        PipelineStatusX.fromWireName('succeeded'),
      );
      expect(PipelineProviderType.githubActions.wireName, 'githubActions');
      expect(DeploymentStrategy.rolling.wireName, 'rolling');
      expect(
        DeploymentResultStatus.succeeded.wireName,
        'succeeded',
      );
    });

    test('unknown enum throws FormatException', () {
      expect(
        () => PipelineStatusX.fromWireName('not-a-status'),
        throwsFormatException,
      );
    });

    test('collections are unmodifiable in pipeline definition', () {
      final definition = PipelineDefinition.fromJson(
        PipelineTestFixtures.validDefinition().toJson(),
      );
      expect(
        () => (definition.stages as dynamic).add(definition.stages.first),
        throwsUnsupportedError,
      );
    });

    test('fingerprint is deterministic for comparable json', () {
      final definition = PipelineTestFixtures.validDefinition();
      final fp1 = PipelineFingerprint.fromComparableJson(
        definition.toComparableJson(),
      );
      final fp2 = PipelineFingerprint.fromComparableJson(
        definition.toComparableJson(),
      );
      expect(fp1, fp2);
      expect(fp1, isNotEmpty);
    });

    test('comparable json excludes transient definition fingerprint', () {
      final definition = PipelineTestFixtures.validDefinition();
      final comparable = definition.toComparableJson();
      expect(comparable.containsKey('fingerprint'), isFalse);
    });

    test('validation issue supports equality and hashCode', () {
      const a = PipelineValidationIssue(
        code: 'X',
        path: 'p',
        severity: PipelineValidationSeverity.error,
        message: 'm',
      );
      const b = PipelineValidationIssue(
        code: 'X',
        path: 'p',
        severity: PipelineValidationSeverity.error,
        message: 'm',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
