import '../quality_gate/quality_gate_snapshot.dart';
import 'release_approval.dart';
import 'release_context.dart';
import 'release_governance_enums.dart';
import 'release_governance_messages.dart';
import 'release_governance_policy.dart';
import 'release_decision_snapshot.dart';
import 'release_waiver.dart';

/// Request to evaluate release governance.
class ReleaseGovernanceRequest {
  const ReleaseGovernanceRequest({
    required this.releaseContext,
    required this.referenceTime,
    this.policy,
    this.policyId,
    this.policyVersion,
    this.qualityGateSnapshot,
    this.qualityGateSnapshotId,
    this.approvalSet,
    this.approvalSetId,
    this.waiverSet,
    this.waiverSetId,
    this.useLatest = false,
    this.historicalEvaluation = false,
    this.strictCompatibility = true,
    this.includeEvidence = true,
    this.includeExplanations = true,
    this.publish = false,
    this.metadata = const {},
  });

  final ReleaseContext releaseContext;
  final ReleaseGovernancePolicy? policy;
  final String? policyId;
  final int? policyVersion;
  final QualityGateSnapshot? qualityGateSnapshot;
  final String? qualityGateSnapshotId;
  final ReleaseApprovalSet? approvalSet;
  final String? approvalSetId;
  final ReleaseWaiverSet? waiverSet;
  final String? waiverSetId;
  final bool useLatest;
  final String referenceTime;
  final bool historicalEvaluation;
  final bool strictCompatibility;
  final bool includeEvidence;
  final bool includeExplanations;
  final bool publish;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'releaseContext': releaseContext.toJson(),
        if (policy != null) 'policy': policy!.toJson(),
        if (policyId != null) 'policyId': policyId,
        if (policyVersion != null) 'policyVersion': policyVersion,
        if (qualityGateSnapshot != null)
          'qualityGateSnapshot': qualityGateSnapshot!.toJson(),
        if (qualityGateSnapshotId != null)
          'qualityGateSnapshotId': qualityGateSnapshotId,
        if (approvalSet != null) 'approvalSet': approvalSet!.toJson(),
        if (approvalSetId != null) 'approvalSetId': approvalSetId,
        if (waiverSet != null) 'waiverSet': waiverSet!.toJson(),
        if (waiverSetId != null) 'waiverSetId': waiverSetId,
        'useLatest': useLatest,
        'referenceTime': referenceTime,
        'historicalEvaluation': historicalEvaluation,
        'strictCompatibility': strictCompatibility,
        'includeEvidence': includeEvidence,
        'includeExplanations': includeExplanations,
        'publish': publish,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseGovernanceRequest.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceRequest(
      releaseContext: ReleaseContext.fromJson(
        json['releaseContext'] as Map<String, dynamic>,
      ),
      policy: json['policy'] == null
          ? null
          : ReleaseGovernancePolicy.fromJson(
              json['policy'] as Map<String, dynamic>,
            ),
      policyId: json['policyId'] as String?,
      policyVersion: json['policyVersion'] as int?,
      qualityGateSnapshot: json['qualityGateSnapshot'] == null
          ? null
          : QualityGateSnapshot.fromJson(
              json['qualityGateSnapshot'] as Map<String, dynamic>,
            ),
      qualityGateSnapshotId: json['qualityGateSnapshotId'] as String?,
      approvalSet: json['approvalSet'] == null
          ? null
          : ReleaseApprovalSet.fromJson(
              json['approvalSet'] as Map<String, dynamic>,
            ),
      approvalSetId: json['approvalSetId'] as String?,
      waiverSet: json['waiverSet'] == null
          ? null
          : ReleaseWaiverSet.fromJson(
              json['waiverSet'] as Map<String, dynamic>,
            ),
      waiverSetId: json['waiverSetId'] as String?,
      useLatest: json['useLatest'] as bool? ?? false,
      referenceTime: json['referenceTime'] as String,
      historicalEvaluation: json['historicalEvaluation'] as bool? ?? false,
      strictCompatibility: json['strictCompatibility'] as bool? ?? true,
      includeEvidence: json['includeEvidence'] as bool? ?? true,
      includeExplanations: json['includeExplanations'] as bool? ?? true,
      publish: json['publish'] as bool? ?? false,
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

/// Summary of source resolution (populated by engine in Part 2).
class ReleaseGovernanceSourceResolutionSummary {
  const ReleaseGovernanceSourceResolutionSummary({
    required this.resolvedSources,
    required this.unresolvedSources,
    required this.injectedSources,
    this.fingerprint,
  });

  final List<String> resolvedSources;
  final List<String> unresolvedSources;
  final List<String> injectedSources;
  final String? fingerprint;

  Map<String, dynamic> toJson() => {
        'resolvedSources': resolvedSources,
        'unresolvedSources': unresolvedSources,
        'injectedSources': injectedSources,
        if (fingerprint != null) 'fingerprint': fingerprint,
      };

  factory ReleaseGovernanceSourceResolutionSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseGovernanceSourceResolutionSummary(
      resolvedSources: (json['resolvedSources'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      unresolvedSources: (json['unresolvedSources'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      injectedSources: (json['injectedSources'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      fingerprint: json['fingerprint'] as String?,
    );
  }
}

/// Operational result of a release governance evaluation run.
class ReleaseGovernanceResult {
  const ReleaseGovernanceResult({
    required this.status,
    this.snapshot,
    this.policyReference,
    this.sourceResolutionSummary,
    this.publicationStatus,
    this.warnings = const [],
    this.errors = const [],
    this.limitations = const [],
    this.duration,
    this.metadata = const {},
  });

  final ReleaseGovernanceResultStatus status;
  final ReleaseDecisionSnapshot? snapshot;
  final ReleaseGovernancePolicyReference? policyReference;
  final ReleaseGovernanceSourceResolutionSummary? sourceResolutionSummary;
  final String? publicationStatus;
  final List<ReleaseGovernanceWarning> warnings;
  final List<ReleaseGovernanceError> errors;
  final List<ReleaseGovernanceLimitation> limitations;
  final Duration? duration;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        if (snapshot != null) 'snapshot': snapshot!.toJson(),
        if (policyReference != null)
          'policyReference': policyReference!.toJson(),
        if (sourceResolutionSummary != null)
          'sourceResolutionSummary': sourceResolutionSummary!.toJson(),
        if (publicationStatus != null) 'publicationStatus': publicationStatus,
        if (warnings.isNotEmpty)
          'warnings': warnings.map((e) => e.toJson()).toList(),
        if (errors.isNotEmpty) 'errors': errors.map((e) => e.toJson()).toList(),
        if (limitations.isNotEmpty)
          'limitations': limitations.map((e) => e.toJson()).toList(),
        if (duration != null) 'durationMs': duration!.inMilliseconds,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseGovernanceResult.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceResult(
      status: ReleaseGovernanceResultStatusX.fromWireName(
        json['status'] as String,
      ),
      snapshot: json['snapshot'] == null
          ? null
          : ReleaseDecisionSnapshot.fromJson(
              json['snapshot'] as Map<String, dynamic>,
            ),
      policyReference: json['policyReference'] == null
          ? null
          : ReleaseGovernancePolicyReference.fromJson(
              json['policyReference'] as Map<String, dynamic>,
            ),
      sourceResolutionSummary: json['sourceResolutionSummary'] == null
          ? null
          : ReleaseGovernanceSourceResolutionSummary.fromJson(
              json['sourceResolutionSummary'] as Map<String, dynamic>,
            ),
      publicationStatus: json['publicationStatus'] as String?,
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseGovernanceWarning.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      errors: (json['errors'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseGovernanceError.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseGovernanceLimitation.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      duration: json['durationMs'] == null
          ? null
          : Duration(milliseconds: json['durationMs'] as int),
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}
