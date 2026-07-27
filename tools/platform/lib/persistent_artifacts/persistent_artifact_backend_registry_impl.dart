import 'backend/persistent_artifact_backend_capability.dart';
import 'backend/persistent_artifact_backend_environment_decision.dart';
import 'backend/persistent_artifact_backend_environment.dart';
import 'backend/persistent_artifact_backend_registration.dart';
import 'cloud/persistent_artifact_cloud_backend_bridge.dart';
import 'cloud/persistent_artifact_cloud_backend_registration_handle.dart';
import 'cloud/persistent_artifact_cloud_bridge_classification.dart';
import 'cloud/persistent_artifact_cloud_capability.dart';
import 'cloud/persistent_artifact_cloud_environment_gate.dart';
import 'cloud/persistent_artifact_cloud_operation_models.dart';
import 'cloud/persistent_artifact_cloud_operation_status.dart';
import 'backend/persistent_artifact_environment_gate.dart';
import 'interfaces/persistent_artifact_content_reader.dart';
import 'interfaces/persistent_artifact_content_store.dart';
import 'interfaces/persistent_artifact_content_writer.dart';
import 'interfaces/persistent_artifact_location_resolver.dart';
import 'interfaces/persistent_artifact_manifest_store.dart';
import 'backend/persistent_artifact_physical_backend_bridge.dart';
import 'interfaces/persistent_artifact_physical_deletion_provider.dart';
import 'persistent_artifact_exceptions.dart';

class PersistentArtifactBackendRegistry {
  PersistentArtifactBackendRegistry({
    PersistentArtifactBackendEnvironmentContext environmentContext =
        PersistentArtifactBackendEnvironmentContext.nonProduction,
    PersistentArtifactEnvironmentGate environmentGate =
        const PersistentArtifactEnvironmentGate(),
  })  : _environmentContext = environmentContext,
        _environmentGate = environmentGate;

  final Map<String, PersistentArtifactBackendRegistration> _registrations = {};
  final PersistentArtifactBackendEnvironmentContext _environmentContext;
  final PersistentArtifactEnvironmentGate _environmentGate;
  final PersistentArtifactCloudEnvironmentGate _cloudEnvironmentGate =
      const PersistentArtifactCloudEnvironmentGate();
  bool _frozen = false;

  bool get isFrozen => _frozen;

  void freeze() => _frozen = true;

  bool contains(String backendId) => _registrations.containsKey(backendId);

  List<String> backends() => _registrations.keys.toList()..sort();

  PersistentArtifactBackendHandle? lookup(String backendId) {
    final registration = _registrations[backendId];
    if (registration == null) return null;
    return PersistentArtifactBackendHandle(
      descriptor: registration.descriptor,
      registration: registration,
    );
  }

  List<PersistentArtifactBackendHandle> queryCapabilities(
    PersistentArtifactBackendCapability capability,
  ) {
    final results = _registrations.values
        .where((it) => it.descriptor.capabilities.contains(capability))
        .map(
          (it) => PersistentArtifactBackendHandle(
            descriptor: it.descriptor,
            registration: it,
          ),
        )
        .toList()
      ..sort(
          (a, b) => a.descriptor.backendId.compareTo(b.descriptor.backendId));
    return List.unmodifiable(results);
  }

  PersistentArtifactBackendHandle? resolveForOperation({
    required String backendId,
    required PersistentArtifactBackendCapability capability,
  }) {
    final registration = _registrations[backendId];
    if (registration == null) {
      return null;
    }
    if (!registration.descriptor.capabilities.contains(capability)) {
      return null;
    }
    return PersistentArtifactBackendHandle(
      descriptor: registration.descriptor,
      registration: registration,
    );
  }

  PersistentArtifactBackendHandle register(
    PersistentArtifactBackendRegistration registration,
  ) {
    _ensureMutable();
    _ensureEnvironmentAllowed(registration);

    final backendId = registration.descriptor.backendId;
    final existing = _registrations[backendId];
    if (existing != null) {
      if (_isCompatible(existing, registration)) {
        return PersistentArtifactBackendHandle(
          descriptor: existing.descriptor,
          registration: existing,
        );
      }
      throw StateError('Incompatible backend registration for id: $backendId');
    }

    _registrations[backendId] = registration;
    return PersistentArtifactBackendHandle(
      descriptor: registration.descriptor,
      registration: registration,
    );
  }

  bool unregister(String backendId) {
    _ensureMutable();
    return _registrations.remove(backendId) != null;
  }

