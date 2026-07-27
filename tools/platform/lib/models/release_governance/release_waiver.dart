import 'release_governance_enums.dart';
import 'release_governance_evidence.dart';

/// Compensating control linked to a waiver.
class ReleaseCompensatingControl {
  const ReleaseCompensatingControl({
    required this.controlId,
    required this.name,
    required this.description,
    required this.owner,
    required this.status,
    required this.evidenceReferences,
    required this.validFrom,
    this.expiresAt,
    this.relatedRuleIds = const [],
    this.limitations = const [],
  });

  final String controlId;
  final String name;
  final String description;
  final String owner;
  final ReleaseCompensatingControlStatus status;
  final List<String> evidenceReferences;
  final String validFrom;
  final String? expiresAt;
  final List<String> relatedRuleIds;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'controlId': controlId,
        'name': name,
        'description': description,
        'owner': owner,
        'status': status.wireName,
        'evidenceReferences': evidenceReferences,
        'validFrom': validFrom,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (relatedRuleIds.isNotEmpty) 'relatedRuleIds': relatedRuleIds,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseCompensatingControl.fromJson(Map<String, dynamic> json) {
    return ReleaseCompensatingControl(
      controlId: json['controlId'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      owner: json['owner'] as String,
      status: ReleaseCompensatingControlStatusX.fromWireName(
        json['status'] as String,
      ),
      evidenceReferences: (json['evidenceReferences'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      validFrom: json['validFrom'] as String,
      expiresAt: json['expiresAt'] as String?,
      relatedRuleIds: (json['relatedRuleIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Waiver authority definition.
class ReleaseWaiverAuthority {
  const ReleaseWaiverAuthority({
    required this.authorityId,
    required this.role,
    required this.allowedSeverities,
    required this.allowedRuleIds,
    required this.allowedEnvironments,
    required this.allowedReleaseTypes,
    required this.maximumWaiverDuration,
    required this.emergencyOnly,
    required this.separationOfDutiesGroup,
    required this.status,
    required this.validFrom,
    this.expiresAt,
  });

  final String authorityId;
  final String role;
  final List<ReleaseGovernanceRuleSeverity> allowedSeverities;
  final List<String> allowedRuleIds;
  final List<ReleaseEnvironment> allowedEnvironments;
  final List<ReleaseType> allowedReleaseTypes;
  final String maximumWaiverDuration;
  final bool emergencyOnly;
  final String separationOfDutiesGroup;
  final ReleaseAuthorityStatus status;
  final String validFrom;
  final String? expiresAt;

  Map<String, dynamic> toJson() => {
        'authorityId': authorityId,
        'role': role,
        'allowedSeverities': allowedSeverities.map((e) => e.wireName).toList(),
        'allowedRuleIds': allowedRuleIds,
        'allowedEnvironments':
            allowedEnvironments.map((e) => e.wireName).toList(),
        'allowedReleaseTypes':
            allowedReleaseTypes.map((e) => e.wireName).toList(),
        'maximumWaiverDuration': maximumWaiverDuration,
        'emergencyOnly': emergencyOnly,
        'separationOfDutiesGroup': separationOfDutiesGroup,
        'status': status.wireName,
        'validFrom': validFrom,
        if (expiresAt != null) 'expiresAt': expiresAt,
      };

  factory ReleaseWaiverAuthority.fromJson(Map<String, dynamic> json) {
    return ReleaseWaiverAuthority(
      authorityId: json['authorityId'] as String,
      role: json['role'] as String,
      allowedSeverities: (json['allowedSeverities'] as List<dynamic>)
          .map(
            (e) => ReleaseGovernanceRuleSeverityX.fromWireName(e as String),
          )
          .toList(),
      allowedRuleIds: (json['allowedRuleIds'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      allowedEnvironments: (json['allowedEnvironments'] as List<dynamic>)
          .map((e) => ReleaseEnvironmentX.fromWireName(e as String))
          .toList(),
      allowedReleaseTypes: (json['allowedReleaseTypes'] as List<dynamic>)
          .map((e) => ReleaseTypeX.fromWireName(e as String))
          .toList(),
      maximumWaiverDuration: json['maximumWaiverDuration'] as String,
      emergencyOnly: json['emergencyOnly'] as bool,
      separationOfDutiesGroup: json['separationOfDutiesGroup'] as String,
      status: ReleaseAuthorityStatusX.fromWireName(json['status'] as String),
      validFrom: json['validFrom'] as String,
      expiresAt: json['expiresAt'] as String?,
    );
  }
}

/// Waiver scope — must be release-bound.
class ReleaseWaiverScope {
  const ReleaseWaiverScope({
    required this.projectId,
    required this.releaseId,
    required this.environment,
    required this.releaseType,
    required this.policyId,
    required this.policyVersion,
    this.commitId,
    this.branch,
    this.ruleIds = const [],
    this.ruleSetIds = const [],
    this.qualityGateSnapshotId,
    this.qualityGateFingerprint,
  });

  final String projectId;
  final String releaseId;
  final String? commitId;
  final String? branch;
  final ReleaseEnvironment environment;
  final ReleaseType releaseType;
  final String policyId;
  final int policyVersion;
  final List<String> ruleIds;
  final List<String> ruleSetIds;
  final String? qualityGateSnapshotId;
  final String? qualityGateFingerprint;

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (branch != null) 'branch': branch,
        'environment': environment.wireName,
        'releaseType': releaseType.wireName,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'ruleIds': ruleIds,
        'ruleSetIds': ruleSetIds,
        if (qualityGateSnapshotId != null)
          'qualityGateSnapshotId': qualityGateSnapshotId,
        if (qualityGateFingerprint != null)
          'qualityGateFingerprint': qualityGateFingerprint,
      };

  factory ReleaseWaiverScope.fromJson(Map<String, dynamic> json) {
    return ReleaseWaiverScope(
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String,
      commitId: json['commitId'] as String?,
      branch: json['branch'] as String?,
      environment: ReleaseEnvironmentX.fromWireName(
        json['environment'] as String,
      ),
      releaseType: ReleaseTypeX.fromWireName(json['releaseType'] as String),
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      ruleIds: (json['ruleIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      ruleSetIds: (json['ruleSetIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      qualityGateSnapshotId: json['qualityGateSnapshotId'] as String?,
      qualityGateFingerprint: json['qualityGateFingerprint'] as String?,
    );
  }
}

/// Waiver expiration contract.
class ReleaseWaiverExpiration {
  const ReleaseWaiverExpiration({
    required this.validFrom,
    required this.expiresAt,
    required this.maximumDuration,
    required this.expirationMode,
    this.consumedAt,
  });

  final String validFrom;
  final String expiresAt;
  final String maximumDuration;
  final ReleaseWaiverExpirationMode expirationMode;
  final String? consumedAt;

  Map<String, dynamic> toJson() => {
        'validFrom': validFrom,
        'expiresAt': expiresAt,
        'maximumDuration': maximumDuration,
        'expirationMode': expirationMode.wireName,
        if (consumedAt != null) 'consumedAt': consumedAt,
      };

  factory ReleaseWaiverExpiration.fromJson(Map<String, dynamic> json) {
    return ReleaseWaiverExpiration(
      validFrom: json['validFrom'] as String,
      expiresAt: json['expiresAt'] as String,
      maximumDuration: json['maximumDuration'] as String,
      expirationMode: ReleaseWaiverExpirationModeX.fromWireName(
        json['expirationMode'] as String,
      ),
      consumedAt: json['consumedAt'] as String?,
    );
  }
}

/// Immutable published waiver record.
class ReleaseWaiver {
  const ReleaseWaiver({
    required this.waiverId,
    required this.releaseId,
    required this.policyId,
    required this.policyVersion,
    required this.status,
    required this.scope,
    required this.authority,
    required this.issuerId,
    required this.issuedAt,
    required this.expiration,
    required this.justification,
    required this.evidence,
    required this.fingerprint,
    required this.schemaVersion,
    this.compensatingControls = const [],
    this.affectedRuleIds = const [],
    this.affectedRuleSetIds = const [],
    this.affectedQualityGateEvaluationIds = const [],
    this.environmentScope = const [],
    this.releaseTypeScope = const [],
    this.maximumUses = 1,
    this.usageCount = 0,
    this.sourceReference,
    this.metadata = const {},
  });

  final String waiverId;
  final String releaseId;
  final String policyId;
  final int policyVersion;
  final ReleaseWaiverStatus status;
  final ReleaseWaiverScope scope;
  final ReleaseWaiverAuthority authority;
  final String issuerId;
  final String issuedAt;
  final ReleaseWaiverExpiration expiration;
  final String justification;
  final List<ReleaseCompensatingControl> compensatingControls;
  final List<ReleaseGovernanceEvidence> evidence;
  final List<String> affectedRuleIds;
  final List<String> affectedRuleSetIds;
  final List<String> affectedQualityGateEvaluationIds;
  final List<ReleaseEnvironment> environmentScope;
  final List<ReleaseType> releaseTypeScope;
  final int maximumUses;
  final int usageCount;
  final ReleaseGovernanceSourceReference? sourceReference;
  final String fingerprint;
  final int schemaVersion;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'waiverId': waiverId,
        'releaseId': releaseId,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'status': status.wireName,
        'scope': scope.toJson(),
        'authority': authority.toJson(),
        'issuerId': issuerId,
        'issuedAt': issuedAt,
        'expiration': expiration.toJson(),
        'justification': justification,
        'compensatingControls':
            compensatingControls.map((e) => e.toJson()).toList(),
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'affectedRuleIds': affectedRuleIds,
        'affectedRuleSetIds': affectedRuleSetIds,
        'affectedQualityGateEvaluationIds': affectedQualityGateEvaluationIds,
        'environmentScope': environmentScope.map((e) => e.wireName).toList(),
        'releaseTypeScope': releaseTypeScope.map((e) => e.wireName).toList(),
        'maximumUses': maximumUses,
        'usageCount': usageCount,
        if (sourceReference != null)
          'sourceReference': sourceReference!.toJson(),
        'fingerprint': fingerprint,
        'schemaVersion': schemaVersion,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseWaiver.fromJson(Map<String, dynamic> json) {
    return ReleaseWaiver(
      waiverId: json['waiverId'] as String,
      releaseId: json['releaseId'] as String,
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      status: ReleaseWaiverStatusX.fromWireName(json['status'] as String),
      scope: ReleaseWaiverScope.fromJson(json['scope'] as Map<String, dynamic>),
      authority: ReleaseWaiverAuthority.fromJson(
        json['authority'] as Map<String, dynamic>,
      ),
      issuerId: json['issuerId'] as String,
      issuedAt: json['issuedAt'] as String,
      expiration: ReleaseWaiverExpiration.fromJson(
        json['expiration'] as Map<String, dynamic>,
      ),
      justification: json['justification'] as String,
      compensatingControls:
          (json['compensatingControls'] as List<dynamic>? ?? [])
              .map(
                (e) => ReleaseCompensatingControl.fromJson(
                  e as Map<String, dynamic>,
                ),
              )
              .toList(),
      evidence: (json['evidence'] as List<dynamic>)
          .map(
            (e) => ReleaseGovernanceEvidence.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      affectedRuleIds: (json['affectedRuleIds'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      affectedRuleSetIds: (json['affectedRuleSetIds'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      affectedQualityGateEvaluationIds:
          (json['affectedQualityGateEvaluationIds'] as List<dynamic>)
              .map((e) => e.toString())
              .toList(),
      environmentScope: (json['environmentScope'] as List<dynamic>? ?? [])
          .map((e) => ReleaseEnvironmentX.fromWireName(e as String))
          .toList(),
      releaseTypeScope: (json['releaseTypeScope'] as List<dynamic>? ?? [])
          .map((e) => ReleaseTypeX.fromWireName(e as String))
          .toList(),
      maximumUses: json['maximumUses'] as int? ?? 1,
      usageCount: json['usageCount'] as int? ?? 0,
      sourceReference: json['sourceReference'] == null
          ? null
          : ReleaseGovernanceSourceReference.fromJson(
              json['sourceReference'] as Map<String, dynamic>,
            ),
      fingerprint: json['fingerprint'] as String,
      schemaVersion: json['schemaVersion'] as int,
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

/// Immutable collection of waivers for a release.
class ReleaseWaiverSet {
  const ReleaseWaiverSet({
    required this.releaseId,
    required this.waivers,
    required this.fingerprint,
    required this.schemaVersion,
    this.sourceReferences = const [],
    this.warnings = const [],
    this.limitations = const [],
  });

  final String releaseId;
  final List<ReleaseWaiver> waivers;
  final List<ReleaseGovernanceSourceReference> sourceReferences;
  final String fingerprint;
  final int schemaVersion;
  final List<String> warnings;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'releaseId': releaseId,
        'waivers': waivers.map((e) => e.toJson()).toList(),
        'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        'fingerprint': fingerprint,
        'schemaVersion': schemaVersion,
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseWaiverSet.fromJson(Map<String, dynamic> json) {
    return ReleaseWaiverSet(
      releaseId: json['releaseId'] as String,
      waivers: (json['waivers'] as List<dynamic>)
          .map((e) => ReleaseWaiver.fromJson(e as Map<String, dynamic>))
          .toList(),
      sourceReferences: (json['sourceReferences'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseGovernanceSourceReference.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      fingerprint: json['fingerprint'] as String,
      schemaVersion: json['schemaVersion'] as int,
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Policy rules governing waivers.
class ReleaseWaiverPolicy {
  const ReleaseWaiverPolicy({
    required this.maximumActiveWaivers,
    required this.maximumDuration,
    required this.allowedEnvironments,
    required this.allowedSeverities,
    required this.allowedAuthorities,
    required this.compensatingControlsRequired,
    required this.evidenceRequired,
    required this.singleUseForProduction,
    required this.expirationRequired,
    required this.commitBindingForProduction,
    required this.releaseBindingRequired,
    required this.criticalForbidden,
    required this.projectConsistencyForbidden,
    required this.commitConsistencyForbidden,
    required this.incompatibleSourcesForbidden,
  });

  final int maximumActiveWaivers;
  final String maximumDuration;
  final List<ReleaseEnvironment> allowedEnvironments;
  final List<ReleaseGovernanceRuleSeverity> allowedSeverities;
  final List<String> allowedAuthorities;
  final bool compensatingControlsRequired;
  final bool evidenceRequired;
  final bool singleUseForProduction;
  final bool expirationRequired;
  final bool commitBindingForProduction;
  final bool releaseBindingRequired;
  final bool criticalForbidden;
  final bool projectConsistencyForbidden;
  final bool commitConsistencyForbidden;
  final bool incompatibleSourcesForbidden;

  Map<String, dynamic> toJson() => {
        'maximumActiveWaivers': maximumActiveWaivers,
        'maximumDuration': maximumDuration,
        'allowedEnvironments':
            allowedEnvironments.map((e) => e.wireName).toList(),
        'allowedSeverities': allowedSeverities.map((e) => e.wireName).toList(),
        'allowedAuthorities': allowedAuthorities,
        'compensatingControlsRequired': compensatingControlsRequired,
        'evidenceRequired': evidenceRequired,
        'singleUseForProduction': singleUseForProduction,
        'expirationRequired': expirationRequired,
        'commitBindingForProduction': commitBindingForProduction,
        'releaseBindingRequired': releaseBindingRequired,
        'criticalForbidden': criticalForbidden,
        'projectConsistencyForbidden': projectConsistencyForbidden,
        'commitConsistencyForbidden': commitConsistencyForbidden,
        'incompatibleSourcesForbidden': incompatibleSourcesForbidden,
      };

  factory ReleaseWaiverPolicy.fromJson(Map<String, dynamic> json) {
    return ReleaseWaiverPolicy(
      maximumActiveWaivers: json['maximumActiveWaivers'] as int,
      maximumDuration: json['maximumDuration'] as String,
      allowedEnvironments: (json['allowedEnvironments'] as List<dynamic>)
          .map((e) => ReleaseEnvironmentX.fromWireName(e as String))
          .toList(),
      allowedSeverities: (json['allowedSeverities'] as List<dynamic>)
          .map(
            (e) => ReleaseGovernanceRuleSeverityX.fromWireName(e as String),
          )
          .toList(),
      allowedAuthorities: (json['allowedAuthorities'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      compensatingControlsRequired:
          json['compensatingControlsRequired'] as bool,
      evidenceRequired: json['evidenceRequired'] as bool,
      singleUseForProduction: json['singleUseForProduction'] as bool,
      expirationRequired: json['expirationRequired'] as bool,
      commitBindingForProduction: json['commitBindingForProduction'] as bool,
      releaseBindingRequired: json['releaseBindingRequired'] as bool,
      criticalForbidden: json['criticalForbidden'] as bool,
      projectConsistencyForbidden: json['projectConsistencyForbidden'] as bool,
      commitConsistencyForbidden: json['commitConsistencyForbidden'] as bool,
      incompatibleSourcesForbidden:
          json['incompatibleSourcesForbidden'] as bool,
    );
  }
}
