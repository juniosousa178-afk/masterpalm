import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_enums.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_operation_request.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_operation_result.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_object_reference.dart';
import '../backend/persistent_artifact_environment_gate.dart';
import '../persistent_artifact_backend_registry_impl.dart';
import 'persistent_artifact_cloud_backend_bridge.dart';
import 'persistent_artifact_cloud_capability.dart';
import 'persistent_artifact_cloud_operation_models.dart';
import 'persistent_artifact_cloud_operation_status.dart';
import 'persistent_artifact_cloud_status_mapper.dart';

class PersistentArtifactCloudOperationsService {
  const PersistentArtifactCloudOperationsService({
    required PersistentArtifactBackendRegistry registry,
    this.runtimeEnvironment =
        PersistentArtifactRuntimeEnvironment.localReference,
    this.statusMapper = const PersistentArtifactCloudStatusMapper(),
  }) : _registry = registry;

  final PersistentArtifactBackendRegistry _registry;
  final PersistentArtifactRuntimeEnvironment runtimeEnvironment;
  final PersistentArtifactCloudStatusMapper statusMapper;

  Future<PersistentArtifactCloudObjectMetadataResult> putObject(
    PersistentArtifactCloudOperationRequest request,
  ) {
    return _runObjectOperation(
      request: request.copyWith(operationType: CloudOperationType.putObject),
      capability: PersistentArtifactCloudCapability.putObject,
      execute: (bridge, req) => bridge.putObject(req),
    );
  }

  Future<PersistentArtifactCloudObjectMetadataResult> getObject(
    PersistentArtifactCloudOperationRequest request,
  ) {
    return _runObjectOperation(
      request: request.copyWith(operationType: CloudOperationType.getObject),
      capability: PersistentArtifactCloudCapability.getObject,
      execute: (bridge, req) => bridge.getObject(req),
    );
  }

  Future<PersistentArtifactCloudObjectMetadataResult> headObject(
    PersistentArtifactCloudOperationRequest request,
  ) {
    return _runObjectOperation(
      request: request.copyWith(operationType: CloudOperationType.headObject),
      capability: PersistentArtifactCloudCapability.headObject,
      execute: (bridge, req) => bridge.headObject(req),
    );
  }

  Future<PersistentArtifactCloudObjectMetadataResult> objectExists(
    PersistentArtifactCloudOperationRequest request,
  ) async {
    final correlationId = _correlationId(
      operation: 'objectExists',
      backendId: request.backendId,
    );
    final resolution = _registry.resolveCloudBackendForOperation(
      request.backendId,
      PersistentArtifactCloudCapability.objectExists,
    );
    if (!resolution.resolved) {
      return _unavailableObjectResult(
        request: request,
        correlationId: correlationId,
        status: resolution.status,
      );
    }
    final environment = _registry.evaluateCloudEnvironment(
      request.backendId,
      runtimeEnvironment,
    );
    if (!environment.allowed) {
      return _unavailableObjectResult(
        request: request,
        correlationId: correlationId,
        status: environment.status,
      );
    }
    final bridge = _registry.cloudBridgeOf(request.backendId);
    if (bridge == null) {
      return _unavailableObjectResult(
        request: request,
        correlationId: correlationId,
        status: PersistentArtifactCloudOperationStatus.unavailable,
      );
    }
    try {
      final exists = await bridge.objectExists(request);
      return PersistentArtifactCloudObjectMetadataResult(
        status: PersistentArtifactCloudOperationStatus.success,
        backendId: request.backendId,
        operation: CloudOperationType.headObject,
        correlationId: correlationId,
        objectReference: request.objectReference,
        exists: exists,
      );
    } catch (_) {
      return _unavailableObjectResult(
        request: request,
        correlationId: correlationId,
        status: PersistentArtifactCloudOperationStatus.failed,
      );
    }
  }

