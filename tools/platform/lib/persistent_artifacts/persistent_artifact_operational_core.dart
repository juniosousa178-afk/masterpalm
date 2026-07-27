import '../interfaces/cicd_integration_provider.dart';
import '../interfaces/cryptographic_trust_provider.dart';
import '../interfaces/persistent_artifact_provider.dart';
import '../interfaces/release_evidence_provider.dart';
import '../interfaces/release_supply_chain_provider.dart';
import '../models/persistent_artifacts/collected_persistent_artifact_material.dart';
import '../models/persistent_artifacts/persistent_artifact_content_descriptor.dart';
import '../models/persistent_artifacts/persistent_artifact_evaluation_request.dart';
import '../models/persistent_artifacts/persistent_artifact_evaluation_result.dart';
import '../models/persistent_artifacts/persistent_artifact_enums.dart';
import '../models/persistent_artifacts/persistent_artifact_fingerprint.dart';
import '../models/persistent_artifacts/persistent_artifact_infrastructure_identity.dart';
import '../models/persistent_artifacts/persistent_artifact_infrastructure_snapshot.dart';
import '../models/persistent_artifacts/persistent_artifact_operation_context.dart';
import '../models/persistent_artifacts/persistent_artifact_operation_message.dart';
import '../models/persistent_artifacts/persistent_artifact_operation_models.dart';
import '../models/persistent_artifacts/persistent_artifact_operational_enums.dart';
import '../models/persistent_artifacts/persistent_artifact_policy_evaluation_result.dart';
import '../models/persistent_artifacts/persistent_artifact_policy_models.dart';
import '../models/persistent_artifacts/persistent_artifact_query.dart';
import '../models/persistent_artifacts/persistent_artifact_reference_models.dart';
import '../models/persistent_artifacts/persistent_artifact_requirement_result.dart';
import '../models/persistent_artifacts/persistent_artifact_snapshot_reference.dart';
import '../models/persistent_artifacts/persistent_artifact_subject.dart';
import '../models/persistent_artifacts/persistent_artifact_validation_result.dart';
import '../models/persistent_artifacts/resolved_persistent_artifact_sources.dart';
import '../models/persistent_artifacts/policies/artifact_integrity_policy_v1.dart';
import '../models/persistent_artifacts/policies/artifact_replication_policy_v1.dart';
import '../models/persistent_artifacts/policies/artifact_retention_policy_v1.dart';
import '../models/persistent_artifacts/policies/artifact_storage_policy_v1.dart';
import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_supply_chain/release_supply_chain_snapshot.dart';
import '../models/cicd_integration/cicd_integration_snapshot.dart';
import '../models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import '../models/persistent_artifacts/cloud/persistent_artifact_cloud_operation_request.dart';
import '../persistent_artifacts/backend/persistent_artifact_physical_operation_models.dart';
import '../persistent_artifacts/backend/persistent_artifact_physical_operation_status.dart';
import '../persistent_artifacts/backend/persistent_artifact_physical_operations_service.dart';
import '../persistent_artifacts/cloud/persistent_artifact_cloud_operation_models.dart';
import '../persistent_artifacts/cloud/persistent_artifact_cloud_operations_service.dart';
import '../persistent_artifacts/cloud/persistent_artifact_cloud_operation_status.dart';
import '../persistent_artifacts/interfaces/persistent_artifact_interfaces.dart';
import '../persistent_artifacts/persistent_artifact_backend_registry_impl.dart';
import 'persistent_artifact_exceptions.dart';

class PersistentArtifactCanonicalSerializer {
  const PersistentArtifactCanonicalSerializer();

  String snapshotFingerprint(
      PersistentArtifactInfrastructureSnapshot snapshot) {
    return PersistentArtifactFingerprint.fromComparableJson(
        snapshot.toComparableJson());
  }

  String materialFingerprint(CollectedPersistentArtifactMaterial material) {
    return PersistentArtifactFingerprint.fromComparableJson(
        material.toComparableJson());
  }
}

class PersistentArtifactInfrastructureIdentityBuilder {
  const PersistentArtifactInfrastructureIdentityBuilder({
    PersistentArtifactCanonicalSerializer? serializer,
  }) : _serializer =
            serializer ?? const PersistentArtifactCanonicalSerializer();

  final PersistentArtifactCanonicalSerializer _serializer;

  String buildSnapshotId({
    required String projectId,
    required String releaseId,
    required String fingerprint,
  }) {
    return 'pa-snapshot:$projectId:$releaseId:$fingerprint';
  }

  PersistentArtifactInfrastructureIdentity buildIdentity(
    PersistentArtifactInfrastructureSnapshot snapshot,
  ) {
    final fingerprint = _serializer.snapshotFingerprint(snapshot);
    final releaseId = snapshot.releaseId ?? 'unknown';
    return PersistentArtifactInfrastructureIdentity(
      persistentArtifactInfrastructureId: buildSnapshotId(
        projectId: snapshot.projectId,
        releaseId: releaseId,
        fingerprint: fingerprint,
      ),
      snapshotFingerprint: fingerprint,
      subjectsFingerprint: snapshot.subjects.isEmpty
          ? null
          : PersistentArtifactFingerprint.fromComparableJson(
              {
                'subjects':
                    snapshot.subjects.map((e) => e.toComparableJson()).toList()
              },
            ),
      policiesFingerprint: snapshot.policyReferences.isEmpty
          ? null
          : PersistentArtifactFingerprint.fromComparableJson(
              {
                'policies': snapshot.policyReferences
                    .map((e) => e.toComparableJson())
                    .toList(),
              },
            ),
      operationsFingerprint: snapshot.operationResults.isEmpty
          ? null
          : PersistentArtifactFingerprint.fromComparableJson(
              {
                'operations': snapshot.operationResults
                    .map((e) => e.toComparableJson())
                    .toList(),
              },
            ),
    );
  }
}

