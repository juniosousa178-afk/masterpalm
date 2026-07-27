import 'persistent_artifact_content_descriptor.dart';
import 'persistent_artifact_integrity_record.dart';
import 'persistent_artifact_location_reference.dart';
import 'persistent_artifact_reference_models.dart';
import 'persistent_artifact_subject.dart';
import 'persistent_artifact_equality.dart';

/// Declarative manifest for a persistent artifact.
///
/// Represents structure only — does not write or persist data.
/// Location references are declarative and do not perform I/O.
class PersistentArtifactManifest {
  const PersistentArtifactManifest({
    required this.manifestId,
    required this.artifactId,
    required this.versionId,
    required this.subject,
    required this.contentDescriptor,
    required this.createdAt,
    this.locations = const [],
    this.integrityRecords = const [],
    this.sourceReferences = const [],
    this.policyReferences = const [],
    this.metadata = const {},
  });

  final String manifestId;
  final String artifactId;
  final String versionId;
  final PersistentArtifactSubject subject;
  final PersistentArtifactContentDescriptor contentDescriptor;
  final List<PersistentArtifactLocationReference> locations;
  final List<PersistentArtifactIntegrityRecord> integrityRecords;
  final List<PersistentArtifactSourceReference> sourceReferences;
  final List<PersistentArtifactPolicyReference> policyReferences;
  final String createdAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'manifestId': manifestId,
        'artifactId': artifactId,
        'versionId': versionId,
        'subject': subject.toJson(),
        'contentDescriptor': contentDescriptor.toJson(),
        if (locations.isNotEmpty)
          'locations': locations.map((e) => e.toJson()).toList(),
        if (integrityRecords.isNotEmpty)
          'integrityRecords': integrityRecords.map((e) => e.toJson()).toList(),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        if (policyReferences.isNotEmpty)
          'policyReferences': policyReferences.map((e) => e.toJson()).toList(),
        'createdAt': createdAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactManifest.fromJson(Map<String, dynamic> json) {
    return PersistentArtifactManifest(
      manifestId: json['manifestId'] as String,
      artifactId: json['artifactId'] as String,
      versionId: json['versionId'] as String,
      subject: PersistentArtifactSubject.fromJson(
        json['subject'] as Map<String, dynamic>,
      ),
      contentDescriptor: PersistentArtifactContentDescriptor.fromJson(
        json['contentDescriptor'] as Map<String, dynamic>,
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
      createdAt: json['createdAt'] as String,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'manifestId': manifestId,
        'artifactId': artifactId,
        'versionId': versionId,
        'subject': subject.toComparableJson(),
        'contentDescriptor': contentDescriptor.toComparableJson(),
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
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactManifest copyWith({
    String? manifestId,
    String? artifactId,
    String? versionId,
    PersistentArtifactSubject? subject,
    PersistentArtifactContentDescriptor? contentDescriptor,
    List<PersistentArtifactLocationReference>? locations,
    List<PersistentArtifactIntegrityRecord>? integrityRecords,
    List<PersistentArtifactSourceReference>? sourceReferences,
    List<PersistentArtifactPolicyReference>? policyReferences,
    String? createdAt,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactManifest(
      manifestId: manifestId ?? this.manifestId,
      artifactId: artifactId ?? this.artifactId,
      versionId: versionId ?? this.versionId,
      subject: subject ?? this.subject,
      contentDescriptor: contentDescriptor ?? this.contentDescriptor,
      locations: locations ?? this.locations,
      integrityRecords: integrityRecords ?? this.integrityRecords,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      policyReferences: policyReferences ?? this.policyReferences,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactManifest &&
          manifestId == other.manifestId &&
          artifactId == other.artifactId &&
          versionId == other.versionId &&
          subject == other.subject &&
          contentDescriptor == other.contentDescriptor &&
          paListEquals(locations, other.locations) &&
          paListEquals(integrityRecords, other.integrityRecords) &&
          paListEquals(sourceReferences, other.sourceReferences) &&
          paListEquals(policyReferences, other.policyReferences) &&
          createdAt == other.createdAt &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        manifestId,
        artifactId,
        versionId,
        subject,
        contentDescriptor,
        Object.hashAll(locations),
        Object.hashAll(integrityRecords),
        Object.hashAll(sourceReferences),
        Object.hashAll(policyReferences),
        createdAt,
        Object.hashAll(metadata.entries),
      );
}
