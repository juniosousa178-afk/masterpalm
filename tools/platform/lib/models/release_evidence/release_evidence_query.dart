import '../release_governance/release_governance_enums.dart';

/// Sort direction for release evidence store queries.
enum ReleaseEvidenceQuerySortDirection {
  ascending,
  descending,
}

extension ReleaseEvidenceQuerySortDirectionX
    on ReleaseEvidenceQuerySortDirection {
  String get wireName => name;

  static ReleaseEvidenceQuerySortDirection fromWireName(String value) {
    return ReleaseEvidenceQuerySortDirection.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseEvidenceQuerySortDirection: $value',
      ),
    );
  }
}

/// Query filters for listing release evidence bundles.
class ReleaseEvidenceQuery {
  const ReleaseEvidenceQuery({
    this.projectId,
    this.releaseId,
    this.commitId,
    this.policyId,
    this.policyVersion,
    this.environment,
    this.evaluatedFrom,
    this.evaluatedTo,
    this.limit,
    this.offset,
    this.sortDirection = ReleaseEvidenceQuerySortDirection.descending,
  });

  final String? projectId;
  final String? releaseId;
  final String? commitId;
  final String? policyId;
  final int? policyVersion;
  final ReleaseEnvironment? environment;
  final String? evaluatedFrom;
  final String? evaluatedTo;
  final int? limit;
  final int? offset;
  final ReleaseEvidenceQuerySortDirection sortDirection;

  Map<String, dynamic> toJson() => {
        if (projectId != null) 'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (policyId != null) 'policyId': policyId,
        if (policyVersion != null) 'policyVersion': policyVersion,
        if (environment != null) 'environment': environment!.wireName,
        if (evaluatedFrom != null) 'evaluatedFrom': evaluatedFrom,
        if (evaluatedTo != null) 'evaluatedTo': evaluatedTo,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        'sortDirection': sortDirection.wireName,
      };
}
