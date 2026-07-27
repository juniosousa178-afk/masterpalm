import '../release_governance/release_governance_enums.dart';

/// Sort direction for release supply chain store queries.
enum ReleaseSupplyChainQuerySortDirection {
  ascending,
  descending,
}

extension ReleaseSupplyChainQuerySortDirectionX
    on ReleaseSupplyChainQuerySortDirection {
  String get wireName => name;

  static ReleaseSupplyChainQuerySortDirection fromWireName(String value) {
    return ReleaseSupplyChainQuerySortDirection.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown ReleaseSupplyChainQuerySortDirection: $value',
      ),
    );
  }
}

/// Query filters for listing release supply chain snapshots.
class ReleaseSupplyChainQuery {
  const ReleaseSupplyChainQuery({
    this.projectId,
    this.releaseId,
    this.commitId,
    this.supplyChainPolicyId,
    this.supplyChainPolicyVersion,
    this.distributionPolicyId,
    this.compliancePolicyId,
    this.environment,
    this.evaluatedFrom,
    this.evaluatedTo,
    this.limit,
    this.offset,
    this.sortDirection = ReleaseSupplyChainQuerySortDirection.descending,
  });

  final String? projectId;
  final String? releaseId;
  final String? commitId;
  final String? supplyChainPolicyId;
  final int? supplyChainPolicyVersion;
  final String? distributionPolicyId;
  final String? compliancePolicyId;
  final ReleaseEnvironment? environment;
  final String? evaluatedFrom;
  final String? evaluatedTo;
  final int? limit;
  final int? offset;
  final ReleaseSupplyChainQuerySortDirection sortDirection;

  Map<String, dynamic> toJson() => {
        if (projectId != null) 'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (supplyChainPolicyId != null)
          'supplyChainPolicyId': supplyChainPolicyId,
        if (supplyChainPolicyVersion != null)
          'supplyChainPolicyVersion': supplyChainPolicyVersion,
        if (distributionPolicyId != null)
          'distributionPolicyId': distributionPolicyId,
        if (compliancePolicyId != null)
          'compliancePolicyId': compliancePolicyId,
        if (environment != null) 'environment': environment!.wireName,
        if (evaluatedFrom != null) 'evaluatedFrom': evaluatedFrom,
        if (evaluatedTo != null) 'evaluatedTo': evaluatedTo,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        'sortDirection': sortDirection.wireName,
      };
}