  Future<PersistentArtifactCloudObjectListResult> listObjects(
    PersistentArtifactCloudOperationRequest request,
  ) async {
    final correlationId = _correlationId(
      operation: 'listObjects',
      backendId: request.backendId,
    );
    final resolution = _registry.resolveCloudBackendForOperation(
      request.backendId,
      PersistentArtifactCloudCapability.listObjects,
    );
    if (!resolution.resolved) {
      return PersistentArtifactCloudObjectListResult(
        status: resolution.status,
        backendId: request.backendId,
        correlationId: correlationId,
      );
    }
    final environment = _registry.evaluateCloudEnvironment(
      request.backendId,
      runtimeEnvironment,
    );
    if (!environment.allowed) {
      return PersistentArtifactCloudObjectListResult(
        status: environment.status,
        backendId: request.backendId,
        correlationId: correlationId,
      );
    }
    final bridge = _registry.cloudBridgeOf(request.backendId);
    if (bridge == null) {
      return PersistentArtifactCloudObjectListResult(
        status: PersistentArtifactCloudOperationStatus.unavailable,
        backendId: request.backendId,
        correlationId: correlationId,
      );
    }
    try {
      final bridgeResults = await bridge.listObjects(
        request.copyWith(operationType: CloudOperationType.listObjects),
      );
      final objects = bridgeResults
          .map((it) => it.objectReference)
          .whereType<PersistentArtifactCloudObjectReference>()
          .toList(growable: false);
      final mapped = bridgeResults.isEmpty
          ? PersistentArtifactCloudOperationStatus.success
          : statusMapper.fromBridgeResult(bridgeResults.last);
      return PersistentArtifactCloudObjectListResult(
        status: mapped,
        backendId: request.backendId,
        correlationId: correlationId,
        objects: List.unmodifiable(objects),
        truncated: bridgeResults.length > 1,
        messages: List.unmodifiable(
          bridgeResults
              .expand((it) => it.issues)
              .map(PersistentArtifactCloudExecutionMessage.fromIssue),
        ),
      );
    } catch (_) {
      return PersistentArtifactCloudObjectListResult(
        status: PersistentArtifactCloudOperationStatus.failed,
        backendId: request.backendId,
        correlationId: correlationId,
      );
    }
  }

  Future<PersistentArtifactCloudObjectMetadataResult> deleteObject(
    PersistentArtifactCloudOperationRequest request,
  ) {
    return _runObjectOperation(
      request: request.copyWith(operationType: CloudOperationType.deleteObject),
      capability: PersistentArtifactCloudCapability.deleteObject,
      execute: (bridge, req) => bridge.deleteObject(req),
    );
  }

  Future<PersistentArtifactCloudObjectMetadataResult> copyObject(
    PersistentArtifactCloudOperationRequest request,
  ) {
    return _runObjectOperation(
      request: request.copyWith(operationType: CloudOperationType.copyObject),
      capability: PersistentArtifactCloudCapability.copyObject,
      execute: (bridge, req) => bridge.copyObject(req),
    );
  }

  Future<PersistentArtifactCloudMultipartOperationResult> beginMultipart(
    PersistentArtifactCloudOperationRequest request,
  ) {
    return _runMultipartOperation(
      request:
          request.copyWith(operationType: CloudOperationType.beginMultipart),
      capability: PersistentArtifactCloudCapability.beginMultipart,
      execute: (bridge, req) => bridge.beginMultipart(req),
    );
  }

  Future<PersistentArtifactCloudMultipartOperationResult> uploadPart(
    PersistentArtifactCloudOperationRequest request,
  ) {
    return _runMultipartOperation(
      request: request.copyWith(operationType: CloudOperationType.uploadPart),
      capability: PersistentArtifactCloudCapability.uploadPart,
      execute: (bridge, req) => bridge.uploadPart(req),
    );
  }

  Future<PersistentArtifactCloudMultipartOperationResult> completeMultipart(
    PersistentArtifactCloudOperationRequest request,
  ) {
    return _runMultipartOperation(
      request:
          request.copyWith(operationType: CloudOperationType.completeMultipart),
      capability: PersistentArtifactCloudCapability.completeMultipart,
      execute: (bridge, req) => bridge.completeMultipart(req),
    );
  }

  Future<PersistentArtifactCloudMultipartOperationResult> abortMultipart(
    PersistentArtifactCloudOperationRequest request,
  ) {
    return _runMultipartOperation(
      request:
          request.copyWith(operationType: CloudOperationType.abortMultipart),
      capability: PersistentArtifactCloudCapability.abortMultipart,
      execute: (bridge, req) => bridge.abortMultipart(req),
    );
  }

