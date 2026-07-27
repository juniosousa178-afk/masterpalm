import 'cicd_integration_operational_enums.dart';

/// Sort direction for CI/CD integration store queries.
enum CicdIntegrationQuerySortDirection {
  ascending,
  descending,
}

extension CicdIntegrationQuerySortDirectionX
    on CicdIntegrationQuerySortDirection {
  String get wireName => name;

  static CicdIntegrationQuerySortDirection fromWireName(String value) {
    return CicdIntegrationQuerySortDirection.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CicdIntegrationQuerySortDirection: $value',
      ),
    );
  }
}

/// Query filters for listing CI/CD integration snapshots.
class CicdIntegrationQuery {
  const CicdIntegrationQuery({
    this.projectId,
    this.releaseId,
    this.pipelineDefinitionId,
    this.status,
    this.policyId,
    this.limit,
    this.offset,
    this.sortDirection = CicdIntegrationQuerySortDirection.descending,
  });

  final String? projectId;
  final String? releaseId;
  final String? pipelineDefinitionId;
  final CicdIntegrationSnapshotStatus? status;
  final String? policyId;
  final int? limit;
  final int? offset;
  final CicdIntegrationQuerySortDirection sortDirection;

  Map<String, dynamic> toJson() => {
        if (projectId != null) 'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (pipelineDefinitionId != null)
          'pipelineDefinitionId': pipelineDefinitionId,
        if (status != null) 'status': status!.wireName,
        if (policyId != null) 'policyId': policyId,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        'sortDirection': sortDirection.wireName,
      };

  factory CicdIntegrationQuery.fromJson(Map<String, dynamic> json) {
    return CicdIntegrationQuery(
      projectId: json['projectId'] as String?,
      releaseId: json['releaseId'] as String?,
      pipelineDefinitionId: json['pipelineDefinitionId'] as String?,
      status: json['status'] == null
          ? null
          : CicdIntegrationSnapshotStatusX.fromWireName(
              json['status'] as String,
            ),
      policyId: json['policyId'] as String?,
      limit: json['limit'] as int?,
      offset: json['offset'] as int?,
      sortDirection: CicdIntegrationQuerySortDirectionX.fromWireName(
        json['sortDirection'] as String? ??
            CicdIntegrationQuerySortDirection.descending.wireName,
      ),
    );
  }

  CicdIntegrationQuery copyWith({
    String? projectId,
    String? releaseId,
    String? pipelineDefinitionId,
    CicdIntegrationSnapshotStatus? status,
    String? policyId,
    int? limit,
    int? offset,
    CicdIntegrationQuerySortDirection? sortDirection,
  }) {
    return CicdIntegrationQuery(
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      pipelineDefinitionId: pipelineDefinitionId ?? this.pipelineDefinitionId,
      status: status ?? this.status,
      policyId: policyId ?? this.policyId,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      sortDirection: sortDirection ?? this.sortDirection,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CicdIntegrationQuery &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          pipelineDefinitionId == other.pipelineDefinitionId &&
          status == other.status &&
          policyId == other.policyId &&
          limit == other.limit &&
          offset == other.offset &&
          sortDirection == other.sortDirection;

  @override
  int get hashCode => Object.hash(
        projectId,
        releaseId,
        pipelineDefinitionId,
        status,
        policyId,
        limit,
        offset,
        sortDirection,
      );
}