class PersistentArtifactPolicyRegistry {
  PersistentArtifactPolicyRegistry({bool registerDefaults = false}) {
    if (registerDefaults) {
      registerDefaultPolicies();
    }
  }

  final Map<String, PersistentArtifactStoragePolicy> _storage = {};
  final Map<String, PersistentArtifactRetentionPolicy> _retention = {};
  final Map<String, PersistentArtifactIntegrityPolicy> _integrity = {};
  final Map<String, PersistentArtifactReplicationPolicy> _replication = {};
  bool _frozen = false;

  bool get isFrozen => _frozen;

  void freeze() => _frozen = true;

  void registerDefaultPolicies() {
    registerStorage(ArtifactStoragePolicyV1.create());
    registerRetention(ArtifactRetentionPolicyV1.create());
    registerIntegrity(ArtifactIntegrityPolicyV1.create());
    registerReplication(ArtifactReplicationPolicyV1.create());
  }

  void registerStorage(PersistentArtifactStoragePolicy policy) {
    _ensureMutable();
    _storage[_key(policy.policyId, policy.version)] = policy;
  }

  void registerRetention(PersistentArtifactRetentionPolicy policy) {
    _ensureMutable();
    _retention[_key(policy.policyId, policy.version)] = policy;
  }

  void registerIntegrity(PersistentArtifactIntegrityPolicy policy) {
    _ensureMutable();
    _integrity[_key(policy.policyId, policy.version)] = policy;
  }

  void registerReplication(PersistentArtifactReplicationPolicy policy) {
    _ensureMutable();
    _replication[_key(policy.policyId, policy.version)] = policy;
  }

  PersistentArtifactStoragePolicy? resolveStorage({
    required String policyId,
    int? policyVersion,
    bool allowCandidate = false,
    bool useLatest = false,
  }) {
    return _resolveTyped(
      all: _storage.values,
      policyId: policyId,
      policyVersion: policyVersion,
      allowCandidate: allowCandidate,
      useLatest: useLatest,
      statusOf: (p) => p.status,
      idOf: (p) => p.policyId,
      versionOf: (p) => p.version,
    );
  }

  PersistentArtifactRetentionPolicy? resolveRetention({
    required String policyId,
    int? policyVersion,
    bool allowCandidate = false,
    bool useLatest = false,
  }) {
    return _resolveTyped(
      all: _retention.values,
      policyId: policyId,
      policyVersion: policyVersion,
      allowCandidate: allowCandidate,
      useLatest: useLatest,
      statusOf: (p) => p.status,
      idOf: (p) => p.policyId,
      versionOf: (p) => p.version,
    );
  }

  PersistentArtifactIntegrityPolicy? resolveIntegrity({
    required String policyId,
    int? policyVersion,
    bool allowCandidate = false,
    bool useLatest = false,
  }) {
    return _resolveTyped(
      all: _integrity.values,
      policyId: policyId,
      policyVersion: policyVersion,
      allowCandidate: allowCandidate,
      useLatest: useLatest,
      statusOf: (p) => p.status,
      idOf: (p) => p.policyId,
      versionOf: (p) => p.version,
    );
  }

  PersistentArtifactReplicationPolicy? resolveReplication({
    required String policyId,
    int? policyVersion,
    bool allowCandidate = false,
    bool useLatest = false,
  }) {
    return _resolveTyped(
      all: _replication.values,
      policyId: policyId,
      policyVersion: policyVersion,
      allowCandidate: allowCandidate,
      useLatest: useLatest,
      statusOf: (p) => p.status,
      idOf: (p) => p.policyId,
      versionOf: (p) => p.version,
    );
  }

  List<Object> list() => [
        ..._storage.values,
        ..._retention.values,
        ..._integrity.values,
        ..._replication.values,
      ];

  T? _resolveTyped<T>({
    required Iterable<T> all,
    required String policyId,
    required int? policyVersion,
    required bool allowCandidate,
    required bool useLatest,
    required PersistentArtifactPolicyStatus Function(T) statusOf,
    required String Function(T) idOf,
    required int Function(T) versionOf,
  }) {
    final filtered = all.where((p) => idOf(p) == policyId).toList()
      ..sort((a, b) => versionOf(b).compareTo(versionOf(a)));
    if (filtered.isEmpty) return null;
    if (policyVersion != null) {
      for (final policy in filtered) {
        if (versionOf(policy) == policyVersion) {
          return policy;
        }
      }
      return null;
    }
    if (useLatest) return filtered.first;
    final active = filtered
        .where((p) => statusOf(p) == PersistentArtifactPolicyStatus.active);
    if (active.isNotEmpty) return active.first;
    if (allowCandidate) {
      final candidate = filtered.where(
          (p) => statusOf(p) == PersistentArtifactPolicyStatus.candidate);
      if (candidate.isNotEmpty) return candidate.first;
    }
    return null;
  }

  void _ensureMutable() {
    if (_frozen) {
      throw const PersistentArtifactRegistryFrozenException(
        'PersistentArtifactPolicyRegistry',
      );
    }
  }

  String _key(String policyId, int version) => '$policyId:v$version';
}

class PersistentArtifactSourceResolver {
  const PersistentArtifactSourceResolver({
    required ReleaseEvidenceProvider releaseEvidenceProvider,
    required ReleaseSupplyChainProvider releaseSupplyChainProvider,
    required CicdIntegrationProvider cicdIntegrationProvider,
    required CryptographicTrustProvider cryptographicTrustProvider,
  })  : _releaseEvidenceProvider = releaseEvidenceProvider,
        _releaseSupplyChainProvider = releaseSupplyChainProvider,
        _cicdIntegrationProvider = cicdIntegrationProvider,
        _cryptographicTrustProvider = cryptographicTrustProvider;

  final ReleaseEvidenceProvider _releaseEvidenceProvider;
  final ReleaseSupplyChainProvider _releaseSupplyChainProvider;
  final CicdIntegrationProvider _cicdIntegrationProvider;
  final CryptographicTrustProvider _cryptographicTrustProvider;

