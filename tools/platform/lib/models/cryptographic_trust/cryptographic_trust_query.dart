import 'cryptographic_trust_enums.dart';

/// Sort direction for cryptographic trust store queries.
enum CryptographicTrustQuerySortDirection {
  ascending,
  descending,
}

extension CryptographicTrustQuerySortDirectionX
    on CryptographicTrustQuerySortDirection {
  String get wireName => name;

  static CryptographicTrustQuerySortDirection fromWireName(String value) {
    return CryptographicTrustQuerySortDirection.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException(
        'Unknown CryptographicTrustQuerySortDirection: $value',
      ),
    );
  }
}

/// Query filters for listing cryptographic trust snapshots.
class CryptographicTrustQuery {
  const CryptographicTrustQuery({
    this.projectId,
    this.releaseId,
    this.subjectId,
    this.signatureId,
    this.policyId,
    this.trustStatus,
    this.verificationStatus,
    this.createdFrom,
    this.createdUntil,
    this.limit,
    this.offset,
    this.sortDirection = CryptographicTrustQuerySortDirection.descending,
  });

  final String? projectId;
  final String? releaseId;
  final String? subjectId;
  final String? signatureId;
  final String? policyId;
  final CryptographicTrustStatus? trustStatus;
  final CryptographicVerificationStatus? verificationStatus;
  final String? createdFrom;
  final String? createdUntil;
  final int? limit;
  final int? offset;
  final CryptographicTrustQuerySortDirection sortDirection;

  Map<String, dynamic> toJson() => {
        if (projectId != null) 'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (subjectId != null) 'subjectId': subjectId,
        if (signatureId != null) 'signatureId': signatureId,
        if (policyId != null) 'policyId': policyId,
        if (trustStatus != null) 'trustStatus': trustStatus!.wireName,
        if (verificationStatus != null)
          'verificationStatus': verificationStatus!.wireName,
        if (createdFrom != null) 'createdFrom': createdFrom,
        if (createdUntil != null) 'createdUntil': createdUntil,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        'sortDirection': sortDirection.wireName,
      };

  factory CryptographicTrustQuery.fromJson(Map<String, dynamic> json) {
    return CryptographicTrustQuery(
      projectId: json['projectId'] as String?,
      releaseId: json['releaseId'] as String?,
      subjectId: json['subjectId'] as String?,
      signatureId: json['signatureId'] as String?,
      policyId: json['policyId'] as String?,
      trustStatus: json['trustStatus'] == null
          ? null
          : CryptographicTrustStatusX.fromWireName(
              json['trustStatus'] as String,
            ),
      verificationStatus: json['verificationStatus'] == null
          ? null
          : CryptographicVerificationStatusX.fromWireName(
              json['verificationStatus'] as String,
            ),
      createdFrom: json['createdFrom'] as String?,
      createdUntil: json['createdUntil'] as String?,
      limit: json['limit'] as int?,
      offset: json['offset'] as int?,
      sortDirection: CryptographicTrustQuerySortDirectionX.fromWireName(
        json['sortDirection'] as String? ??
            CryptographicTrustQuerySortDirection.descending.wireName,
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        if (projectId != null) 'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (subjectId != null) 'subjectId': subjectId,
        if (signatureId != null) 'signatureId': signatureId,
        if (policyId != null) 'policyId': policyId,
        if (trustStatus != null) 'trustStatus': trustStatus!.wireName,
        if (verificationStatus != null)
          'verificationStatus': verificationStatus!.wireName,
        if (createdFrom != null) 'createdFrom': createdFrom,
        if (createdUntil != null) 'createdUntil': createdUntil,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        'sortDirection': sortDirection.wireName,
      };

  CryptographicTrustQuery copyWith({
    String? projectId,
    String? releaseId,
    String? subjectId,
    String? signatureId,
    String? policyId,
    CryptographicTrustStatus? trustStatus,
    CryptographicVerificationStatus? verificationStatus,
    String? createdFrom,
    String? createdUntil,
    int? limit,
    int? offset,
    CryptographicTrustQuerySortDirection? sortDirection,
  }) {
    return CryptographicTrustQuery(
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      subjectId: subjectId ?? this.subjectId,
      signatureId: signatureId ?? this.signatureId,
      policyId: policyId ?? this.policyId,
      trustStatus: trustStatus ?? this.trustStatus,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      createdFrom: createdFrom ?? this.createdFrom,
      createdUntil: createdUntil ?? this.createdUntil,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      sortDirection: sortDirection ?? this.sortDirection,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTrustQuery &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          subjectId == other.subjectId &&
          signatureId == other.signatureId &&
          policyId == other.policyId &&
          trustStatus == other.trustStatus &&
          verificationStatus == other.verificationStatus &&
          createdFrom == other.createdFrom &&
          createdUntil == other.createdUntil &&
          limit == other.limit &&
          offset == other.offset &&
          sortDirection == other.sortDirection;

  @override
  int get hashCode => Object.hash(
        projectId,
        releaseId,
        subjectId,
        signatureId,
        policyId,
        trustStatus,
        verificationStatus,
        createdFrom,
        createdUntil,
        limit,
        offset,
        sortDirection,
      );
}
