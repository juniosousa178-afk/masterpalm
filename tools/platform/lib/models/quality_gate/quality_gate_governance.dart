import 'quality_gate_enums.dart';

/// Policy governance and change control metadata.
class QualityGateGovernance {
  const QualityGateGovernance({
    required this.policyOwner,
    required this.approvalAuthority,
    required this.versioningStrategy,
    required this.thresholdChangePolicy,
    required this.ruleChangePolicy,
    required this.deprecationPolicy,
    required this.rollbackPolicy,
    required this.evidenceRequirements,
    required this.compatibilityRequirements,
    required this.auditRequirements,
    this.changeControl = 'immutable-version-on-change',
  });

  final String policyOwner;
  final String approvalAuthority;
  final String changeControl;
  final String versioningStrategy;
  final String thresholdChangePolicy;
  final String ruleChangePolicy;
  final String deprecationPolicy;
  final String rollbackPolicy;
  final String evidenceRequirements;
  final String compatibilityRequirements;
  final String auditRequirements;

  Map<String, dynamic> toJson() => {
        'policyOwner': policyOwner,
        'approvalAuthority': approvalAuthority,
        'changeControl': changeControl,
        'versioningStrategy': versioningStrategy,
        'thresholdChangePolicy': thresholdChangePolicy,
        'ruleChangePolicy': ruleChangePolicy,
        'deprecationPolicy': deprecationPolicy,
        'rollbackPolicy': rollbackPolicy,
        'evidenceRequirements': evidenceRequirements,
        'compatibilityRequirements': compatibilityRequirements,
        'auditRequirements': auditRequirements,
      };

  factory QualityGateGovernance.fromJson(Map<String, dynamic> json) {
    return QualityGateGovernance(
      policyOwner: json['policyOwner'] as String,
      approvalAuthority: json['approvalAuthority'] as String,
      changeControl:
          json['changeControl'] as String? ?? 'immutable-version-on-change',
      versioningStrategy: json['versioningStrategy'] as String,
      thresholdChangePolicy: json['thresholdChangePolicy'] as String,
      ruleChangePolicy: json['ruleChangePolicy'] as String,
      deprecationPolicy: json['deprecationPolicy'] as String,
      rollbackPolicy: json['rollbackPolicy'] as String,
      evidenceRequirements: json['evidenceRequirements'] as String,
      compatibilityRequirements: json['compatibilityRequirements'] as String,
      auditRequirements: json['auditRequirements'] as String,
    );
  }
}

/// Immutable policy version identity.
class QualityGatePolicyVersion {
  const QualityGatePolicyVersion({
    required this.policyId,
    required this.policyVersion,
    required this.schemaVersion,
    required this.calculationVersion,
    required this.canonicalizationVersion,
  });

  final String policyId;
  final int policyVersion;
  final int schemaVersion;
  final int calculationVersion;
  final int canonicalizationVersion;

  String get versionKey => '$policyId:v$policyVersion';

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'schemaVersion': schemaVersion,
        'calculationVersion': calculationVersion,
        'canonicalizationVersion': canonicalizationVersion,
      };

  factory QualityGatePolicyVersion.fromJson(Map<String, dynamic> json) {
    return QualityGatePolicyVersion(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      schemaVersion: json['schemaVersion'] as int,
      calculationVersion: json['calculationVersion'] as int,
      canonicalizationVersion: json['canonicalizationVersion'] as int,
    );
  }
}

/// Changelog entry for a policy version.
class QualityGatePolicyChangelogEntry {
  const QualityGatePolicyChangelogEntry({
    required this.version,
    required this.summary,
    required this.author,
    required this.createdAt,
  });

  final int version;
  final String summary;
  final String author;
  final String createdAt;

  Map<String, dynamic> toJson() => {
        'version': version,
        'summary': summary,
        'author': author,
        'createdAt': createdAt,
      };

  factory QualityGatePolicyChangelogEntry.fromJson(Map<String, dynamic> json) {
    return QualityGatePolicyChangelogEntry(
      version: json['version'] as int,
      summary: json['summary'] as String,
      author: json['author'] as String,
      createdAt: json['createdAt'] as String,
    );
  }
}

/// Normative metadata for a quality gate policy.
class QualityGatePolicyMetadata {
  const QualityGatePolicyMetadata({
    required this.policyId,
    required this.policyName,
    required this.policyVersion,
    required this.schemaVersion,
    required this.calculationVersion,
    required this.canonicalizationVersion,
    required this.status,
    required this.owner,
    required this.createdAt,
    required this.rationale,
    required this.changelog,
    this.effectiveFrom,
    this.deprecatedAt,
    this.tags = const [],
    this.policyFingerprint = '',
  });

  static const int currentSchemaVersion = 1;
  static const int currentCalculationVersion = 1;
  static const int currentCanonicalizationVersion = 1;

  final String policyId;
  final String policyName;
  final int policyVersion;
  final int schemaVersion;
  final int calculationVersion;
  final int canonicalizationVersion;
  final QualityGatePolicyStatus status;
  final String owner;
  final String createdAt;
  final String? effectiveFrom;
  final String? deprecatedAt;
  final String rationale;
  final List<QualityGatePolicyChangelogEntry> changelog;
  final List<String> tags;
  final String policyFingerprint;

  QualityGatePolicyVersion get versionRef => QualityGatePolicyVersion(
        policyId: policyId,
        policyVersion: policyVersion,
        schemaVersion: schemaVersion,
        calculationVersion: calculationVersion,
        canonicalizationVersion: canonicalizationVersion,
      );

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyName': policyName,
        'policyVersion': policyVersion,
        'schemaVersion': schemaVersion,
        'calculationVersion': calculationVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'status': status.wireName,
        'owner': owner,
        'createdAt': createdAt,
        if (effectiveFrom != null) 'effectiveFrom': effectiveFrom,
        if (deprecatedAt != null) 'deprecatedAt': deprecatedAt,
        'rationale': rationale,
        'changelog': changelog.map((e) => e.toJson()).toList(),
        'tags': tags,
        'policyFingerprint': policyFingerprint,
      };

  factory QualityGatePolicyMetadata.fromJson(Map<String, dynamic> json) {
    return QualityGatePolicyMetadata(
      policyId: json['policyId'] as String,
      policyName: json['policyName'] as String,
      policyVersion: json['policyVersion'] as int,
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      calculationVersion:
          json['calculationVersion'] as int? ?? currentCalculationVersion,
      canonicalizationVersion: json['canonicalizationVersion'] as int? ??
          currentCanonicalizationVersion,
      status: QualityGatePolicyStatusX.fromWireName(json['status'] as String),
      owner: json['owner'] as String,
      createdAt: json['createdAt'] as String,
      effectiveFrom: json['effectiveFrom'] as String?,
      deprecatedAt: json['deprecatedAt'] as String?,
      rationale: json['rationale'] as String,
      changelog: (json['changelog'] as List<dynamic>? ?? [])
          .map(
            (e) => QualityGatePolicyChangelogEntry.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      policyFingerprint: json['policyFingerprint'] as String? ?? '',
    );
  }
}