  void clearRuntimeRegistrations() {
    _ensureMutable();
    _registrations.removeWhere((_, value) => value.runtimeRegistration);
  }

  // Legacy compatibility API.
  void registerContentStore(
    String backendId,
    PersistentArtifactContentStore store,
  ) {
    register(
      PersistentArtifactBackendRegistration(
        descriptor: PersistentArtifactBackendDescriptor(
          backendId: backendId,
          kind: 'legacy-content-store',
          capabilities: const {
            PersistentArtifactBackendCapability.contentWrite,
            PersistentArtifactBackendCapability.contentRead,
            PersistentArtifactBackendCapability.contentExists,
          },
          environment: _environmentContext.isProduction
              ? const PersistentArtifactBackendEnvironment(
                  classification:
                      PersistentArtifactBackendEnvironmentClassification
                          .productionEligible,
                  test: false,
                  development: false,
                  localReference: false,
                  stagingEligible: true,
                  productionEligible: true,
                )
              : const PersistentArtifactBackendEnvironment(
                  classification:
                      PersistentArtifactBackendEnvironmentClassification
                          .development,
                  test: false,
                  development: true,
                  localReference: false,
                  stagingEligible: true,
                  productionEligible: true,
                ),
        ),
        contentStore: store,
        contentReader: null,
        contentWriter: null,
        runtimeRegistration: true,
      ),
    );
  }

  PersistentArtifactContentStore? resolveContentStore(String backendId) {
    return _registrations[backendId]?.contentStore;
  }

  PersistentArtifactContentStore? contentStoreOf(String backendId) =>
      _registrations[backendId]?.contentStore;

  PersistentArtifactManifestStore? manifestStoreOf(String backendId) =>
      _registrations[backendId]?.manifestStore;

  PersistentArtifactLocationResolver? locationResolverOf(String backendId) =>
      _registrations[backendId]?.locationResolver;

  PersistentArtifactContentReader? contentReaderOf(String backendId) =>
      _registrations[backendId]?.contentReader;

  PersistentArtifactContentWriter? contentWriterOf(String backendId) =>
      _registrations[backendId]?.contentWriter;

  PersistentArtifactPhysicalDeletionProvider? quarantineProviderOf(
    String backendId,
  ) =>
      _registrations[backendId]?.quarantineProvider;

  PersistentArtifactRecoveryInspector? recoveryInspectorOf(String backendId) =>
      _registrations[backendId]?.recoveryInspector;

  PersistentArtifactPhysicalBackendBridge? bridgeOf(String backendId) =>
      _registrations[backendId]?.bridge;

  PersistentArtifactCloudBackendBridge? cloudBridgeOf(String backendId) =>
      _registrations[backendId]?.cloudBridge;

  PersistentArtifactCloudBackendRegistrationHandle? cloudRegistrationOf(
    String backendId,
  ) {
    final registration = _registrations[backendId];
    if (registration?.cloudBridge == null ||
        registration?.cloudDescriptor == null) {
      return null;
    }
    return PersistentArtifactCloudBackendRegistrationHandle(
      backendId: backendId,
      descriptor: registration!.cloudDescriptor!,
      bridge: registration.cloudBridge!,
    );
  }

  PersistentArtifactCloudBackendResolution resolveCloudBackend(
      String backendId) {
    final registration = _registrations[backendId];
    if (registration == null) {
      return PersistentArtifactCloudBackendResolution(
        backendId: backendId,
        resolved: false,
        status: PersistentArtifactCloudOperationStatus.unregistered,
        conflict: PersistentArtifactCloudBackendConflict(
          backendId: backendId,
          code: 'backend-unregistered',
          message: 'Cloud backend is not registered',
        ),
      );
    }
    if (registration.cloudBridge == null ||
        registration.cloudDescriptor == null) {
      return PersistentArtifactCloudBackendResolution(
        backendId: backendId,
        resolved: false,
        status: PersistentArtifactCloudOperationStatus.unavailable,
        conflict: PersistentArtifactCloudBackendConflict(
          backendId: backendId,
          code: 'cloud-bridge-unavailable',
          message: 'Cloud bridge is not registered for backend',
        ),
      );
    }
    return PersistentArtifactCloudBackendResolution(
      backendId: backendId,
      resolved: true,
      status: PersistentArtifactCloudOperationStatus.success,
      classification:
          PersistentArtifactCloudBridgeClassification.offlineSimulation,
    );
  }

