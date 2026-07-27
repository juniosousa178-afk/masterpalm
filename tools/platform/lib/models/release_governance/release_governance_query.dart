import 'release_governance_enums.dart';

/// Sort direction for release governance store queries.
enum ReleaseGovernanceQuerySortDirection {
  ascending,
  descending,
}

extension ReleaseGovernanceQuerySortDirectionX
    on ReleaseGovernanceQuerySortDirection {
  String get wireName => name;

  static ReleaseGovernanceQuerySortDirection fromWireName(String value) {
    return ReleaseGovernanceQuerySortDirection.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseGovernanceQuerySortDirection: $value',
      ),
    );
  }
}

/// Query filters for listing release decision snapshots.
class ReleaseGovernanceQuery {
  const ReleaseGovernanceQuery({
    this.projectId,
    this.releaseId,
    this.commitId,
    this.policyId,
    this.policyVersion,
    this.decision,
    this.environment,
    this.releaseType,
    this.evaluatedFrom,
    this.evaluatedTo,
    this.limit,
    this.offset,
    this.sortDirection = ReleaseGovernanceQuerySortDirection.descending,
  });

  final String? projectId;
  final String? releaseId;
  final String? commitId;
  final String? policyId;
  final int? policyVersion;
  final ReleaseGovernanceDecision? decision;
  final ReleaseEnvironment? environment;
  final ReleaseType? releaseType;
  final String? evaluatedFrom;
  final String? evaluatedTo;
  final int? limit;
  final int? offset;
  final ReleaseGovernanceQuerySortDirection sortDirection;

  Map<String, dynamic> toJson() => {
        if (projectId != null) 'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (policyId != null) 'policyId': policyId,
        if (policyVersion != null) 'policyVersion': policyVersion,
        if (decision != null) 'decision': decision!.wireName,
        if (environment != null) 'environment': environment!.wireName,
        if (releaseType != null) 'releaseType': releaseType!.wireName,
        if (evaluatedFrom != null) 'evaluatedFrom': evaluatedFrom,
        if (evaluatedTo != null) 'evaluatedTo': evaluatedTo,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        'sortDirection': sortDirection.wireName,
      };
}
