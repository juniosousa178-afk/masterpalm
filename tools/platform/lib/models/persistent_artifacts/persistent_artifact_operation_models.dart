import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';
import 'persistent_artifact_reference_models.dart';
import 'persistent_artifact_subject.dart';
import 'persistent_artifact_validation_result.dart';

/// Declarative location result within an artifact operation.
class PersistentArtifactLocationResult {
  const PersistentArtifactLocationResult({
    required this.locationId,
    required this.status,
    this.issues = const [],
    this.metadata = const {},
  });

  final String locationId;
  final PersistentArtifactOperationStatus status;
  final List<PersistentArtifactIssue> issues;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'locationId': locationId,
        'status': status.wireName,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactLocationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactLocationResult(
      locationId: json['locationId'] as String,
      status: PersistentArtifactOperationStatusX.fromWireName(
        json['status'] as String,
      ),
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
        'locationId': locationId,
        'status': status.wireName,
        if (issues.isNotEmpty)
          'issues': (issues.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => (a['code'] as String).compareTo(b['code'] as String),
            )),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactLocationResult copyWith({
    String? locationId,
    PersistentArtifactOperationStatus? status,
    List<PersistentArtifactIssue>? issues,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactLocationResult(
      locationId: locationId ?? this.locationId,
      status: status ?? this.status,
      issues: issues ?? this.issues,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactLocationResult &&
          locationId == other.locationId &&
          status == other.status &&
          paListEquals(issues, other.issues) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        locationId,
        status,
        Object.hashAll(issues),
        Object.hashAll(metadata.entries),
      );
}

/// Declarative policy result within an artifact operation.
class PersistentArtifactPolicyResult {
  const PersistentArtifactPolicyResult({
    required this.policyId,
    required this.policyVersion,
    required this.policyType,
    required this.status,
    this.issues = const [],
    this.metadata = const {},
  });

  final String policyId;
  final int policyVersion;
  final PersistentArtifactPolicyType policyType;
  final PersistentArtifactOperationStatus status;
  final List<PersistentArtifactIssue> issues;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'policyType': policyType.wireName,
        'status': status.wireName,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactPolicyResult.fromJson(Map<String, dynamic> json) {
    return PersistentArtifactPolicyResult(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      policyType: PersistentArtifactPolicyTypeX.fromWireName(
        json['policyType'] as String,
      ),
      status: PersistentArtifactOperationStatusX.fromWireName(
        json['status'] as String,
      ),
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
        'policyId': policyId,
        'policyVersion': policyVersion,
        'policyType': policyType.wireName,
        'status': status.wireName,
        if (issues.isNotEmpty)
          'issues': (issues.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => (a['code'] as String).compareTo(b['code'] as String),
            )),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactPolicyResult copyWith({
    String? policyId,
    int? policyVersion,
    PersistentArtifactPolicyType? policyType,
    PersistentArtifactOperationStatus? status,
    List<PersistentArtifactIssue>? issues,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactPolicyResult(
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      policyType: policyType ?? this.policyType,
      status: status ?? this.status,
      issues: issues ?? this.issues,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactPolicyResult &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          policyType == other.policyType &&
          status == other.status &&
          paListEquals(issues, other.issues) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        policyId,
        policyVersion,
        policyType,
        status,
        Object.hashAll(issues),
        Object.hashAll(metadata.entries),
      );
}

/// Declarative per-artifact result within an operation.
class PersistentArtifactItemResult {
  const PersistentArtifactItemResult({
    required this.artifactId,
    required this.status,
    this.versionId,
    this.locationResults = const [],
    this.policyResults = const [],
    this.issues = const [],
    this.metadata = const {},
  });

  final String artifactId;
  final String? versionId;
  final PersistentArtifactOperationStatus status;
  final List<PersistentArtifactLocationResult> locationResults;
  final List<PersistentArtifactPolicyResult> policyResults;
  final List<PersistentArtifactIssue> issues;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'artifactId': artifactId,
        if (versionId != null) 'versionId': versionId,
        'status': status.wireName,
        if (locationResults.isNotEmpty)
          'locationResults': locationResults.map((e) => e.toJson()).toList(),
        if (policyResults.isNotEmpty)
          'policyResults': policyResults.map((e) => e.toJson()).toList(),
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactItemResult.fromJson(Map<String, dynamic> json) {
    return PersistentArtifactItemResult(
      artifactId: json['artifactId'] as String,
      versionId: json['versionId'] as String?,
      status: PersistentArtifactOperationStatusX.fromWireName(
        json['status'] as String,
      ),
      locationResults: List.unmodifiable(
        (json['locationResults'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactLocationResult.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      policyResults: List.unmodifiable(
        (json['policyResults'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactPolicyResult.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
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
        'artifactId': artifactId,
        if (versionId != null) 'versionId': versionId,
        'status': status.wireName,
        if (locationResults.isNotEmpty)
          'locationResults': paSortedComparableList(
            locationResults.map((e) => e.toComparableJson()),
            'locationId',
          ),
        if (policyResults.isNotEmpty)
          'policyResults': paSortedComparableList(
            policyResults.map((e) => e.toComparableJson()),
            'policyId',
          ),
        if (issues.isNotEmpty)
          'issues': (issues.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => (a['code'] as String).compareTo(b['code'] as String),
            )),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactItemResult copyWith({
    String? artifactId,
    String? versionId,
    PersistentArtifactOperationStatus? status,
    List<PersistentArtifactLocationResult>? locationResults,
    List<PersistentArtifactPolicyResult>? policyResults,
    List<PersistentArtifactIssue>? issues,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactItemResult(
      artifactId: artifactId ?? this.artifactId,
      versionId: versionId ?? this.versionId,
      status: status ?? this.status,
      locationResults: locationResults ?? this.locationResults,
      policyResults: policyResults ?? this.policyResults,
      issues: issues ?? this.issues,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactItemResult &&
          artifactId == other.artifactId &&
          versionId == other.versionId &&
          status == other.status &&
          paListEquals(locationResults, other.locationResults) &&
          paListEquals(policyResults, other.policyResults) &&
          paListEquals(issues, other.issues) &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        artifactId,
        versionId,
        status,
        Object.hashAll(locationResults),
        Object.hashAll(policyResults),
        Object.hashAll(issues),
        Object.hashAll(metadata.entries),
      );
}

/// Declarative operation request for persistent artifacts.
///
/// Future intent only — does not execute operations or access storage.
class PersistentArtifactOperationRequest {
  const PersistentArtifactOperationRequest({
    required this.requestId,
    required this.operationType,
    required this.projectId,
    required this.requestedAt,
    this.releaseId,
    this.artifactSubjects = const [],
    this.artifactIds = const [],
    this.versionIds = const [],
    this.policyReferences = const [],
    this.metadata = const {},
  });

  final String requestId;
  final PersistentArtifactOperationType operationType;
  final String projectId;
  final String? releaseId;
  final List<PersistentArtifactSubject> artifactSubjects;
  final List<String> artifactIds;
  final List<String> versionIds;
  final List<PersistentArtifactPolicyReference> policyReferences;
  final String requestedAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'operationType': operationType.wireName,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (artifactSubjects.isNotEmpty)
          'artifactSubjects': artifactSubjects.map((e) => e.toJson()).toList(),
        if (artifactIds.isNotEmpty) 'artifactIds': artifactIds,
        if (versionIds.isNotEmpty) 'versionIds': versionIds,
        if (policyReferences.isNotEmpty)
          'policyReferences': policyReferences.map((e) => e.toJson()).toList(),
        'requestedAt': requestedAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactOperationRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactOperationRequest(
      requestId: json['requestId'] as String,
      operationType: PersistentArtifactOperationTypeX.fromWireName(
        json['operationType'] as String,
      ),
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      artifactSubjects: List.unmodifiable(
        (json['artifactSubjects'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactSubject.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      artifactIds: List.unmodifiable(
        (json['artifactIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      versionIds: List.unmodifiable(
        (json['versionIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
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
      requestedAt: json['requestedAt'] as String,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'requestId': requestId,
        'operationType': operationType.wireName,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (artifactSubjects.isNotEmpty)
          'artifactSubjects': paSortedComparableList(
            artifactSubjects.map((e) => e.toComparableJson()),
            'subjectId',
          ),
        if (artifactIds.isNotEmpty)
          'artifactIds': List<String>.from(artifactIds)..sort(),
        if (versionIds.isNotEmpty)
          'versionIds': List<String>.from(versionIds)..sort(),
        if (policyReferences.isNotEmpty)
          'policyReferences': paSortedComparableList(
            policyReferences.map((e) => e.toComparableJson()),
            'policyId',
          ),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactOperationRequest copyWith({
    String? requestId,
    PersistentArtifactOperationType? operationType,
    String? projectId,
    String? releaseId,
    List<PersistentArtifactSubject>? artifactSubjects,
    List<String>? artifactIds,
    List<String>? versionIds,
    List<PersistentArtifactPolicyReference>? policyReferences,
    String? requestedAt,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactOperationRequest(
      requestId: requestId ?? this.requestId,
      operationType: operationType ?? this.operationType,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      artifactSubjects: artifactSubjects ?? this.artifactSubjects,
      artifactIds: artifactIds ?? this.artifactIds,
      versionIds: versionIds ?? this.versionIds,
      policyReferences: policyReferences ?? this.policyReferences,
      requestedAt: requestedAt ?? this.requestedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactOperationRequest &&
          requestId == other.requestId &&
          operationType == other.operationType &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          paListEquals(artifactSubjects, other.artifactSubjects) &&
          paListEquals(artifactIds, other.artifactIds) &&
          paListEquals(versionIds, other.versionIds) &&
          paListEquals(policyReferences, other.policyReferences) &&
          requestedAt == other.requestedAt &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        requestId,
        operationType,
        projectId,
        releaseId,
        Object.hashAll(artifactSubjects),
        Object.hashAll(artifactIds),
        Object.hashAll(versionIds),
        Object.hashAll(policyReferences),
        requestedAt,
        Object.hashAll(metadata.entries),
      );
}

/// Declarative operation result for persistent artifacts.
///
/// Declared outcome only — success does not authorize release or deployment.
class PersistentArtifactOperationResult {
  const PersistentArtifactOperationResult({
    required this.resultId,
    required this.requestId,
    required this.operationType,
    required this.projectId,
    required this.status,
    this.releaseId,
    this.artifactResults = const [],
    this.issues = const [],
    this.completedAt,
    this.metadata = const {},
  });

  final String resultId;
  final String requestId;
  final PersistentArtifactOperationType operationType;
  final String projectId;
  final String? releaseId;
  final PersistentArtifactOperationStatus status;
  final List<PersistentArtifactItemResult> artifactResults;
  final List<PersistentArtifactIssue> issues;
  final String? completedAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'resultId': resultId,
        'requestId': requestId,
        'operationType': operationType.wireName,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'status': status.wireName,
        if (artifactResults.isNotEmpty)
          'artifactResults': artifactResults.map((e) => e.toJson()).toList(),
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (completedAt != null) 'completedAt': completedAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactOperationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactOperationResult(
      resultId: json['resultId'] as String,
      requestId: json['requestId'] as String,
      operationType: PersistentArtifactOperationTypeX.fromWireName(
        json['operationType'] as String,
      ),
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      status: PersistentArtifactOperationStatusX.fromWireName(
        json['status'] as String,
      ),
      artifactResults: List.unmodifiable(
        (json['artifactResults'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactItemResult.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map(
              (e) => PersistentArtifactIssue.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      completedAt: json['completedAt'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'resultId': resultId,
        'requestId': requestId,
        'operationType': operationType.wireName,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'status': status.wireName,
        if (artifactResults.isNotEmpty)
          'artifactResults': paSortedComparableList(
            artifactResults.map((e) => e.toComparableJson()),
            'artifactId',
          ),
        if (issues.isNotEmpty)
          'issues': (issues.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => (a['code'] as String).compareTo(b['code'] as String),
            )),
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactOperationResult copyWith({
    String? resultId,
    String? requestId,
    PersistentArtifactOperationType? operationType,
    String? projectId,
    String? releaseId,
    PersistentArtifactOperationStatus? status,
    List<PersistentArtifactItemResult>? artifactResults,
    List<PersistentArtifactIssue>? issues,
    String? completedAt,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactOperationResult(
      resultId: resultId ?? this.resultId,
      requestId: requestId ?? this.requestId,
      operationType: operationType ?? this.operationType,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      status: status ?? this.status,
      artifactResults: artifactResults ?? this.artifactResults,
      issues: issues ?? this.issues,
      completedAt: completedAt ?? this.completedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactOperationResult &&
          resultId == other.resultId &&
          requestId == other.requestId &&
          operationType == other.operationType &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          status == other.status &&
          paListEquals(artifactResults, other.artifactResults) &&
          paListEquals(issues, other.issues) &&
          completedAt == other.completedAt &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        resultId,
        requestId,
        operationType,
        projectId,
        releaseId,
        status,
        Object.hashAll(artifactResults),
        Object.hashAll(issues),
        completedAt,
        Object.hashAll(metadata.entries),
      );
}