  /// Read-only boundary: resolve using load/latest only; never evaluate/publish.
  Future<ResolvedPersistentArtifactSources> resolveAll(
    PersistentArtifactEvaluationRequest request,
  ) async {
    final refs = <PersistentArtifactSourceReference>[];
    final resolved = <String>[];
    final unresolved = <String>[];
    final injected = <String>[];
    final messages = <PersistentArtifactOperationMessage>[];

    Future<void> resolveLatest({
      required String key,
      required PersistentArtifactSourceType sourceType,
      required Future<dynamic> Function() load,
      required String Function(dynamic) idOf,
      required String Function(dynamic) fpOf,
    }) async {
      if (request.injectedSources.containsKey(key)) {
        final id = request.injectedSources[key]!;
        injected.add(sourceType.wireName);
        resolved.add(sourceType.wireName);
        refs.add(
          PersistentArtifactSourceReference(
            sourceType: sourceType,
            sourceId: id,
            projectId: request.projectId,
            releaseId: request.releaseId,
            fingerprint: 'injected:$id',
            metadata: const {'resolutionMode': 'injected'},
          ),
        );
        return;
      }
      if (!request.useLatest) return;
      final artifact = await load();
      if (artifact == null) {
        unresolved.add(sourceType.wireName);
        messages.add(
          PersistentArtifactOperationMessage(
            messageId: 'source-unavailable-${sourceType.wireName}',
            code: 'source-unavailable',
            message: 'Source ${sourceType.wireName} unavailable',
            severity: PersistentArtifactIssueSeverity.warning,
            operation: PersistentArtifactOperationType.snapshot,
            sourceType: sourceType,
          ),
        );
        return;
      }
      resolved.add(sourceType.wireName);
      refs.add(
        PersistentArtifactSourceReference(
          sourceType: sourceType,
          sourceId: idOf(artifact),
          projectId: request.projectId,
          releaseId: request.releaseId,
          fingerprint: fpOf(artifact),
          metadata: const {'resolutionMode': 'latest'},
        ),
      );
    }

    await resolveLatest(
      key: 'releaseEvidenceBundleId',
      sourceType: PersistentArtifactSourceType.releaseEvidence,
      load: () => _releaseEvidenceProvider.latest(
        projectId: request.projectId,
        releaseId: request.releaseId,
      ),
      idOf: (it) => (it as ReleaseEvidenceBundle).metadata.bundleId,
      fpOf: (it) => (it as ReleaseEvidenceBundle).fingerprint,
    );
    await resolveLatest(
      key: 'releaseSupplyChainSnapshotId',
      sourceType: PersistentArtifactSourceType.releaseSupplyChain,
      load: () => _releaseSupplyChainProvider.latest(
        projectId: request.projectId,
        releaseId: request.releaseId,
      ),
      idOf: (it) =>
          (it as ReleaseSupplyChainSnapshot).metadata.supplyChainSnapshotId,
      fpOf: (it) => (it as ReleaseSupplyChainSnapshot).fingerprint,
    );
    await resolveLatest(
      key: 'cicdIntegrationSnapshotId',
      sourceType: PersistentArtifactSourceType.cicdIntegration,
      load: () => _cicdIntegrationProvider.latest(
        projectId: request.projectId,
        releaseId: request.releaseId,
      ),
      idOf: (it) =>
          (it as CicdIntegrationSnapshot).metadata.cicdIntegrationSnapshotId,
      fpOf: (it) => (it as CicdIntegrationSnapshot).fingerprint,
    );
    await resolveLatest(
      key: 'cryptographicTrustSnapshotId',
      sourceType: PersistentArtifactSourceType.cryptographicTrust,
      load: () => _cryptographicTrustProvider.latest(
        projectId: request.projectId,
        releaseId: request.releaseId,
      ),
      idOf: (it) => (it as CryptographicTrustSnapshot)
          .metadata
          .cryptographicTrustSnapshotId,
      fpOf: (it) => (it as CryptographicTrustSnapshot).fingerprint,
    );

    final status = unresolved.isEmpty
        ? PersistentArtifactSourceResolutionStatus.complete
        : (resolved.isEmpty
            ? PersistentArtifactSourceResolutionStatus.unavailable
            : PersistentArtifactSourceResolutionStatus.partial);

    return ResolvedPersistentArtifactSources(
      status: status,
      resolvedSources: resolved,
      unresolvedSources: unresolved,
      injectedSources: injected,
      sourceReferences: refs..sort((a, b) => a.sourceId.compareTo(b.sourceId)),
      messages: messages,
      fingerprint: PersistentArtifactFingerprint.fromComparableJson(
        {
          'sourceReferences': refs.map((e) => e.toComparableJson()).toList(),
        },
      ),
    );
  }
}

class PersistentArtifactCollector {
  const PersistentArtifactCollector();

  CollectedPersistentArtifactMaterial collect(
    PersistentArtifactOperationContext context,
  ) {
    return CollectedPersistentArtifactMaterial(
      subjects: context.request.operationRequest.artifactSubjects,
      policies: context.request.policyReferences,
      sourceReferences: context.sources.sourceReferences,
      metadata: {
        'evaluationId': context.request.evaluationId,
        'projectId': context.request.projectId,
      },
    );
  }
}

class PersistentArtifactContentDescriptorBuilder {
  const PersistentArtifactContentDescriptorBuilder();

  PersistentArtifactContentDescriptor fromSubject(
    PersistentArtifactSubject subject, {
    required String contentId,
  }) {
    return PersistentArtifactContentDescriptor(
      contentId: contentId,
      mediaType: subject.contentType ?? 'application/octet-stream',
      format: PersistentArtifactFormat.json,
      encoding: PersistentArtifactEncoding.utf8,
      compression: PersistentArtifactCompression.none,
      schemaVersion: subject.schemaVersion,
      contentFingerprint: PersistentArtifactFingerprint.fromComparableJson(
        subject.toComparableJson(),
      ),
      metadata: subject.metadata,
    );
  }
}