  PersistentArtifactCloudBackendResolution resolveCloudBackendForOperation(
    String backendId,
    PersistentArtifactCloudCapability capability,
  ) {
    final base = resolveCloudBackend(backendId);
    if (!base.resolved) return base;
    final capabilities = queryCloudCapabilities()[backendId] ?? const {};
    if (!capabilities.contains(capability)) {
      return PersistentArtifactCloudBackendResolution(
        backendId: backendId,
        resolved: false,
        status: PersistentArtifactCloudOperationStatus.unsupported,
        classification: base.classification,
        conflict: PersistentArtifactCloudBackendConflict(
          backendId: backendId,
          code: 'cloud-capability-not-supported',
          message: 'Cloud capability ${capability.name} not supported',
        ),
      );
    }
    return base;
  }

  PersistentArtifactCloudBackendRegistrationHandle?
      resolveCloudBackendForCapability(
    PersistentArtifactCloudCapability capability,
  ) {
    final candidates = queryCloudCapabilities()
        .entries
        .where((entry) => entry.value.contains(capability))
        .map((entry) => cloudRegistrationOf(entry.key))
        .whereType<PersistentArtifactCloudBackendRegistrationHandle>()
        .toList()
      ..sort((a, b) => a.backendId.compareTo(b.backendId));
    if (candidates.isEmpty) return null;
    return candidates.first;
  }

  Map<String, Set<PersistentArtifactCloudCapability>> queryCloudCapabilities() {
    final result = <String, Set<PersistentArtifactCloudCapability>>{};
    for (final entry in _registrations.entries) {
      final backendId = entry.key;
      final registration = entry.value;
      if (registration.cloudBridge == null) continue;
      result[backendId] = Set.unmodifiable({
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
      });
    }
    return Map.unmodifiable(result);
  }

  PersistentArtifactCloudEnvironmentDecision evaluateCloudEnvironment(
    String backendId,
    PersistentArtifactRuntimeEnvironment environment,
  ) {
    final resolution = resolveCloudBackend(backendId);
    if (!resolution.resolved) {
      return PersistentArtifactCloudEnvironmentDecision(
        backendId: backendId,
        runtimeEnvironment: environment,
        allowed: false,
        status: resolution.status,
        reasonCode: resolution.conflict?.code,
        message: resolution.conflict?.message,
      );
    }
    return _cloudEnvironmentGate.evaluate(
      backendId: backendId,
      runtimeEnvironment: environment,
      classification: resolution.classification,
    );
  }

  PersistentArtifactBackendEnvironmentDecision evaluateEnvironment(
    String backendId, {
    PersistentArtifactRuntimeEnvironment? runtimeEnvironment,
  }) {
    final registration = _registrations[backendId];
    if (registration == null) {
      return PersistentArtifactBackendEnvironmentDecision.blockedDecision(
        environment: PersistentArtifactBackendEnvironment.localReferenceOnly,
        reasonCode: 'backend-unregistered',
        message: 'Backend $backendId is not registered',
      );
    }
    return _environmentGate.evaluate(
      environment: registration.descriptor.environment,
      runtimeEnvironment: runtimeEnvironment ?? _contextEnvironment(),
    );
  }

  bool _isCompatible(
    PersistentArtifactBackendRegistration existing,
    PersistentArtifactBackendRegistration incoming,
  ) {
    final a = existing.descriptor;
    final b = incoming.descriptor;
    return a.backendId == b.backendId &&
        a.kind == b.kind &&
        a.environment.classification == b.environment.classification &&
        a.environment.productionEligible == b.environment.productionEligible &&
        a.capabilities.length == b.capabilities.length &&
        a.capabilities.containsAll(b.capabilities);
  }

  void _ensureMutable() {
    if (_frozen) {
      throw const PersistentArtifactRegistryFrozenException(
        'PersistentArtifactBackendRegistry',
      );
    }
  }

  void _ensureEnvironmentAllowed(
    PersistentArtifactBackendRegistration registration,
  ) {
    if (_environmentContext.isProduction &&
        !registration.descriptor.environment.productionEligible) {
      throw StateError(
        'Backend ${registration.descriptor.backendId} is not production-eligible',
      );
    }
  }

  PersistentArtifactRuntimeEnvironment _contextEnvironment() {
    if (_environmentContext.isProduction) {
      return PersistentArtifactRuntimeEnvironment.production;
    }
    return PersistentArtifactRuntimeEnvironment.localReference;
  }
}
