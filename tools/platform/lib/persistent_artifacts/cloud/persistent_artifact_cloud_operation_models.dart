import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_enums.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_issue.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_multipart_models.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_object_reference.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_object_version_reference.dart';
import '../backend/persistent_artifact_environment_gate.dart';
import 'persistent_artifact_cloud_bridge_classification.dart';
import 'persistent_artifact_cloud_capability.dart';
import 'persistent_artifact_cloud_operation_status.dart';

class PersistentArtifactCloudExecutionMessage {
  const PersistentArtifactCloudExecutionMessage({
    required this.code,
    required this.message,
    this.severity = 'info',
    this.metadata = const {},
  });

  final String code;
  final String message;
  final String severity;
  final Map<String, String> metadata;

  factory PersistentArtifactCloudExecutionMessage.fromIssue(
    PersistentArtifactCloudIssue issue,
  ) {
    return PersistentArtifactCloudExecutionMessage(
      code: issue.code,
      message: issue.message,
      severity: issue.severity.wireName,
      metadata: issue.metadata,
    );
  }
}

class PersistentArtifactCloudOperationContext {
  const PersistentArtifactCloudOperationContext({
    required this.backendId,
    required this.operation,
    required this.capability,
    required this.runtimeEnvironment,
    required this.correlationId,
    required this.requestId,
    this.classification =
        PersistentArtifactCloudBridgeClassification.offlineSimulation,
    this.metadata = const {},
  });

  final String backendId;
  final CloudOperationType operation;
  final PersistentArtifactCloudCapability capability;
  final PersistentArtifactRuntimeEnvironment runtimeEnvironment;
  final String correlationId;
  final String requestId;
  final PersistentArtifactCloudBridgeClassification classification;
  final Map<String, String> metadata;
}

class PersistentArtifactCloudCapabilityDecision {
  const PersistentArtifactCloudCapabilityDecision({
    required this.backendId,
    required this.capability,
    required this.allowed,
    required this.status,
    this.reasonCode,
    this.messages = const [],
    this.metadata = const {},
  });

  final String backendId;
  final PersistentArtifactCloudCapability capability;
  final bool allowed;
  final PersistentArtifactCloudOperationStatus status;
  final String? reasonCode;
  final List<PersistentArtifactCloudExecutionMessage> messages;
  final Map<String, String> metadata;
}

class PersistentArtifactCloudBackendConflict {
  const PersistentArtifactCloudBackendConflict({
    required this.backendId,
    required this.code,
    required this.message,
    this.metadata = const {},
  });

  final String backendId;
  final String code;
  final String message;
  final Map<String, String> metadata;
}

class PersistentArtifactCloudBackendResolution {
  const PersistentArtifactCloudBackendResolution({
    required this.backendId,
    required this.resolved,
    required this.status,
    this.classification =
        PersistentArtifactCloudBridgeClassification.offlineSimulation,
    this.conflict,
    this.metadata = const {},
  });

  final String backendId;
  final bool resolved;
  final PersistentArtifactCloudOperationStatus status;
  final PersistentArtifactCloudBridgeClassification classification;
  final PersistentArtifactCloudBackendConflict? conflict;
  final Map<String, String> metadata;
}

class PersistentArtifactCloudEnvironmentDecision {
  const PersistentArtifactCloudEnvironmentDecision({
    required this.backendId,
    required this.runtimeEnvironment,
    required this.allowed,
    required this.status,
    this.reasonCode,
    this.message,
    this.classification =
        PersistentArtifactCloudBridgeClassification.offlineSimulation,
    this.metadata = const {},
  });

  final String backendId;
  final PersistentArtifactRuntimeEnvironment runtimeEnvironment;
  final bool allowed;
  final PersistentArtifactCloudOperationStatus status;
  final String? reasonCode;
  final String? message;
  final PersistentArtifactCloudBridgeClassification classification;
  final Map<String, String> metadata;
}

class PersistentArtifactCloudExecutionPlan {
  const PersistentArtifactCloudExecutionPlan({
    required this.context,
    required this.environmentDecision,
    required this.capabilityDecision,
    required this.backendResolution,
    required this.bridgeCallAllowed,
    this.messages = const [],
  });

  final PersistentArtifactCloudOperationContext context;
  final PersistentArtifactCloudEnvironmentDecision environmentDecision;
  final PersistentArtifactCloudCapabilityDecision capabilityDecision;
  final PersistentArtifactCloudBackendResolution backendResolution;
  final bool bridgeCallAllowed;
  final List<PersistentArtifactCloudExecutionMessage> messages;
}

class PersistentArtifactCloudObjectMetadataResult {
  const PersistentArtifactCloudObjectMetadataResult({
    required this.status,
    required this.backendId,
    required this.operation,
    required this.correlationId,
    this.objectReference,
    this.versionReference,
    this.exists,
    this.messages = const [],
    this.metadata = const {},
  });

  final PersistentArtifactCloudOperationStatus status;
  final String backendId;
  final CloudOperationType operation;
  final String correlationId;
  final PersistentArtifactCloudObjectReference? objectReference;
  final PersistentArtifactCloudObjectVersionReference? versionReference;
  final bool? exists;
  final List<PersistentArtifactCloudExecutionMessage> messages;
  final Map<String, String> metadata;
}

class PersistentArtifactCloudObjectListResult {
  const PersistentArtifactCloudObjectListResult({
    required this.status,
    required this.backendId,
    required this.correlationId,
    this.objects = const [],
    this.nextToken,
    this.truncated = false,
    this.messages = const [],
    this.metadata = const {},
  });

  final PersistentArtifactCloudOperationStatus status;
  final String backendId;
  final String correlationId;
  final List<PersistentArtifactCloudObjectReference> objects;
  final String? nextToken;
  final bool truncated;
  final List<PersistentArtifactCloudExecutionMessage> messages;
  final Map<String, String> metadata;
}

class PersistentArtifactCloudMultipartOperationResult {
  const PersistentArtifactCloudMultipartOperationResult({
    required this.status,
    required this.backendId,
    required this.operation,
    required this.correlationId,
    this.multipartUpload,
    this.messages = const [],
    this.metadata = const {},
  });

  final PersistentArtifactCloudOperationStatus status;
  final String backendId;
  final CloudOperationType operation;
  final String correlationId;
  final PersistentArtifactCloudMultipartUpload? multipartUpload;
  final List<PersistentArtifactCloudExecutionMessage> messages;
  final Map<String, String> metadata;
}
