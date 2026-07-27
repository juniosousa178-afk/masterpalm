import 'persistent_artifact_availability_record.dart';
import 'persistent_artifact_content_descriptor.dart';
import 'persistent_artifact_deletion_models.dart';
import 'persistent_artifact_encryption_descriptor.dart';
import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';
import 'persistent_artifact_identity.dart';
import 'persistent_artifact_infrastructure_identity.dart';
import 'persistent_artifact_integrity_record.dart';
import 'persistent_artifact_lifecycle_record.dart';
import 'persistent_artifact_location_reference.dart';
import 'persistent_artifact_manifest.dart';
import 'persistent_artifact_operation_models.dart';
import 'persistent_artifact_policy_models.dart';
import 'persistent_artifact_publication_record.dart';
import 'persistent_artifact_reference_models.dart';
import 'persistent_artifact_replica_record.dart';
import 'persistent_artifact_replication_requirement.dart';
import 'persistent_artifact_retention_record.dart';
import 'persistent_artifact_subject.dart';
import 'persistent_artifact_version.dart';

/// Published aggregate snapshot for Persistent Artifact infrastructure.
///
/// Immutable descriptor only — no persistence, I/O, or physical operations.
/// Operational timestamps are excluded from comparable identity.
class PersistentArtifactInfrastructureSnapshot {
  const PersistentArtifactInfrastructureSnapshot({
    required this.projectId,
    required this.status,
    required this.createdAt,
    this.releaseId,
    this.subjects = const [],
    this.contentDescriptors = const [],
    this.artifactIdentities = const [],
    this.versions = const [],
    this.manifests = const [],
    this.locations = const [],
    this.integrityRecords = const [],
    this.encryptionDescriptors = const [],
    this.publications = const [],
    this.lifecycleRecords = const [],
    this.retentionPolicies = const [],
    this.storagePolicies = const [],
    this.replicationRequirements = const [],
    this.replicas = const [],
    this.availabilityRecords = const [],
    this.retentionRecords = const [],
    this.deletionRequests = const [],
    this.deletionResults = const [],
    this.tombstones = const [],
    this.sourceReferences = const [],
    this.policyReferences = const [],
    this.operationRequests = const [],
    this.operationResults = const [],
    this.identity,
    this.evaluatedAt,
    this.publishedAt,
    this.metadata = const {},
  });

