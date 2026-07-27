import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';
import 'persistent_artifact_validation_result.dart';

/// Declarative availability record for a persistent artifact.
///
/// Does not perform health checks. Status is declarative only.
/// Unavailable is not invalid; partial is not failed.
class PersistentArtifactAvailabilityRecord {
  const PersistentArtifactAvailabilityRecord({
    required this.availabilityRecordId,
    required this.artifactId,
    required this.versionId,
    required this.status,
    this.locationId,
    this.checkedAt,
    this.reasonCode,
    this.issues = const [],
    this.metadata = const {},
  });

  final String availabilityRecordId;
  final String artifactId;
  final String versionId;
  final String? locationId;
  final PersistentArtifactAvailabilityStatus status;
  final String? checkedAt;
  final String? reasonCode;
  final List<PersistentArtifactIssue> issues;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'availabilityRecordId': availabilityRecordId,
        'artifactId': artifactId,
        'versionId': versionId,
        if (locationId != null) 'locationId': locationId,
        'status': status.wireName,
        if (checkedAt != null) 'checkedAt': checkedAt,
        if (reasonCode != null) 'reasonCode': reasonCode,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactAvailabilityRecord.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactAvailabilityRecord(
      availabilityRecordId: json['availabilityRecordId'] as String,
      artifactId: json['artifactId'] as String,
      versionId: json['versionId'] as String,
      locationId: json['locationId'] as String?,
      status: PersistentArtifactAvailabilityStatusX.fromWireName(
        json['status'] as String,
      ),
      checkedAt: json['checkedAt'] as String?,
      reasonCode: json['reasonCode'] as String?,
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactIssue.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'availabilityRecordId': availabilityRecordId,
        'artifactId': artifactId,
        'versionId': versionId,
        if (locationId != null) 'locationId': locationId,
        'status': status.wireName,
        if (reasonCode != null) 'reasonCode': reasonCode,
        if (issues.isNotEmpty)
          'issues': (issues.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => (a['code'] as String).compareTo(b['code'] as String),
            )),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactAvailabilityRecord copyWith({
    String? availabilityRecordId,
    String? artifactId,
    String? versionId,
    String? locationId,
    PersistentArtifactAvailabilityStatus? status,
    String? checkedAt,
    String? reasonCode,
    List<PersistentArtifactIssue>? issues,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactAvailabilityRecord(
      availabilityRecordId: availabilityRecordId ?? this.availabilityRecordId,
      artifactId: artifactId ?? this.artifactId,
      versionId: versionId ?? this.versionId,
      locationId: locationId ?? this.locationId,
      status: status ?? this.status,
      checkedAt: checkedAt ?? this.checkedAt,
      reasonCode: reasonCode ?? this.reasonCode,
      issues: issues ?? this.issues,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactAvailabilityRecord &&
          availabilityRecordId == other.availabilityRecordId &&
          artifactId == other.artifactId &&
          versionId == other.versionId &&
          locationId == other.locationId &&
          status == other.status &&
          checkedAt == other.checkedAt &&
          reasonCode == other.reasonCode &&
          paListEquals(issues, other.issues) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        availabilityRecordId,
        artifactId,
        versionId,
        locationId,
        status,
        checkedAt,
        reasonCode,
        Object.hashAll(issues),
        Object.hashAll(metadata.entries),
      );
}
