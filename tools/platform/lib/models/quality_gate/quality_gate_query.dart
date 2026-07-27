import 'quality_gate_enums.dart';

/// Sort direction for quality gate store queries.
enum QualityGateQuerySortDirection {
  ascending,
  descending,
}

extension QualityGateQuerySortDirectionX on QualityGateQuerySortDirection {
  String get wireName => name;

  static QualityGateQuerySortDirection fromWireName(String value) {
    return QualityGateQuerySortDirection.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown QualityGateQuerySortDirection: $value',
      ),
    );
  }
}

/// Query filters for listing quality gate snapshots.
class QualityGateQuery {
  const QualityGateQuery({
    this.projectId,
    this.commitId,
    this.branch,
    this.policyId,
    this.policyVersion,
    this.decision,
    this.eligibility,
    this.compatibility,
    this.createdFrom,
    this.createdTo,
    this.limit,
    this.offset,
    this.sortDirection = QualityGateQuerySortDirection.descending,
  });

  final String? projectId;
  final String? commitId;
  final String? branch;
  final String? policyId;
  final int? policyVersion;
  final QualityGateDecision? decision;
  final QualityGateEligibilityStatus? eligibility;
  final QualityGateCompatibilityStatus? compatibility;
  final String? createdFrom;
  final String? createdTo;
  final int? limit;
  final int? offset;
  final QualityGateQuerySortDirection sortDirection;

  Map<String, dynamic> toJson() => {
        if (projectId != null) 'projectId': projectId,
        if (commitId != null) 'commitId': commitId,
        if (branch != null) 'branch': branch,
        if (policyId != null) 'policyId': policyId,
        if (policyVersion != null) 'policyVersion': policyVersion,
        if (decision != null) 'decision': decision!.wireName,
        if (eligibility != null) 'eligibility': eligibility!.wireName,
        if (compatibility != null) 'compatibility': compatibility!.wireName,
        if (createdFrom != null) 'createdFrom': createdFrom,
        if (createdTo != null) 'createdTo': createdTo,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        'sortDirection': sortDirection.wireName,
      };
}