class PersistentArtifactVersionBuilder {
  const PersistentArtifactVersionBuilder();
}

class PersistentArtifactManifestBuilder {
  const PersistentArtifactManifestBuilder();
}

class _BasePolicyEvaluator {
  const _BasePolicyEvaluator();

  PersistentArtifactPolicyEvaluationResult ok({
    required String policyId,
    required int policyVersion,
    required PersistentArtifactPolicyType policyType,
    required String requirementId,
    required PersistentArtifactRequirementType requirementType,
  }) {
    return PersistentArtifactPolicyEvaluationResult(
      policyId: policyId,
      policyVersion: policyVersion,
      policyType: policyType,
      status: PersistentArtifactOperationStatus.succeeded,
      requirementResults: [
        PersistentArtifactRequirementResult(
          requirementId: requirementId,
          requirementType: requirementType,
          status: PersistentArtifactRequirementStatus.satisfied,
        ),
      ],
    );
  }
}

class PersistentArtifactIntegrityEvaluator extends _BasePolicyEvaluator {
  const PersistentArtifactIntegrityEvaluator();
}

class PersistentArtifactStoragePolicyEvaluator extends _BasePolicyEvaluator {
  const PersistentArtifactStoragePolicyEvaluator();
}

class PersistentArtifactRetentionEvaluator extends _BasePolicyEvaluator {
  const PersistentArtifactRetentionEvaluator();
}

class PersistentArtifactReplicationEvaluator extends _BasePolicyEvaluator {
  const PersistentArtifactReplicationEvaluator();
}

class PersistentArtifactAvailabilityEvaluator {
  const PersistentArtifactAvailabilityEvaluator();
}

class PersistentArtifactLifecycleEvaluator {
  const PersistentArtifactLifecycleEvaluator();
}

class PersistentArtifactPublicationEvaluator {
  const PersistentArtifactPublicationEvaluator();
}

class PersistentArtifactDeletionEvaluator {
  const PersistentArtifactDeletionEvaluator();

  PersistentArtifactOperationResult evaluate({
    required PersistentArtifactEvaluationRequest request,
    required bool force,
  }) {
    final hasLegalHold = request.metadata['legalHold'] == 'true';
    final blocked = hasLegalHold;
    return PersistentArtifactOperationResult(
      resultId: 'delete:${request.evaluationId}',
      requestId: request.operationRequest.requestId,
      operationType: PersistentArtifactOperationType.requestDeletion,
      projectId: request.projectId,
      releaseId: request.releaseId,
      status: blocked
          ? PersistentArtifactOperationStatus.blocked
          : PersistentArtifactOperationStatus.succeeded,
      issues: blocked
          ? const [
              PersistentArtifactIssue(
                code: 'legal-hold-blocks-deletion',
                severity: PersistentArtifactIssueSeverity.critical,
                path: 'retention.legalHold',
                message: 'Legal hold blocks deletion even with force',
              ),
            ]
          : const [],
      metadata: {
        'force': '$force',
        'legalHold': '$hasLegalHold',
      },
    );
  }
}

class PersistentArtifactTombstoneBuilder {
  const PersistentArtifactTombstoneBuilder();
}

class PersistentArtifactPolicyEvaluators {
  const PersistentArtifactPolicyEvaluators({
    this.integrity = const PersistentArtifactIntegrityEvaluator(),
    this.storage = const PersistentArtifactStoragePolicyEvaluator(),
    this.retention = const PersistentArtifactRetentionEvaluator(),
    this.replication = const PersistentArtifactReplicationEvaluator(),
  });

  final PersistentArtifactIntegrityEvaluator integrity;
  final PersistentArtifactStoragePolicyEvaluator storage;
  final PersistentArtifactRetentionEvaluator retention;
  final PersistentArtifactReplicationEvaluator replication;
}

class PersistentArtifactInfrastructureSnapshotBuilder {
  const PersistentArtifactInfrastructureSnapshotBuilder({
    PersistentArtifactInfrastructureIdentityBuilder? identityBuilder,
    PersistentArtifactCanonicalSerializer? serializer,
  })  : _identityBuilder = identityBuilder ??
            const PersistentArtifactInfrastructureIdentityBuilder(),
        _serializer =
            serializer ?? const PersistentArtifactCanonicalSerializer();

  final PersistentArtifactInfrastructureIdentityBuilder _identityBuilder;
  final PersistentArtifactCanonicalSerializer _serializer;

  PersistentArtifactInfrastructureSnapshot build({
    required PersistentArtifactEvaluationRequest request,
    required CollectedPersistentArtifactMaterial material,
    required PersistentArtifactOperationResult operationResult,
    required String evaluatedAt,
    String? publishedAt,
  }) {
    final provisional = PersistentArtifactInfrastructureSnapshot(
      projectId: request.projectId,
      releaseId: request.releaseId,
      subjects: material.subjects,
      sourceReferences: material.sourceReferences,
      policyReferences: material.policies,
      operationRequests: [request.operationRequest],
      operationResults: [operationResult],
      status: publishedAt == null
          ? PersistentArtifactInfrastructureStatus.evaluated
          : PersistentArtifactInfrastructureStatus.published,
      createdAt: evaluatedAt,
      evaluatedAt: evaluatedAt,
      publishedAt: publishedAt,
      metadata: request.metadata,
    );
    final fingerprint = _serializer.snapshotFingerprint(provisional);
    final identity = _identityBuilder.buildIdentity(provisional);
    final snapshotId = _identityBuilder.buildSnapshotId(
      projectId: request.projectId,
      releaseId: request.releaseId ?? 'unknown',
      fingerprint: fingerprint,
    );
    return provisional.copyWith(
      identity: identity.copyWith(
        persistentArtifactInfrastructureId: snapshotId,
        snapshotFingerprint: fingerprint,
      ),
      metadata: {
        ...provisional.metadata,
        'snapshotId': snapshotId,
        'fingerprint': fingerprint,
      },
    );
  }
}