  Future<PersistentArtifactCloudObjectMetadataResult> _runObjectOperation({
    required PersistentArtifactCloudOperationRequest request,
    required PersistentArtifactCloudCapability capability,
    required Future<PersistentArtifactCloudOperationResult> Function(
      PersistentArtifactCloudBackendBridge bridge,
      PersistentArtifactCloudOperationRequest request,
    ) execute,
  }) async {
    final correlationId = _correlationId(
      operation: request.operationType.wireName,
      backendId: request.backendId,
    );
    final resolution = _registry.resolveCloudBackendForOperation(
      request.backendId,
      capability,
    );
    if (!resolution.resolved) {
      return _unavailableObjectResult(
        request: request,
        correlationId: correlationId,
        status: resolution.status,
      );
    }
    final environment = _registry.evaluateCloudEnvironment(
      request.backendId,
      runtimeEnvironment,
    );
    if (!environment.allowed) {
      return _unavailableObjectResult(
        request: request,
        correlationId: correlationId,
        status: environment.status,
      );
    }
    final bridge = _registry.cloudBridgeOf(request.backendId);
    if (bridge == null) {
      return _unavailableObjectResult(
        request: request,
        correlationId: correlationId,
        status: PersistentArtifactCloudOperationStatus.unavailable,
      );
    }
    try {
      final result = await execute(bridge, request);
      return PersistentArtifactCloudObjectMetadataResult(
        status: statusMapper.fromBridgeResult(result),
        backendId: request.backendId,
        operation: request.operationType,
        correlationId: correlationId,
        objectReference: result.objectReference,
        versionReference: result.versionReference,
        messages: List.unmodifiable(
          result.issues.map(PersistentArtifactCloudExecutionMessage.fromIssue),
        ),
        metadata: {'bridgeStatus': result.status.wireName},
      );
    } catch (_) {
      return _unavailableObjectResult(
        request: request,
        correlationId: correlationId,
        status: PersistentArtifactCloudOperationStatus.failed,
      );
    }
  }

  Future<PersistentArtifactCloudMultipartOperationResult>
      _runMultipartOperation({
    required PersistentArtifactCloudOperationRequest request,
    required PersistentArtifactCloudCapability capability,
    required Future<PersistentArtifactCloudOperationResult> Function(
      PersistentArtifactCloudBackendBridge bridge,
      PersistentArtifactCloudOperationRequest request,
    ) execute,
  }) async {
    final correlationId = _correlationId(
      operation: request.operationType.wireName,
      backendId: request.backendId,
    );
    final resolution = _registry.resolveCloudBackendForOperation(
      request.backendId,
      capability,
    );
    if (!resolution.resolved) {
      return PersistentArtifactCloudMultipartOperationResult(
        status: resolution.status,
        backendId: request.backendId,
        operation: request.operationType,
        correlationId: correlationId,
      );
    }
    final environment = _registry.evaluateCloudEnvironment(
      request.backendId,
      runtimeEnvironment,
    );
    if (!environment.allowed) {
      return PersistentArtifactCloudMultipartOperationResult(
        status: environment.status,
        backendId: request.backendId,
        operation: request.operationType,
        correlationId: correlationId,
      );
    }
    final bridge = _registry.cloudBridgeOf(request.backendId);
    if (bridge == null) {
      return PersistentArtifactCloudMultipartOperationResult(
        status: PersistentArtifactCloudOperationStatus.unavailable,
        backendId: request.backendId,
        operation: request.operationType,
        correlationId: correlationId,
      );
    }
    try {
      final result = await execute(bridge, request);
      return PersistentArtifactCloudMultipartOperationResult(
        status: statusMapper.fromBridgeResult(result),
        backendId: request.backendId,
        operation: request.operationType,
        correlationId: correlationId,
        multipartUpload: request.multipartUpload,
        messages: List.unmodifiable(
          result.issues.map(PersistentArtifactCloudExecutionMessage.fromIssue),
        ),
        metadata: {'bridgeStatus': result.status.wireName},
      );
    } catch (_) {
      return PersistentArtifactCloudMultipartOperationResult(
        status: PersistentArtifactCloudOperationStatus.failed,
        backendId: request.backendId,
        operation: request.operationType,
        correlationId: correlationId,
      );
    }
  }

  PersistentArtifactCloudObjectMetadataResult _unavailableObjectResult({
    required PersistentArtifactCloudOperationRequest request,
    required String correlationId,
    required PersistentArtifactCloudOperationStatus status,
  }) {
    return PersistentArtifactCloudObjectMetadataResult(
      status: status,
      backendId: request.backendId,
      operation: request.operationType,
      correlationId: correlationId,
      objectReference: request.objectReference,
    );
  }

  String _correlationId({
    required String operation,
    required String backendId,
  }) {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'pa-cloud:$operation:$backendId:$now';
  }
}
