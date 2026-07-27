import 'mes_enums.dart';
import 'mes_policy.dart';
import 'mes_snapshot.dart';

/// Request to calculate official MES for a project.
class MESRequest {
  const MESRequest({
    required this.projectId,
    required this.createdAt,
    required this.metricsSnapshot,
    this.policyId,
    this.policy,
    this.guardianAnalysis,
    this.historyDiff,
    this.historySnapshot,
    this.gitRef,
    this.branch,
    this.sourceEventId,
    this.requestedDimensions,
    this.strictCompatibility = false,
    this.includeTrace = false,
    this.includeExplanations = true,
    this.eligibilityOnly = false,
    this.allowedPolicyStatuses = const [
      MESPolicyStatus.candidate,
      MESPolicyStatus.active,
    ],
  });

  final String projectId;
  final String createdAt;
  final Map<String, dynamic> metricsSnapshot;
  final String? policyId;
  final MESPolicy? policy;
  final Map<String, dynamic>? guardianAnalysis;
  final Map<String, dynamic>? historyDiff;
  final Map<String, dynamic>? historySnapshot;
  final String? gitRef;
  final String? branch;
  final String? sourceEventId;
  final Set<String>? requestedDimensions;
  final bool strictCompatibility;
  final bool includeTrace;
  final bool includeExplanations;
  final bool eligibilityOnly;
  final List<MESPolicyStatus> allowedPolicyStatuses;

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'createdAt': createdAt,
        'metricsSnapshot': metricsSnapshot,
        if (policyId != null) 'policyId': policyId,
        if (guardianAnalysis != null) 'guardianAnalysis': guardianAnalysis,
        if (historyDiff != null) 'historyDiff': historyDiff,
        if (historySnapshot != null) 'historySnapshot': historySnapshot,
        if (gitRef != null) 'gitRef': gitRef,
        if (branch != null) 'branch': branch,
        if (sourceEventId != null) 'sourceEventId': sourceEventId,
        if (requestedDimensions != null)
          'requestedDimensions': requestedDimensions!.toList()..sort(),
        'strictCompatibility': strictCompatibility,
        'includeTrace': includeTrace,
        'includeExplanations': includeExplanations,
        'eligibilityOnly': eligibilityOnly,
        'allowedPolicyStatuses':
            allowedPolicyStatuses.map((s) => s.wireName).toList(),
      };
}

/// Result of an MES calculation.
class MESResult {
  const MESResult({
    required this.status,
    required this.eligibility,
    this.snapshot,
    this.warnings = const [],
    this.errors = const [],
    this.idempotent = false,
  });

  final MESStatus status;
  final MESEligibility eligibility;
  final MESSnapshot? snapshot;
  final List<MESWarning> warnings;
  final List<MESError> errors;
  final bool idempotent;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'eligibility': eligibility.toJson(),
        if (snapshot != null) 'snapshot': snapshot!.toJson(),
        'warnings': warnings.map((w) => w.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
        'idempotent': idempotent,
      };
}
