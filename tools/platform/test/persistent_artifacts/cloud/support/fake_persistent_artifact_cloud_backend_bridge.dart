import 'package:masterpalm_platform/masterpalm_platform.dart';

import 'cloud_test_fixtures.dart';

class FakePersistentArtifactCloudBackendBridge
    implements PersistentArtifactCloudBackendBridge {
  FakePersistentArtifactCloudBackendBridge({
    PersistentArtifactCloudBackendDescriptor? descriptor,
    Set<PersistentArtifactCloudCapability>? capabilities,
    Map<CloudOperationType, CloudOperationStatus>? forcedStatuses,
    Map<CloudOperationType, Object>? injectedFailures,
    this.classification =
        PersistentArtifactCloudBridgeClassification.offlineSimulation,
  })  : _descriptor = descriptor ?? CloudTestFixtures.backendDescriptor(),
        _capabilities = capabilities ??
            {
              PersistentArtifactCloudCapability.describe,
              PersistentArtifactCloudCapability.evaluateEnvironment,
              PersistentArtifactCloudCapability.evaluateCapabilities,
              PersistentArtifactCloudCapability.putObject,
              PersistentArtifactCloudCapability.getObject,
              PersistentArtifactCloudCapability.headObject,
              PersistentArtifactCloudCapability.objectExists,
              PersistentArtifactCloudCapability.listObjects,
              PersistentArtifactCloudCapability.deleteObject,
              PersistentArtifactCloudCapability.copyObject,
              PersistentArtifactCloudCapability.beginMultipart,
              PersistentArtifactCloudCapability.uploadPart,
              PersistentArtifactCloudCapability.completeMultipart,
              PersistentArtifactCloudCapability.abortMultipart,
            },
        _forcedStatuses = forcedStatuses ?? const {},
        _injectedFailures = injectedFailures ?? const {} {
    final seed = CloudTestFixtures.objectReference();
    _objectsByKey[seed.objectKey] = seed;
  }

  final PersistentArtifactCloudBackendDescriptor _descriptor;
  final Set<PersistentArtifactCloudCapability> _capabilities;
  final Map<CloudOperationType, CloudOperationStatus> _forcedStatuses;
  final Map<CloudOperationType, Object> _injectedFailures;
  final PersistentArtifactCloudBridgeClassification classification;
  final Map<CloudOperationType, int> _operationCounters = {};
  final Map<String, PersistentArtifactCloudObjectReference> _objectsByKey = {};

  Map<CloudOperationType, int> get operationCounters =>
      Map.unmodifiable(_operationCounters);

  @override
  Future<PersistentArtifactCloudBackendDescriptor> describe() async =>
      _descriptor;

  @override
  Future<PersistentArtifactCloudStagingReadinessDecision>
      evaluateEnvironment() async {
    return CloudTestFixtures.readinessDecision(approved: false);
  }

  @override
  Future<Set<PersistentArtifactCloudCapability>> evaluateCapabilities() async =>
      Set.unmodifiable(_capabilities);

  @override
  Future<PersistentArtifactCloudOperationResult> putObject(
    PersistentArtifactCloudOperationRequest request,
  ) async {
    _count(CloudOperationType.putObject);
    _maybeThrow(CloudOperationType.putObject);
    final object =
        request.objectReference ?? CloudTestFixtures.objectReference();
    _objectsByKey[object.objectKey] = object;
    return _resultFor(
      request,
      _statusFor(CloudOperationType.putObject, CloudOperationStatus.succeeded),
      object: object,
    );
  }

  @override
  Future<PersistentArtifactCloudOperationResult> getObject(
    PersistentArtifactCloudOperationRequest request,
  ) async {
    _count(CloudOperationType.getObject);
    _maybeThrow(CloudOperationType.getObject);
    final key = request.objectReference?.objectKey;
    final object = key == null ? null : _objectsByKey[key];
    if (object == null) {
      return _resultFor(
        request,
        CloudOperationStatus.failed,
        issues: const [
          PersistentArtifactCloudIssue(
            code: 'not-found',
            message: 'Object not found in fake table',
            severity: CloudIssueSeverity.warning,
          ),
        ],
      );
    }
    return _resultFor(
      request,
      _statusFor(CloudOperationType.getObject, CloudOperationStatus.succeeded),
      object: object,
    );
  }

  @override
  Future<PersistentArtifactCloudOperationResult> headObject(
    PersistentArtifactCloudOperationRequest request,
  ) async {
    _count(CloudOperationType.headObject);
    _maybeThrow(CloudOperationType.headObject);
    final key = request.objectReference?.objectKey;
    final object = key == null ? null : _objectsByKey[key];
    return _resultFor(
      request,
      _statusFor(
        CloudOperationType.headObject,
        object == null
            ? CloudOperationStatus.failed
            : CloudOperationStatus.succeeded,
      ),
      object: object,
      issues: object == null
          ? const [
              PersistentArtifactCloudIssue(
                code: 'not-found',
                message: 'Object not found in fake table',
                severity: CloudIssueSeverity.warning,
              ),
            ]
          : const [],
    );
  }

  @override
  Future<bool> objectExists(
      PersistentArtifactCloudOperationRequest request) async {
    _count(CloudOperationType.headObject);
    final key = request.objectReference?.objectKey;
    if (key == null) return false;
    return _objectsByKey.containsKey(key);
  }

  @override
  Future<List<PersistentArtifactCloudOperationResult>> listObjects(
    PersistentArtifactCloudOperationRequest request,
  ) async {
    _count(CloudOperationType.listObjects);
    _maybeThrow(CloudOperationType.listObjects);
    final sorted = _objectsByKey.values.toList()
      ..sort((a, b) => a.objectKey.compareTo(b.objectKey));
    if (sorted.isEmpty) {
      return [
        _resultFor(
          request,
          _statusFor(
              CloudOperationType.listObjects, CloudOperationStatus.succeeded),
          object: CloudTestFixtures.objectReference(),
          issues: const [],
        ),
      ];
    }
    final first = sorted.first;
    final second = sorted.length > 1 ? sorted[1] : sorted.first;
    return [
      _resultFor(
        request,
        _statusFor(
            CloudOperationType.listObjects, CloudOperationStatus.succeeded),
        object: first,
      ),
      _resultFor(
        request.copyWith(requestId: '${request.requestId}-2'),
        CloudOperationStatus.partial,
        object: second,
      ),
    ];
  }

  @override
  Future<PersistentArtifactCloudOperationResult> deleteObject(
    PersistentArtifactCloudOperationRequest request,
  ) async {
    _count(CloudOperationType.deleteObject);
    _maybeThrow(CloudOperationType.deleteObject);
    final key = request.objectReference?.objectKey;
    final existing = key == null ? null : _objectsByKey.remove(key);
    return _resultFor(
      request,
      _statusFor(
        CloudOperationType.deleteObject,
        existing == null
            ? CloudOperationStatus.failed
            : CloudOperationStatus.succeeded,
      ),
      object: existing,
      issues: existing == null
          ? const [
              PersistentArtifactCloudIssue(
                code: 'not-found',
                message: 'Object does not exist',
                severity: CloudIssueSeverity.warning,
              ),
            ]
          : const [],
    );
  }

  @override
  Future<PersistentArtifactCloudOperationResult> copyObject(
    PersistentArtifactCloudOperationRequest request,
  ) async {
    _count(CloudOperationType.copyObject);
    _maybeThrow(CloudOperationType.copyObject);
    final source = request.objectReference;
    final destination = request.destinationObjectReference;
    if (source != null && destination != null) {
      _objectsByKey[destination.objectKey] = destination;
    }
    return _resultFor(
      request,
      _statusFor(CloudOperationType.copyObject, CloudOperationStatus.succeeded),
      object: destination ?? source,
    );
  }

  @override
  Future<PersistentArtifactCloudOperationResult> beginMultipart(
    PersistentArtifactCloudOperationRequest request,
  ) async {
    _count(CloudOperationType.beginMultipart);
    _maybeThrow(CloudOperationType.beginMultipart);
    return _resultFor(
      request,
      _statusFor(
          CloudOperationType.beginMultipart, CloudOperationStatus.pending),
      multipartStatus: CloudMultipartStatus.initiated,
    );
  }

  @override
  Future<PersistentArtifactCloudOperationResult> uploadPart(
    PersistentArtifactCloudOperationRequest request,
  ) async {
    _count(CloudOperationType.uploadPart);
    _maybeThrow(CloudOperationType.uploadPart);
    return _resultFor(
      request,
      _statusFor(CloudOperationType.uploadPart, CloudOperationStatus.partial),
      multipartStatus: CloudMultipartStatus.uploading,
    );
  }

  @override
  Future<PersistentArtifactCloudOperationResult> completeMultipart(
    PersistentArtifactCloudOperationRequest request,
  ) async {
    _count(CloudOperationType.completeMultipart);
    _maybeThrow(CloudOperationType.completeMultipart);
    return _resultFor(
      request,
      _statusFor(
        CloudOperationType.completeMultipart,
        CloudOperationStatus.succeeded,
      ),
      multipartStatus: CloudMultipartStatus.completed,
    );
  }

  @override
  Future<PersistentArtifactCloudOperationResult> abortMultipart(
    PersistentArtifactCloudOperationRequest request,
  ) async {
    _count(CloudOperationType.abortMultipart);
    _maybeThrow(CloudOperationType.abortMultipart);
    return _resultFor(
      request,
      _statusFor(
          CloudOperationType.abortMultipart, CloudOperationStatus.failed),
      multipartStatus: CloudMultipartStatus.aborted,
    );
  }

  PersistentArtifactCloudOperationResult _resultFor(
    PersistentArtifactCloudOperationRequest request,
    CloudOperationStatus status, {
    CloudMultipartStatus? multipartStatus,
    PersistentArtifactCloudObjectReference? object,
    List<PersistentArtifactCloudIssue> issues = const [],
  }) {
    return PersistentArtifactCloudOperationResult(
      requestId: request.requestId,
      operationType: request.operationType,
      status: status,
      objectReference: object ??
          request.objectReference ??
          CloudTestFixtures.objectReference(),
      versionReference: CloudTestFixtures.objectVersion(),
      multipartStatus: multipartStatus,
      issues: issues,
      metadata: {
        'backend': 'fake',
        'classification': classification.wireName,
      },
    );
  }

  void _count(CloudOperationType operation) {
    _operationCounters.update(operation, (value) => value + 1,
        ifAbsent: () => 1);
  }

  CloudOperationStatus _statusFor(
    CloudOperationType operation,
    CloudOperationStatus fallback,
  ) {
    return _forcedStatuses[operation] ?? fallback;
  }

  void _maybeThrow(CloudOperationType operation) {
    final failure = _injectedFailures[operation];
    if (failure == null) return;
    if (failure is Exception) throw failure;
    throw StateError('$failure');
  }
}