class PersistentArtifactEngine {
  const PersistentArtifactEngine({
    this.policyEvaluators = const PersistentArtifactPolicyEvaluators(),
    this.deletionEvaluator = const PersistentArtifactDeletionEvaluator(),
  });

  final PersistentArtifactPolicyEvaluators policyEvaluators;
  final PersistentArtifactDeletionEvaluator deletionEvaluator;

  PersistentArtifactOperationResult evaluateOperation({
    required PersistentArtifactEvaluationRequest request,
    required CollectedPersistentArtifactMaterial material,
  }) {
    final itemResults = request.operationRequest.artifactSubjects
        .map(
          (subject) => PersistentArtifactItemResult(
            artifactId: subject.subjectId,
            status: PersistentArtifactOperationStatus.succeeded,
          ),
        )
        .toList();
    return PersistentArtifactOperationResult(
      resultId: 'op:${request.evaluationId}',
      requestId: request.operationRequest.requestId,
      operationType: request.operationRequest.operationType,
      projectId: request.projectId,
      releaseId: request.releaseId,
      status: itemResults.isEmpty
          ? PersistentArtifactOperationStatus.partial
          : PersistentArtifactOperationStatus.succeeded,
      artifactResults: itemResults,
      completedAt: request.requestedAt,
    );
  }
}