  final String projectId;
  final String? releaseId;
  final List<PersistentArtifactSubject> subjects;
  final List<PersistentArtifactContentDescriptor> contentDescriptors;
  final List<PersistentArtifactIdentity> artifactIdentities;
  final List<PersistentArtifactVersion> versions;
  final List<PersistentArtifactManifest> manifests;
  final List<PersistentArtifactLocationReference> locations;
  final List<PersistentArtifactIntegrityRecord> integrityRecords;
  final List<PersistentArtifactEncryptionDescriptor> encryptionDescriptors;
  final List<PersistentArtifactPublicationRecord> publications;
  final List<PersistentArtifactLifecycleRecord> lifecycleRecords;
  final List<PersistentArtifactRetentionPolicy> retentionPolicies;
  final List<PersistentArtifactStoragePolicy> storagePolicies;
  final List<PersistentArtifactReplicationRequirement> replicationRequirements;
  final List<PersistentArtifactReplicaRecord> replicas;
  final List<PersistentArtifactAvailabilityRecord> availabilityRecords;
  final List<PersistentArtifactRetentionRecord> retentionRecords;
  final List<PersistentArtifactDeletionRequest> deletionRequests;
  final List<PersistentArtifactDeletionResult> deletionResults;
  final List<PersistentArtifactTombstone> tombstones;
  final List<PersistentArtifactSourceReference> sourceReferences;
  final List<PersistentArtifactPolicyReference> policyReferences;
  final List<PersistentArtifactOperationRequest> operationRequests;
  final List<PersistentArtifactOperationResult> operationResults;
  final PersistentArtifactInfrastructureIdentity? identity;
  final PersistentArtifactInfrastructureStatus status;
  final String createdAt;
  final String? evaluatedAt;
  final String? publishedAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (subjects.isNotEmpty)
          'subjects': subjects.map((e) => e.toJson()).toList(),
        if (contentDescriptors.isNotEmpty)
          'contentDescriptors':
              contentDescriptors.map((e) => e.toJson()).toList(),
        if (artifactIdentities.isNotEmpty)
          'artifactIdentities':
              artifactIdentities.map((e) => e.toJson()).toList(),
        if (versions.isNotEmpty)
          'versions': versions.map((e) => e.toJson()).toList(),
        if (manifests.isNotEmpty)
          'manifests': manifests.map((e) => e.toJson()).toList(),
        if (locations.isNotEmpty)
          'locations': locations.map((e) => e.toJson()).toList(),
        if (integrityRecords.isNotEmpty)
          'integrityRecords': integrityRecords.map((e) => e.toJson()).toList(),
        if (encryptionDescriptors.isNotEmpty)
          'encryptionDescriptors':
              encryptionDescriptors.map((e) => e.toJson()).toList(),
        if (publications.isNotEmpty)
          'publications': publications.map((e) => e.toJson()).toList(),
        if (lifecycleRecords.isNotEmpty)
          'lifecycleRecords': lifecycleRecords.map((e) => e.toJson()).toList(),
        if (retentionPolicies.isNotEmpty)
          'retentionPolicies':
              retentionPolicies.map((e) => e.toJson()).toList(),
        if (storagePolicies.isNotEmpty)
          'storagePolicies': storagePolicies.map((e) => e.toJson()).toList(),
        if (replicationRequirements.isNotEmpty)
          'replicationRequirements':
              replicationRequirements.map((e) => e.toJson()).toList(),
        if (replicas.isNotEmpty)
          'replicas': replicas.map((e) => e.toJson()).toList(),
        if (availabilityRecords.isNotEmpty)
          'availabilityRecords':
              availabilityRecords.map((e) => e.toJson()).toList(),
        if (retentionRecords.isNotEmpty)
          'retentionRecords': retentionRecords.map((e) => e.toJson()).toList(),
        if (deletionRequests.isNotEmpty)
          'deletionRequests': deletionRequests.map((e) => e.toJson()).toList(),
        if (deletionResults.isNotEmpty)
          'deletionResults': deletionResults.map((e) => e.toJson()).toList(),
        if (tombstones.isNotEmpty)
          'tombstones': tombstones.map((e) => e.toJson()).toList(),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        if (policyReferences.isNotEmpty)
          'policyReferences': policyReferences.map((e) => e.toJson()).toList(),
        if (operationRequests.isNotEmpty)
          'operationRequests':
              operationRequests.map((e) => e.toJson()).toList(),
        if (operationResults.isNotEmpty)
          'operationResults': operationResults.map((e) => e.toJson()).toList(),
        if (identity != null) 'identity': identity!.toJson(),
        'status': status.wireName,
        'createdAt': createdAt,
        if (evaluatedAt != null) 'evaluatedAt': evaluatedAt,
        if (publishedAt != null) 'publishedAt': publishedAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactInfrastructureSnapshot.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactInfrastructureSnapshot(
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      subjects: List.unmodifiable(
        (json['subjects'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactSubject.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      contentDescriptors: List.unmodifiable(
        (json['contentDescriptors'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactContentDescriptor.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      artifactIdentities: List.unmodifiable(
        (json['artifactIdentities'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactIdentity.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      versions: List.unmodifiable(
        (json['versions'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactVersion.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      manifests: List.unmodifiable(
        (json['manifests'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactManifest.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      locations: List.unmodifiable(
        (json['locations'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactLocationReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      integrityRecords: List.unmodifiable(
        (json['integrityRecords'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactIntegrityRecord.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      encryptionDescriptors: List.unmodifiable(
        (json['encryptionDescriptors'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactEncryptionDescriptor.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      publications: List.unmodifiable(
        (json['publications'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactPublicationRecord.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      lifecycleRecords: List.unmodifiable(
        (json['lifecycleRecords'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactLifecycleRecord.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      retentionPolicies: List.unmodifiable(
        (json['retentionPolicies'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactRetentionPolicy.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      storagePolicies: List.unmodifiable(
        (json['storagePolicies'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactStoragePolicy.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      replicationRequirements: List.unmodifiable(
        (json['replicationRequirements'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactReplicationRequirement.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      replicas: List.unmodifiable(
        (json['replicas'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactReplicaRecord.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      availabilityRecords: List.unmodifiable(
        (json['availabilityRecords'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactAvailabilityRecord.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      retentionRecords: List.unmodifiable(
        (json['retentionRecords'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactRetentionRecord.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      deletionRequests: List.unmodifiable(
        (json['deletionRequests'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactDeletionRequest.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      deletionResults: List.unmodifiable(
        (json['deletionResults'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactDeletionResult.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      tombstones: List.unmodifiable(
        (json['tombstones'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactTombstone.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      sourceReferences: List.unmodifiable(
        (json['sourceReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactSourceReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      policyReferences: List.unmodifiable(
        (json['policyReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactPolicyReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      operationRequests: List.unmodifiable(
        (json['operationRequests'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactOperationRequest.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      operationResults: List.unmodifiable(
        (json['operationResults'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactOperationResult.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      identity: json['identity'] != null
          ? PersistentArtifactInfrastructureIdentity.fromJson(
              json['identity'] as Map<String, dynamic>,
            )
          : null,
      status: PersistentArtifactInfrastructureStatusX.fromWireName(
        json['status'] as String,
      ),
      createdAt: json['createdAt'] as String,
      evaluatedAt: json['evaluatedAt'] as String?,
      publishedAt: json['publishedAt'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (subjects.isNotEmpty)
          'subjects': paSortedComparableList(
            subjects.map((e) => e.toComparableJson()),
            'subjectId',
          ),
        if (contentDescriptors.isNotEmpty)
          'contentDescriptors': paSortedComparableList(
            contentDescriptors.map((e) => e.toComparableJson()),
            'contentId',
          ),
        if (artifactIdentities.isNotEmpty)
          'artifactIdentities': paSortedComparableList(
            artifactIdentities.map((e) => e.toComparableJson()),
            'artifactId',
          ),
        if (versions.isNotEmpty)
          'versions': paSortedComparableList(
            versions.map((e) => e.toComparableJson()),
            'versionId',
          ),
        if (manifests.isNotEmpty)
          'manifests': paSortedComparableList(
            manifests.map((e) => e.toComparableJson()),
            'manifestId',
          ),
        if (locations.isNotEmpty)
          'locations': paSortedComparableList(
            locations.map((e) => e.toComparableJson()),
            'locationId',
          ),
        if (integrityRecords.isNotEmpty)
          'integrityRecords': paSortedComparableList(
            integrityRecords.map((e) => e.toComparableJson()),
            'integrityRecordId',
          ),
        if (encryptionDescriptors.isNotEmpty)
          'encryptionDescriptors':
              (encryptionDescriptors.map((e) => e.toComparableJson()).toList()
                ..sort(
                  (a, b) => (a['encryptionStatus'] as String)
                      .compareTo(b['encryptionStatus'] as String),
                )),
        if (publications.isNotEmpty)
          'publications': paSortedComparableList(
            publications.map((e) => e.toComparableJson()),
            'publicationId',
          ),
        if (lifecycleRecords.isNotEmpty)
          'lifecycleRecords': paSortedComparableList(
            lifecycleRecords.map((e) => e.toComparableJson()),
            'lifecycleRecordId',
          ),
        if (retentionPolicies.isNotEmpty)
          'retentionPolicies': paSortedComparableList(
            retentionPolicies.map((e) => e.toComparableJson()),
            'policyId',
          ),
        if (storagePolicies.isNotEmpty)
          'storagePolicies': paSortedComparableList(
            storagePolicies.map((e) => e.toComparableJson()),
            'policyId',
          ),
        if (replicationRequirements.isNotEmpty)
          'replicationRequirements': paSortedComparableList(
            replicationRequirements.map((e) => e.toComparableJson()),
            'requirementId',
          ),
        if (replicas.isNotEmpty)
          'replicas': paSortedComparableList(
            replicas.map((e) => e.toComparableJson()),
            'replicaId',
          ),
        if (availabilityRecords.isNotEmpty)
          'availabilityRecords': paSortedComparableList(
            availabilityRecords.map((e) => e.toComparableJson()),
            'availabilityRecordId',
          ),
        if (retentionRecords.isNotEmpty)
          'retentionRecords': paSortedComparableList(
            retentionRecords.map((e) => e.toComparableJson()),
            'retentionRecordId',
          ),
        if (deletionRequests.isNotEmpty)
          'deletionRequests': paSortedComparableList(
            deletionRequests.map((e) => e.toComparableJson()),
            'deletionRequestId',
          ),
        if (deletionResults.isNotEmpty)
          'deletionResults': paSortedComparableList(
            deletionResults.map((e) => e.toComparableJson()),
            'deletionResultId',
          ),
        if (tombstones.isNotEmpty)
          'tombstones': paSortedComparableList(
            tombstones.map((e) => e.toComparableJson()),
            'tombstoneId',
          ),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': paSortedComparableList(
            sourceReferences.map((e) => e.toComparableJson()),
            'sourceId',
          ),
        if (policyReferences.isNotEmpty)
          'policyReferences': paSortedComparableList(
            policyReferences.map((e) => e.toComparableJson()),
            'policyId',
          ),
        if (operationRequests.isNotEmpty)
          'operationRequests': paSortedComparableList(
            operationRequests.map((e) => e.toComparableJson()),
            'requestId',
          ),
        if (operationResults.isNotEmpty)
          'operationResults': paSortedComparableList(
            operationResults.map((e) => e.toComparableJson()),
            'resultId',
          ),
        if (identity != null) 'identity': identity!.toComparableJson(),
        'status': status.wireName,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactInfrastructureSnapshot copyWith({
    String? projectId,
    String? releaseId,
    List<PersistentArtifactSubject>? subjects,
    List<PersistentArtifactContentDescriptor>? contentDescriptors,
    List<PersistentArtifactIdentity>? artifactIdentities,
    List<PersistentArtifactVersion>? versions,
    List<PersistentArtifactManifest>? manifests,
    List<PersistentArtifactLocationReference>? locations,
    List<PersistentArtifactIntegrityRecord>? integrityRecords,
    List<PersistentArtifactEncryptionDescriptor>? encryptionDescriptors,
    List<PersistentArtifactPublicationRecord>? publications,
    List<PersistentArtifactLifecycleRecord>? lifecycleRecords,
    List<PersistentArtifactRetentionPolicy>? retentionPolicies,
    List<PersistentArtifactStoragePolicy>? storagePolicies,
    List<PersistentArtifactReplicationRequirement>? replicationRequirements,
    List<PersistentArtifactReplicaRecord>? replicas,
    List<PersistentArtifactAvailabilityRecord>? availabilityRecords,
    List<PersistentArtifactRetentionRecord>? retentionRecords,
    List<PersistentArtifactDeletionRequest>? deletionRequests,
    List<PersistentArtifactDeletionResult>? deletionResults,
    List<PersistentArtifactTombstone>? tombstones,
    List<PersistentArtifactSourceReference>? sourceReferences,
    List<PersistentArtifactPolicyReference>? policyReferences,
    List<PersistentArtifactOperationRequest>? operationRequests,
    List<PersistentArtifactOperationResult>? operationResults,
    PersistentArtifactInfrastructureIdentity? identity,
    PersistentArtifactInfrastructureStatus? status,
    String? createdAt,
    String? evaluatedAt,
    String? publishedAt,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactInfrastructureSnapshot(
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      subjects: subjects ?? this.subjects,
      contentDescriptors: contentDescriptors ?? this.contentDescriptors,
      artifactIdentities: artifactIdentities ?? this.artifactIdentities,
      versions: versions ?? this.versions,
      manifests: manifests ?? this.manifests,
      locations: locations ?? this.locations,
      integrityRecords: integrityRecords ?? this.integrityRecords,
      encryptionDescriptors:
          encryptionDescriptors ?? this.encryptionDescriptors,
      publications: publications ?? this.publications,
      lifecycleRecords: lifecycleRecords ?? this.lifecycleRecords,
      retentionPolicies: retentionPolicies ?? this.retentionPolicies,
      storagePolicies: storagePolicies ?? this.storagePolicies,
      replicationRequirements:
          replicationRequirements ?? this.replicationRequirements,
      replicas: replicas ?? this.replicas,
      availabilityRecords: availabilityRecords ?? this.availabilityRecords,
      retentionRecords: retentionRecords ?? this.retentionRecords,
      deletionRequests: deletionRequests ?? this.deletionRequests,
      deletionResults: deletionResults ?? this.deletionResults,
      tombstones: tombstones ?? this.tombstones,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      policyReferences: policyReferences ?? this.policyReferences,
      operationRequests: operationRequests ?? this.operationRequests,
      operationResults: operationResults ?? this.operationResults,
      identity: identity ?? this.identity,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
      publishedAt: publishedAt ?? this.publishedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactInfrastructureSnapshot &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          paListEquals(subjects, other.subjects) &&
          paListEquals(contentDescriptors, other.contentDescriptors) &&
          paListEquals(artifactIdentities, other.artifactIdentities) &&
          paListEquals(versions, other.versions) &&
          paListEquals(manifests, other.manifests) &&
          paListEquals(locations, other.locations) &&
          paListEquals(integrityRecords, other.integrityRecords) &&
          paListEquals(encryptionDescriptors, other.encryptionDescriptors) &&
          paListEquals(publications, other.publications) &&
          paListEquals(lifecycleRecords, other.lifecycleRecords) &&
          paListEquals(retentionPolicies, other.retentionPolicies) &&
          paListEquals(storagePolicies, other.storagePolicies) &&
          paListEquals(
              replicationRequirements, other.replicationRequirements) &&
          paListEquals(replicas, other.replicas) &&
          paListEquals(availabilityRecords, other.availabilityRecords) &&
          paListEquals(retentionRecords, other.retentionRecords) &&
          paListEquals(deletionRequests, other.deletionRequests) &&
          paListEquals(deletionResults, other.deletionResults) &&
          paListEquals(tombstones, other.tombstones) &&
          paListEquals(sourceReferences, other.sourceReferences) &&
          paListEquals(policyReferences, other.policyReferences) &&
          paListEquals(operationRequests, other.operationRequests) &&
          paListEquals(operationResults, other.operationResults) &&
          identity == other.identity &&
          status == other.status &&
          createdAt == other.createdAt &&
          evaluatedAt == other.evaluatedAt &&
          publishedAt == other.publishedAt &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        Object.hash(
          projectId,
          releaseId,
          Object.hashAll(subjects),
          Object.hashAll(contentDescriptors),
          Object.hashAll(artifactIdentities),
          Object.hashAll(versions),
          Object.hashAll(manifests),
          Object.hashAll(locations),
          Object.hashAll(integrityRecords),
          Object.hashAll(encryptionDescriptors),
          Object.hashAll(publications),
          Object.hashAll(lifecycleRecords),
          Object.hashAll(retentionPolicies),
          Object.hashAll(storagePolicies),
          Object.hashAll(replicationRequirements),
          Object.hashAll(replicas),
          Object.hashAll(availabilityRecords),
          Object.hashAll(retentionRecords),
          Object.hashAll(deletionRequests),
          Object.hashAll(deletionResults),
        ),
        Object.hash(
          Object.hashAll(tombstones),
          Object.hashAll(sourceReferences),
          Object.hashAll(policyReferences),
          Object.hashAll(operationRequests),
          Object.hashAll(operationResults),
          identity,
          status,
          createdAt,
          evaluatedAt,
          publishedAt,
          Object.hashAll(metadata.entries),
        ),
      );
}
