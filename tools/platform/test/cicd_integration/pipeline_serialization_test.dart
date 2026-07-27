import 'package:masterpalm_platform/models/cicd_integration/deployment_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_fingerprint.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_integration_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_validation_result.dart';
import 'package:test/test.dart';

import 'support/pipeline_test_fixtures.dart';

void main() {
  group('CI/CD integration serialization audit', () {
    final aggregates = <String, dynamic Function()>{
      'PipelineDefinition': () =>
          PipelineTestFixtures.validDefinition().toJson(),
      'PipelineExecution': () => PipelineTestFixtures.validExecution().toJson(),
      'PipelineReference': () => PipelineTestFixtures.validReference().toJson(),
      'PipelineCapability': () =>
          PipelineTestFixtures.validCapability().toJson(),
      'PipelineMetadata': () => PipelineTestFixtures.validMetadata().toJson(),
      'DeploymentPlan': () =>
          PipelineTestFixtures.validDeploymentPlan().toJson(),
      'DeploymentResult': () =>
          PipelineTestFixtures.validDeploymentResult().toJson(),
      'PipelineValidationResult': () => const PipelineValidationResult(
            isValid: true,
            warnings: ['ok'],
          ).toJson(),
    };

    for (final entry in aggregates.entries) {
      test('${entry.key} json keys are non-empty', () {
        final json = entry.value() as Map<String, dynamic>;
        expect(json.keys, isNotEmpty);
      });
    }

    test('fingerprint stable across repeated comparable serialization', () {
      final definition = PipelineTestFixtures.validDefinition();
      final fps = List.generate(
        5,
        (_) => PipelineFingerprint.fromComparableJson(
          definition.toComparableJson(),
        ),
      );
      expect(fps.toSet(), hasLength(1));
    });

    test('all pipeline enums expose wireName and fromWireName', () {
      void assertEnum<T extends Enum>(
        List<T> values,
        String Function(T) wireName,
        T Function(String) fromWireName,
      ) {
        for (final value in values) {
          expect(fromWireName(wireName(value)), value);
        }
      }

      assertEnum(
        PipelineStatus.values,
        (e) => e.wireName,
        PipelineStatusX.fromWireName,
      );
      assertEnum(
        PipelineStepType.values,
        (e) => e.wireName,
        PipelineStepTypeX.fromWireName,
      );
      assertEnum(
        PipelineStageType.values,
        (e) => e.wireName,
        PipelineStageTypeX.fromWireName,
      );
      assertEnum(
        PipelineTriggerType.values,
        (e) => e.wireName,
        PipelineTriggerTypeX.fromWireName,
      );
      assertEnum(
        PipelineArtifactType.values,
        (e) => e.wireName,
        PipelineArtifactTypeX.fromWireName,
      );
      assertEnum(
        PipelineEnvironmentType.values,
        (e) => e.wireName,
        PipelineEnvironmentTypeX.fromWireName,
      );
      assertEnum(
        PipelineProviderType.values,
        (e) => e.wireName,
        PipelineProviderTypeX.fromWireName,
      );
      assertEnum(
        PipelineCapabilityType.values,
        (e) => e.wireName,
        PipelineCapabilityTypeX.fromWireName,
      );
      assertEnum(
        DeploymentStrategy.values,
        (e) => e.wireName,
        DeploymentStrategyX.fromWireName,
      );
      assertEnum(
        DeploymentApprovalStatus.values,
        (e) => e.wireName,
        DeploymentApprovalStatusX.fromWireName,
      );
      assertEnum(
        DeploymentResultStatus.values,
        (e) => e.wireName,
        DeploymentResultStatusX.fromWireName,
      );
      assertEnum(
        DeploymentTargetType.values,
        (e) => e.wireName,
        DeploymentTargetTypeX.fromWireName,
      );
      assertEnum(
        PipelineValidationSeverity.values,
        (e) => e.wireName,
        PipelineValidationSeverityX.fromWireName,
      );
      assertEnum(
        PipelineExecutionOutcome.values,
        (e) => e.wireName,
        PipelineExecutionOutcomeX.fromWireName,
      );
      assertEnum(
        PipelineStepStatus.values,
        (e) => e.wireName,
        PipelineStepStatusX.fromWireName,
      );
    });

    test('nested models roundtrip through json', () {
      final step = PipelineTestFixtures.validBuildStep();
      expect(PipelineStep.fromJson(step.toJson()), equals(step));

      final stage = PipelineTestFixtures.validBuildStage();
      expect(PipelineStage.fromJson(stage.toJson()), equals(stage));

      final target = PipelineTestFixtures.validDeploymentTarget();
      expect(DeploymentTarget.fromJson(target.toJson()), equals(target));

      final window = PipelineTestFixtures.validDeploymentWindow();
      expect(DeploymentWindow.fromJson(window.toJson()), equals(window));
    });

    test('comparable json sorts nested collections deterministically', () {
      final definition = PipelineTestFixtures.validDefinition().copyWith(
        metadata: {'z': 'last', 'a': 'first'},
      );
      final comparable = definition.toComparableJson();
      final metadata = comparable['metadata'] as Map<String, dynamic>;
      expect(metadata.keys.toList(), ['a', 'z']);
    });
  });
}
