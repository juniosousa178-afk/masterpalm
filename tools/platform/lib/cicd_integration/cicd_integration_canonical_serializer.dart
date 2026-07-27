import 'dart:convert';

import '../models/cicd_integration/cicd_integration_messages.dart';
import '../models/cicd_integration/cicd_integration_policy_models.dart';
import '../models/cicd_integration/cicd_integration_request.dart';
import '../models/cicd_integration/cicd_integration_snapshot.dart';
import '../models/cicd_integration/deployment_models.dart';
import '../models/cicd_integration/pipeline_fingerprint.dart';
import '../models/cicd_integration/pipeline_models.dart';

/// Canonical serialization and fingerprinting for CI/CD integration.
class CicdIntegrationCanonicalSerializer {
  const CicdIntegrationCanonicalSerializer();

  static const String version = 'cicd-integration-canonical-v1';

  String fingerprintFromString(String value) {
    return PipelineFingerprint.fromComparableJson({'value': value});
  }

  String pipelineIntegrationPolicyFingerprint(
    RegisteredPipelineIntegrationPolicy policy,
  ) {
    return PipelineFingerprint.fromComparableJson(policy.toComparableJson());
  }

  String pipelineExecutionPolicyFingerprint(
    RegisteredPipelineExecutionPolicy policy,
  ) {
    return PipelineFingerprint.fromComparableJson(policy.toComparableJson());
  }

  String deploymentIntegrationPolicyFingerprint(
    RegisteredDeploymentIntegrationPolicy policy,
  ) {
    return PipelineFingerprint.fromComparableJson(policy.toComparableJson());
  }

  String requestFingerprint(CicdIntegrationRequest request) {
    return PipelineFingerprint.fromComparableJson(request.toJson());
  }

  String snapshotFingerprint(CicdIntegrationSnapshot snapshot) {
    return PipelineFingerprint.fromComparableJson(snapshot.toComparableJson());
  }

  String pipelineDefinitionFingerprint(PipelineDefinition definition) {
    return PipelineFingerprint.fromComparableJson(
        definition.toComparableJson());
  }

  String pipelineExecutionFingerprint(PipelineExecution execution) {
    return PipelineFingerprint.fromComparableJson(execution.toComparableJson());
  }

  String pipelineExecutionResultFingerprint(PipelineExecutionResult result) {
    return PipelineFingerprint.fromComparableJson(result.toComparableJson());
  }

  String deploymentPlanFingerprint(DeploymentPlan plan) {
    return PipelineFingerprint.fromComparableJson(plan.toComparableJson());
  }

  String deploymentResultFingerprint(DeploymentResult result) {
    return PipelineFingerprint.fromComparableJson(result.toComparableJson());
  }

  String sourceReferencesFingerprint(
    List<CicdIntegrationSourceReference> references,
  ) {
    final refs = references.map((r) => r.toComparableJson()).toList()
      ..sort(
        (a, b) =>
            (a['sourceType'] as String).compareTo(b['sourceType'] as String),
      );
    return PipelineFingerprint.fromComparableJson({'references': refs});
  }

  String normalizeJsonString(Map<String, dynamic> input) {
    return jsonEncode(_normalizeJson(input));
  }

  Map<String, dynamic> _normalizeJson(Map<String, dynamic> input) {
    final output = <String, dynamic>{};
    final keys = input.keys.toList()..sort();
    for (final key in keys) {
      output[key] = _normalizeValue(input[key]);
    }
    return output;
  }

  dynamic _normalizeValue(dynamic value) {
    if (value is Map) {
      return _normalizeJson(value.map((k, v) => MapEntry(k.toString(), v)));
    }
    if (value is List) {
      return value.map(_normalizeValue).toList();
    }
    if (value is double) {
      if (value.isNaN || value.isInfinite) {
        throw FormatException('Non-finite value in canonicalization');
      }
      if (value == -0.0) return 0.0;
      return value;
    }
    return value;
  }
}