class InMemoryPersistentArtifactSnapshotStore
    implements PersistentArtifactSnapshotStore {
  InMemoryPersistentArtifactSnapshotStore({
    PersistentArtifactCanonicalSerializer? serializer,
  }) : _serializer =
            serializer ?? const PersistentArtifactCanonicalSerializer();

  final PersistentArtifactCanonicalSerializer _serializer;
  final Map<String, PersistentArtifactInfrastructureSnapshot> _snapshots = {};

  @override
  Future<void> save(PersistentArtifactInfrastructureSnapshot snapshot) async {
    final id = _snapshotId(snapshot);
    final existing = _snapshots[id];
    if (existing != null) {
      if (_serializer.snapshotFingerprint(existing) !=
          _serializer.snapshotFingerprint(snapshot)) {
        throw PersistentArtifactSnapshotConflictException(id);
      }
      return;
    }
    _snapshots[id] = snapshot;
  }

  @override
  Future<PersistentArtifactInfrastructureSnapshot?> load(
      String snapshotId) async {
    return _snapshots[snapshotId];
  }

  @override
  Future<bool> exists(String snapshotId) async =>
      _snapshots.containsKey(snapshotId);

  @override
  Future<PersistentArtifactInfrastructureSnapshot?> latest({
    required String projectId,
    String? releaseId,
  }) async {
    final matches = _snapshots.values
        .where((s) => s.projectId == projectId)
        .where((s) => releaseId == null || s.releaseId == releaseId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<List<PersistentArtifactInfrastructureSnapshot>> query(
    PersistentArtifactQuery query,
  ) async {
    var values = _snapshots.values.where((snapshot) {
      if (query.projectId != null && snapshot.projectId != query.projectId)
        return false;
      if (query.releaseId != null && snapshot.releaseId != query.releaseId)
        return false;
      if (query.status != null && snapshot.status != query.status) return false;
      if (query.artifactId != null &&
          !snapshot.subjects.any((s) => s.subjectId == query.artifactId))
        return false;
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (query.offset != null && query.offset! > 0) {
      if (query.offset! >= values.length) return const [];
      values = values.sublist(query.offset!);
    }
    if (query.limit != null && query.limit! < values.length) {
      values = values.sublist(0, query.limit!);
    }
    return List.unmodifiable(values);
  }

  @override
  Future<void> invalidate(String snapshotId) async {
    _snapshots.remove(snapshotId);
  }

  @override
  Future<void> clear() async => _snapshots.clear();

  @override
  Future<int> count() async => _snapshots.length;

  String _snapshotId(PersistentArtifactInfrastructureSnapshot snapshot) {
    return snapshot.identity?.persistentArtifactInfrastructureId ??
        snapshot.metadata['snapshotId'] ??
        _serializer.snapshotFingerprint(snapshot);
  }
}

class PlatformPersistentArtifactProvider implements PersistentArtifactProvider {
  PlatformPersistentArtifactProvider({
    required PersistentArtifactPolicyRegistry policyRegistry,
    required PersistentArtifactSourceResolver sourceResolver,
    required PersistentArtifactSnapshotStore store,
    PersistentArtifactCollector? collector,
    PersistentArtifactEngine? engine,
    PersistentArtifactInfrastructureSnapshotBuilder? snapshotBuilder,
    PersistentArtifactContentStore? contentStore,
    PersistentArtifactBackendRegistry? backendRegistry,
  })  : _policyRegistry = policyRegistry,
        _sourceResolver = sourceResolver,
        _store = store,
        _collector = collector ?? const PersistentArtifactCollector(),
        _engine = engine ?? const PersistentArtifactEngine(),
        _snapshotBuilder = snapshotBuilder ??
            const PersistentArtifactInfrastructureSnapshotBuilder(),
        _contentStore = contentStore,
        _backendRegistry = backendRegistry,
        _physicalOperationsService = backendRegistry == null
            ? null
            : PersistentArtifactPhysicalOperationsService(
                registry: backendRegistry,
              ),
        _cloudOperationsService = backendRegistry == null
            ? null
            : PersistentArtifactCloudOperationsService(
                registry: backendRegistry,
              );

  final PersistentArtifactPolicyRegistry _policyRegistry;
  final PersistentArtifactSourceResolver _sourceResolver;
  final PersistentArtifactSnapshotStore _store;
  final PersistentArtifactCollector _collector;
  final PersistentArtifactEngine _engine;
  final PersistentArtifactInfrastructureSnapshotBuilder _snapshotBuilder;
  final PersistentArtifactContentStore? _contentStore;
  final PersistentArtifactBackendRegistry? _backendRegistry;
  final PersistentArtifactPhysicalOperationsService? _physicalOperationsService;
  final PersistentArtifactCloudOperationsService? _cloudOperationsService;

  @override
  Future<PersistentArtifactEvaluationResult> evaluate(
    PersistentArtifactEvaluationRequest request,
  ) async =>
      _evaluate(request, persist: false);

  @override
  Future<PersistentArtifactEvaluationResult> evaluateAndPublish(
    PersistentArtifactEvaluationRequest request,
  ) async =>
      _evaluate(request, persist: true);

  Future<PersistentArtifactEvaluationResult> _evaluate(
    PersistentArtifactEvaluationRequest request, {
    required bool persist,
  }) async {
    final _ = _policyRegistry.list();
    final sources = await _sourceResolver.resolveAll(request);
    final context = PersistentArtifactOperationContext(
      operation: persist
          ? PersistentArtifactOperationType.publish
          : PersistentArtifactOperationType.persist,
      request: request,
      sources: sources,
      material: const CollectedPersistentArtifactMaterial(),
    );
    final material = _collector.collect(context);
    final operationResult = _engine.evaluateOperation(
      request: request,
      material: material,
    );
    final snapshot = _snapshotBuilder.build(
      request: request,
      material: material,
      operationResult: operationResult,
      evaluatedAt: request.requestedAt,
      publishedAt: persist ? request.requestedAt : null,
    );
    if (persist) {
      await _store.save(snapshot);
    }
    return PersistentArtifactEvaluationResult(
      status:
          sources.status == PersistentArtifactSourceResolutionStatus.complete
              ? PersistentArtifactEvaluationStatus.success
              : PersistentArtifactEvaluationStatus.partial,
      evaluationId: request.evaluationId,
      projectId: request.projectId,
      releaseId: request.releaseId,
      operationResult: operationResult,
      snapshot: snapshot,
      snapshotReference: PersistentArtifactSnapshotReference(
        snapshotId: snapshot.identity?.persistentArtifactInfrastructureId ??
            snapshot.metadata['snapshotId'] ??
            request.evaluationId,
        projectId: snapshot.projectId,
        releaseId: snapshot.releaseId,
        fingerprint: snapshot.metadata['fingerprint'] ?? '',
        createdAt: snapshot.createdAt,
      ),
      sourceResolutionSummary: sources,
      evaluatedAt: request.requestedAt,
      metadata: const {
        'declarativeBoundaries': 'no-physical-storage-by-default',
      },
    );
  }

  @override
  Future<void> publish(PersistentArtifactInfrastructureSnapshot snapshot) =>
      _store.save(snapshot);

  @override
  Future<PersistentArtifactInfrastructureSnapshot?> load(String snapshotId) =>
      _store.load(snapshotId);

  @override
  Future<PersistentArtifactInfrastructureSnapshot?> latest({
    required String projectId,
    String? releaseId,
  }) =>
      _store.latest(projectId: projectId, releaseId: releaseId);

  @override
  Future<List<PersistentArtifactInfrastructureSnapshot>> query(
    PersistentArtifactQuery query,
  ) =>
      _store.query(query);

  @override
  Future<void> invalidate(String snapshotId) async {
    if (!await _store.exists(snapshotId)) {
      throw PersistentArtifactNotFoundException(snapshotId);
    }
    await _store.invalidate(snapshotId);
  }

  @override
  Future<PersistentArtifactOperationResult> evaluateIntegrity(
    PersistentArtifactEvaluationRequest request,
  ) async =>
      _engine.evaluateOperation(
        request: request,
        material: const CollectedPersistentArtifactMaterial(),
      );

  @override
  Future<PersistentArtifactOperationResult> evaluateRetention(
    PersistentArtifactEvaluationRequest request,
  ) async =>
      _engine.evaluateOperation(
        request: request,
        material: const CollectedPersistentArtifactMaterial(),
      );

  @override
  Future<PersistentArtifactOperationResult> evaluateReplication(
    PersistentArtifactEvaluationRequest request,
  ) async =>
      _engine.evaluateOperation(
        request: request,
        material: const CollectedPersistentArtifactMaterial(),
      );

  @override
  Future<PersistentArtifactOperationResult> evaluateAvailability(
    PersistentArtifactEvaluationRequest request,
  ) async =>
      _engine.evaluateOperation(
        request: request,
        material: const CollectedPersistentArtifactMaterial(),
      );

  @override
  Future<PersistentArtifactOperationResult> evaluateDeletion(
    PersistentArtifactEvaluationRequest request, {
    bool force = false,
  }) async =>
      _engine.deletionEvaluator.evaluate(request: request, force: force);

  @override
  Future<PersistentArtifactOperationResult> buildTombstone(
    PersistentArtifactEvaluationRequest request,
  ) async =>
      PersistentArtifactOperationResult(
        resultId: 'tombstone:${request.evaluationId}',
        requestId: request.operationRequest.requestId,
        operationType: PersistentArtifactOperationType.snapshot,
        projectId: request.projectId,
        releaseId: request.releaseId,
        status: PersistentArtifactOperationStatus.succeeded,
        metadata: const {'tombstone': 'built'},
      );

  @override
  Future<PersistentArtifactOperationResult> evaluateLifecycle(
    PersistentArtifactEvaluationRequest request,
  ) async =>
      _engine.evaluateOperation(
        request: request,
        material: const CollectedPersistentArtifactMaterial(),
      );

  @override
  Future<PersistentArtifactOperationResult> evaluatePublication(
    PersistentArtifactEvaluationRequest request,
  ) async =>
      _engine.evaluateOperation(
        request: request,
        material: const CollectedPersistentArtifactMaterial(),
      );

  @override
  Future<PersistentArtifactContentHandle> writeContent({
    required String contentId,
    required List<int> bytes,
  }) async {
    if (_contentStore == null) {
      throw const PersistentArtifactContentUnavailableException(
        'writeContent unavailable without backend',
      );
    }
    return _contentStore!.writeContent(
      descriptor: PersistentArtifactContentDescriptor(
        contentId: contentId,
        mediaType: 'application/octet-stream',
        format: PersistentArtifactFormat.binary,
        encoding: PersistentArtifactEncoding.none,
        compression: PersistentArtifactCompression.none,
        contentFingerprint: PersistentArtifactFingerprint.fromComparableJson(
            {'contentId': 'x'}),
      ),
      bytes: bytes,
    );
  }

  @override
  Future<List<int>> readContent(PersistentArtifactContentHandle handle) async {
    if (_contentStore == null) {
      throw const PersistentArtifactContentUnavailableException(
        'readContent unavailable without backend',
      );
    }
    final bytes = await _contentStore!.readContent(handle);
    return bytes ?? const [];
  }

  @override
  Future<void> deleteContent(
    PersistentArtifactContentHandle handle, {
    bool force = false,
  }) async {
    final store = _contentStore;
    if (store == null) {
      throw const PersistentArtifactContentUnavailableException(
        'deleteContent unavailable without backend',
      );
    }
    await store.deleteContent(handle);
  }

  @override
  Future<PersistentArtifactCloudObjectMetadataResult> putCloudObject(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      _cloudOperationsService?.putObject(request) ??
      Future.value(
        PersistentArtifactCloudObjectMetadataResult(
          status: PersistentArtifactCloudOperationStatus.unavailable,
          backendId: request.backendId,
          operation: request.operationType,
          correlationId: 'pa-cloud:put:unavailable',
        ),
      );

  @override
  Future<PersistentArtifactCloudObjectMetadataResult> getCloudObject(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      _cloudOperationsService?.getObject(request) ??
      Future.value(
        PersistentArtifactCloudObjectMetadataResult(
          status: PersistentArtifactCloudOperationStatus.unavailable,
          backendId: request.backendId,
          operation: request.operationType,
          correlationId: 'pa-cloud:get:unavailable',
        ),
      );

  @override
  Future<PersistentArtifactCloudObjectMetadataResult> headCloudObject(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      _cloudOperationsService?.headObject(request) ??
      Future.value(
        PersistentArtifactCloudObjectMetadataResult(
          status: PersistentArtifactCloudOperationStatus.unavailable,
          backendId: request.backendId,
          operation: request.operationType,
          correlationId: 'pa-cloud:head:unavailable',
        ),
      );

  @override
  Future<PersistentArtifactCloudObjectMetadataResult> cloudObjectExists(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      _cloudOperationsService?.objectExists(request) ??
      Future.value(
        PersistentArtifactCloudObjectMetadataResult(
          status: PersistentArtifactCloudOperationStatus.unavailable,
          backendId: request.backendId,
          operation: request.operationType,
          correlationId: 'pa-cloud:exists:unavailable',
          exists: false,
        ),
      );

  @override
  Future<PersistentArtifactCloudObjectListResult> listCloudObjects(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      _cloudOperationsService?.listObjects(request) ??
      Future.value(
        PersistentArtifactCloudObjectListResult(
          status: PersistentArtifactCloudOperationStatus.unavailable,
          backendId: request.backendId,
          correlationId: 'pa-cloud:list:unavailable',
        ),
      );

  @override
  Future<PersistentArtifactCloudObjectMetadataResult> deleteCloudObject(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      _cloudOperationsService?.deleteObject(request) ??
      Future.value(
        PersistentArtifactCloudObjectMetadataResult(
          status: PersistentArtifactCloudOperationStatus.unavailable,
          backendId: request.backendId,
          operation: request.operationType,
          correlationId: 'pa-cloud:delete:unavailable',
        ),
      );

  @override
  Future<PersistentArtifactCloudObjectMetadataResult> copyCloudObject(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      _cloudOperationsService?.copyObject(request) ??
      Future.value(
        PersistentArtifactCloudObjectMetadataResult(
          status: PersistentArtifactCloudOperationStatus.unavailable,
          backendId: request.backendId,
          operation: request.operationType,
          correlationId: 'pa-cloud:copy:unavailable',
        ),
      );

  @override
  Future<PersistentArtifactCloudMultipartOperationResult> beginCloudMultipart(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      _cloudOperationsService?.beginMultipart(request) ??
      Future.value(
        PersistentArtifactCloudMultipartOperationResult(
          status: PersistentArtifactCloudOperationStatus.unavailable,
          backendId: request.backendId,
          operation: request.operationType,
          correlationId: 'pa-cloud:begin-multipart:unavailable',
        ),
      );

  @override
  Future<PersistentArtifactCloudMultipartOperationResult> uploadCloudPart(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      _cloudOperationsService?.uploadPart(request) ??
      Future.value(
        PersistentArtifactCloudMultipartOperationResult(
          status: PersistentArtifactCloudOperationStatus.unavailable,
          backendId: request.backendId,
          operation: request.operationType,
          correlationId: 'pa-cloud:upload-part:unavailable',
        ),
      );

  @override
  Future<PersistentArtifactCloudMultipartOperationResult>
      completeCloudMultipart(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
          _cloudOperationsService?.completeMultipart(request) ??
          Future.value(
            PersistentArtifactCloudMultipartOperationResult(
              status: PersistentArtifactCloudOperationStatus.unavailable,
              backendId: request.backendId,
              operation: request.operationType,
              correlationId: 'pa-cloud:complete-multipart:unavailable',
            ),
          );

  @override
  Future<PersistentArtifactCloudMultipartOperationResult> abortCloudMultipart(
    PersistentArtifactCloudOperationRequest request,
  ) async =>
      _cloudOperationsService?.abortMultipart(request) ??
      Future.value(
        PersistentArtifactCloudMultipartOperationResult(
          status: PersistentArtifactCloudOperationStatus.unavailable,
          backendId: request.backendId,
          operation: request.operationType,
          correlationId: 'pa-cloud:abort-multipart:unavailable',
        ),
      );

  @override
  Future<WritePhysicalContentResult> writePhysicalContent(
    WritePhysicalContentRequest request,
  ) async =>
      _physicalOperationsService?.writePhysicalContent(request) ??
      Future.value(
        const WritePhysicalContentResult(
          status: PersistentArtifactPhysicalOperationStatus.unavailable,
        ),
      );

  @override
  Future<ReadPhysicalContentResult> readPhysicalContent(
    ReadPhysicalContentRequest request,
  ) async =>
      _physicalOperationsService?.readPhysicalContent(request) ??
      Future.value(
        const ReadPhysicalContentResult(
          status: PersistentArtifactPhysicalOperationStatus.unavailable,
        ),
      );

  @override
  Future<ContentExistsResult> contentExists(
          ContentExistsRequest request) async =>
      _physicalOperationsService?.contentExists(request) ??
      Future.value(
        const ContentExistsResult(
          status: PersistentArtifactPhysicalOperationStatus.unavailable,
          exists: false,
        ),
      );

  @override
  Future<ContentMetadataResult> contentMetadata(
    ContentMetadataRequest request,
  ) async =>
      _physicalOperationsService?.contentMetadata(request) ??
      Future.value(
        const ContentMetadataResult(
          status: PersistentArtifactPhysicalOperationStatus.unavailable,
        ),
      );

  @override
  Future<SavePhysicalManifestResult> savePhysicalManifest(
    SavePhysicalManifestRequest request,
  ) async =>
      _physicalOperationsService?.savePhysicalManifest(request) ??
      Future.value(
        SavePhysicalManifestResult(
          status: PersistentArtifactPhysicalOperationStatus.unavailable,
          manifestId: request.manifest.manifestId,
        ),
      );

  @override
  Future<LoadPhysicalManifestResult> loadPhysicalManifest(
    LoadPhysicalManifestRequest request,
  ) async =>
      _physicalOperationsService?.loadPhysicalManifest(request) ??
      Future.value(
        const LoadPhysicalManifestResult(
          status: PersistentArtifactPhysicalOperationStatus.unavailable,
        ),
      );

  @override
  Future<LoadPhysicalManifestResult> latestPhysicalManifest(
    LatestPhysicalManifestRequest request,
  ) async =>
      _physicalOperationsService?.latestPhysicalManifest(request) ??
      Future.value(
        const LoadPhysicalManifestResult(
          status: PersistentArtifactPhysicalOperationStatus.unavailable,
        ),
      );

  @override
  Future<QueryPhysicalManifestsResult> queryPhysicalManifests(
    QueryPhysicalManifestsRequest request,
  ) async =>
      _physicalOperationsService?.queryPhysicalManifests(request) ??
      Future.value(
        const QueryPhysicalManifestsResult(
          status: PersistentArtifactPhysicalOperationStatus.unavailable,
        ),
      );

  @override
  Future<PersistentArtifactPhysicalResult> invalidatePhysicalManifest(
    InvalidatePhysicalManifestRequest request,
  ) async =>
      _physicalOperationsService?.invalidatePhysicalManifest(request) ??
      Future.value(
        const PersistentArtifactPhysicalResult(
          status: PersistentArtifactPhysicalOperationStatus.unavailable,
        ),
      );

  @override
  Future<ResolvePhysicalLocationResult> resolvePhysicalLocation(
    ResolvePhysicalLocationRequest request,
  ) async =>
      _physicalOperationsService?.resolvePhysicalLocation(request) ??
      Future.value(
        const ResolvePhysicalLocationResult(
          status: PersistentArtifactPhysicalOperationStatus.unavailable,
        ),
      );

  @override
  Future<QuarantineContentResult> quarantineContent(
    QuarantineContentRequest request,
  ) async =>
      _physicalOperationsService?.quarantineContent(request) ??
      Future.value(
        const QuarantineContentResult(
          status: PersistentArtifactPhysicalOperationStatus.unavailable,
          quarantined: false,
        ),
      );

  @override
  Future<RecoveryInspectionResult> inspectInterruptedOperations(
    String backendId,
  ) async =>
      _physicalOperationsService?.inspectInterruptedOperations(backendId) ??
      Future.value(
        const RecoveryInspectionResult(
          status: PersistentArtifactPhysicalOperationStatus.unavailable,
        ),
      );

  @override
  Future<RecoveryInspectionResult> inspectOrphanTemporaryObjects(
    String backendId,
  ) async =>
      _physicalOperationsService?.inspectOrphanTemporaryObjects(backendId) ??
      Future.value(
        const RecoveryInspectionResult(
          status: PersistentArtifactPhysicalOperationStatus.unavailable,
        ),
      );

  @override
  Future<PersistentArtifactPhysicalResult> recoverTemporaryObject(
    RecoverTemporaryObjectRequest request,
  ) async =>
      _physicalOperationsService?.recoverTemporaryObject(request) ??
      Future.value(
        const PersistentArtifactPhysicalResult(
          status: PersistentArtifactPhysicalOperationStatus.unavailable,
        ),
      );

  @override
  Future<PersistentArtifactPhysicalResult> discardTemporaryObject(
    DiscardTemporaryObjectRequest request,
  ) async =>
      _physicalOperationsService?.discardTemporaryObject(request) ??
      Future.value(
        const PersistentArtifactPhysicalResult(
          status: PersistentArtifactPhysicalOperationStatus.unavailable,
        ),
      );

  @override
  Future<PersistentArtifactPhysicalResult> unregisterBackend(
    UnregisterBackendRequest request,
  ) async {
    final removed = _backendRegistry?.unregister(request.backendId) ?? false;
    return PersistentArtifactPhysicalResult(
      status: removed
          ? PersistentArtifactPhysicalOperationStatus.succeeded
          : PersistentArtifactPhysicalOperationStatus.notFound,
    );
  }
}
