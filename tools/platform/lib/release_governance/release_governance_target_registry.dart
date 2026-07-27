import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';
import '../models/release_governance/release_approval.dart';
import '../models/release_governance/release_context.dart';
import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_evidence.dart';
import '../models/release_governance/release_governance_policy.dart';
import '../models/release_governance/release_governance_rule_value.dart';
import '../models/release_governance/release_waiver.dart';
import 'resolved_release_governance_sources.dart';

/// Derived approval metrics for target resolution.
class ReleaseGovernanceApprovalMetrics {
  const ReleaseGovernanceApprovalMetrics({
    required this.requiredApprovalCount,
    required this.validApprovalCount,
    required this.missingApprovalCount,
    required this.rejectedApprovalCount,
    required this.expiredApprovalCount,
    required this.separationOfDutiesSatisfied,
    required this.approvalAuthorityPresent,
    required this.approvalEvidenceComplete,
  });

  final int requiredApprovalCount;
  final int validApprovalCount;
  final int missingApprovalCount;
  final int rejectedApprovalCount;
  final int expiredApprovalCount;
  final bool separationOfDutiesSatisfied;
  final bool approvalAuthorityPresent;
  final bool approvalEvidenceComplete;

  static ReleaseGovernanceApprovalMetrics compute({
    required ReleaseGovernancePolicy policy,
    required ReleaseContext releaseContext,
    required ResolvedReleaseGovernanceSource<ReleaseApprovalSet> approvalSet,
    required String referenceTime,
  }) {
    if (!approvalSet.isAvailable) {
      final required = policy.approvalRequirements
          .where((r) => r.enabled && _requirementApplies(r, releaseContext))
          .fold<int>(0, (sum, r) => sum + r.minimumCount);
      return ReleaseGovernanceApprovalMetrics(
        requiredApprovalCount: required,
        validApprovalCount: 0,
        missingApprovalCount: required,
        rejectedApprovalCount: 0,
        expiredApprovalCount: 0,
        separationOfDutiesSatisfied: required == 0,
        approvalAuthorityPresent: false,
        approvalEvidenceComplete: false,
      );
    }

    final approvals = approvalSet.resolvedArtifact!.approvals;
    final applicableRequirements = policy.approvalRequirements
        .where((r) => r.enabled && _requirementApplies(r, releaseContext))
        .toList()
      ..sort((a, b) {
        final orderCmp = a.order.compareTo(b.order);
        if (orderCmp != 0) return orderCmp;
        return a.requirementId.compareTo(b.requirementId);
      });

    var requiredCount = 0;
    var validCount = 0;
    var missingCount = 0;
    var rejectedCount = 0;
    var expiredCount = 0;
    var sodSatisfied = true;
    var authorityPresent = true;
    var evidenceComplete = true;

    final refTime = DateTime.tryParse(referenceTime)?.toUtc();

    final approvedForContext = approvals
        .where(
          (a) =>
              a.status == ReleaseApprovalStatus.approved &&
              !_isExpired(a.expiresAt, refTime) &&
              _authorityValid(a.authority, refTime),
        )
        .toList()
      ..sort((a, b) => a.approvalId.compareTo(b.approvalId));

    ReleaseSeparationOfDutiesRule? separationOfDutiesRule;

    for (final requirement in applicableRequirements) {
      separationOfDutiesRule ??= requirement.separationOfDutiesRule;
      requiredCount += requirement.minimumCount;
      final matching = approvals
          .where((a) => a.approvalType == requirement.approvalType)
          .toList()
        ..sort((a, b) => a.approvalId.compareTo(b.approvalId));

      var validForRequirement = 0;
      for (final approval in matching) {
        if (approval.status == ReleaseApprovalStatus.rejected) {
          rejectedCount++;
          continue;
        }
        if (_isExpired(approval.expiresAt, refTime)) {
          expiredCount++;
          continue;
        }
        if (approval.status != ReleaseApprovalStatus.approved) continue;
        if (!_authorityValid(approval.authority, refTime)) {
          continue;
        }
        if (requirement.evidenceRequired && approval.evidence.isEmpty) {
          evidenceComplete = false;
        }
        validForRequirement++;
      }
      validCount += validForRequirement;

      final missing = requirement.minimumCount - validForRequirement;
      if (missing > 0) missingCount += missing;

      if (requirement.allowedAuthorityIds.isNotEmpty) {
        final hasAuthority = matching.any(
          (a) =>
              a.status == ReleaseApprovalStatus.approved &&
              requirement.allowedAuthorityIds.contains(a.authority.authorityId),
        );
        if (!hasAuthority && requirement.minimumCount > 0) {
          authorityPresent = false;
        }
      }
    }

    if (separationOfDutiesRule != null) {
      sodSatisfied = _checkSeparationOfDuties(
        separationOfDutiesRule,
        approvedForContext,
        releaseContext,
      );
    }

    return ReleaseGovernanceApprovalMetrics(
      requiredApprovalCount: requiredCount,
      validApprovalCount: validCount,
      missingApprovalCount: missingCount,
      rejectedApprovalCount: rejectedCount,
      expiredApprovalCount: expiredCount,
      separationOfDutiesSatisfied: sodSatisfied,
      approvalAuthorityPresent: authorityPresent,
      approvalEvidenceComplete: evidenceComplete,
    );
  }

  static bool requirementApplies(
    ReleaseApprovalRequirement requirement,
    ReleaseContext context,
  ) =>
      _requirementApplies(requirement, context);

  static bool _requirementApplies(
    ReleaseApprovalRequirement requirement,
    ReleaseContext context,
  ) {
    if (!requirement.environmentScope.contains(context.environment)) {
      return false;
    }
    if (!requirement.releaseTypeScope.contains(context.releaseType)) {
      return false;
    }
    return true;
  }

  static bool _isExpired(String? expiresAt, DateTime? referenceTime) {
    if (expiresAt == null || referenceTime == null) return false;
    final expiry = DateTime.tryParse(expiresAt)?.toUtc();
    if (expiry == null) return false;
    return expiry.isBefore(referenceTime);
  }

  static bool _authorityValid(
    ReleaseApprovalAuthority authority,
    DateTime? referenceTime,
  ) {
    if (authority.status != ReleaseAuthorityStatus.active) return false;
    if (referenceTime == null) return true;
    final validFrom = DateTime.tryParse(authority.validFrom)?.toUtc();
    if (validFrom != null && validFrom.isAfter(referenceTime)) return false;
    if (_isExpired(authority.expiresAt, referenceTime)) return false;
    return true;
  }

  static bool _checkSeparationOfDuties(
    ReleaseSeparationOfDutiesRule rule,
    Iterable<ReleaseApproval> approvals,
    ReleaseContext context,
  ) {
    final approved = approvals.toList();
    final approverIds = approved.map((a) => a.approverId).toSet();
    if (approverIds.length < rule.minimumDistinctApprovers) return false;
    if (rule.requesterCannotApprove &&
        approved.any((a) => a.approverId == context.requestedBy)) {
      return false;
    }
    final groups = approved.map((a) => a.authority.separationOfDutiesGroup);
    if (groups.length != groups.toSet().length &&
        rule.prohibitedAuthorityGroups.isNotEmpty) {
      return false;
    }
    return true;
  }
}

/// Derived waiver metrics for target resolution.
class ReleaseGovernanceWaiverMetrics {
  const ReleaseGovernanceWaiverMetrics({
    required this.activeWaiverCount,
    required this.invalidWaiverCount,
    required this.expiredWaiverCount,
    required this.waiverScopeValid,
    required this.waiverAuthorityValid,
    required this.waiverEvidenceComplete,
    required this.waiverExpirationValid,
    required this.waiverLimitSatisfied,
  });

  final int activeWaiverCount;
  final int invalidWaiverCount;
  final int expiredWaiverCount;
  final bool waiverScopeValid;
  final bool waiverAuthorityValid;
  final bool waiverEvidenceComplete;
  final bool waiverExpirationValid;
  final bool waiverLimitSatisfied;

  static ReleaseGovernanceWaiverMetrics compute({
    required ReleaseGovernancePolicy policy,
    required ReleaseContext releaseContext,
    required ResolvedReleaseGovernanceSource<ReleaseWaiverSet> waiverSet,
    required String referenceTime,
  }) {
    final waiverPolicy = policy.waiverRules;
    if (!waiverSet.isAvailable) {
      return const ReleaseGovernanceWaiverMetrics(
        activeWaiverCount: 0,
        invalidWaiverCount: 0,
        expiredWaiverCount: 0,
        waiverScopeValid: true,
        waiverAuthorityValid: true,
        waiverEvidenceComplete: true,
        waiverExpirationValid: true,
        waiverLimitSatisfied: true,
      );
    }

    final refTime = DateTime.tryParse(referenceTime)?.toUtc();
    var active = 0;
    var invalid = 0;
    var expired = 0;
    var scopeValid = true;
    var authorityValid = true;
    var evidenceComplete = true;
    var expirationValid = true;

    for (final waiver in waiverSet.resolvedArtifact!.waivers) {
      if (waiver.status == ReleaseWaiverStatus.invalid) {
        invalid++;
        continue;
      }
      if (_waiverExpired(waiver, refTime)) {
        expired++;
        continue;
      }
      if (waiver.status == ReleaseWaiverStatus.active ||
          waiver.status == ReleaseWaiverStatus.approved) {
        active++;
      }
      if (waiver.scope.projectId != releaseContext.projectId ||
          waiver.scope.releaseId != releaseContext.releaseId) {
        scopeValid = false;
      }
      if (waiver.authority.status != ReleaseAuthorityStatus.active) {
        authorityValid = false;
      }
      if (waiverPolicy.evidenceRequired && waiver.evidence.isEmpty) {
        evidenceComplete = false;
      }
      if (waiverPolicy.expirationRequired &&
          waiver.expiration.expiresAt.isEmpty) {
        expirationValid = false;
      }
    }

    final limitSatisfied = active <= waiverPolicy.maximumActiveWaivers;

    return ReleaseGovernanceWaiverMetrics(
      activeWaiverCount: active,
      invalidWaiverCount: invalid,
      expiredWaiverCount: expired,
      waiverScopeValid: scopeValid,
      waiverAuthorityValid: authorityValid,
      waiverEvidenceComplete: evidenceComplete,
      waiverExpirationValid: expirationValid,
      waiverLimitSatisfied: limitSatisfied,
    );
  }

  static bool _waiverExpired(ReleaseWaiver waiver, DateTime? referenceTime) {
    if (referenceTime == null) return false;
    if (waiver.status == ReleaseWaiverStatus.expired) return true;
    final expiresAt = DateTime.tryParse(waiver.expiration.expiresAt)?.toUtc();
    if (expiresAt == null) return false;
    return expiresAt.isBefore(referenceTime);
  }
}

/// Resolves all [ReleaseGovernanceRuleTarget] values from published artifacts.
class ReleaseGovernanceTargetRegistry {
  const ReleaseGovernanceTargetRegistry();

  ReleaseGovernanceTargetResolution resolve(
    ReleaseGovernanceRule rule,
    ResolvedReleaseGovernanceSources sources,
    ReleaseGovernanceEvaluationContext context,
  ) {
    final approvalMetrics = ReleaseGovernanceApprovalMetrics.compute(
      policy: context.policy,
      releaseContext: context.releaseContext,
      approvalSet: sources.approvalSet,
      referenceTime: context.referenceTime,
    );
    final waiverMetrics = ReleaseGovernanceWaiverMetrics.compute(
      policy: context.policy,
      releaseContext: context.releaseContext,
      waiverSet: sources.waiverSet,
      referenceTime: context.referenceTime,
    );

    final qg = sources.qualityGateSnapshot;
    final qgRef = _qgSourceRef(qg);

    switch (rule.target) {
      case ReleaseGovernanceRuleTarget.qualityGateDecision:
        return _resolveQgString(qg, qgRef, _qgDecision(qg));
      case ReleaseGovernanceRuleTarget.qualityGatePolicyId:
        return _resolveQgString(
          qg,
          qgRef,
          qg.resolvedArtifact?.metadata.policyId,
        );
      case ReleaseGovernanceRuleTarget.qualityGatePolicyVersion:
        return _resolveQgInteger(
          qg,
          qgRef,
          qg.resolvedArtifact?.metadata.policyVersion,
        );
      case ReleaseGovernanceRuleTarget.qualityGateEligibility:
        return _resolveQgEnum(
          qg,
          qgRef,
          'eligibility',
          qg.resolvedArtifact?.eligibility.status.wireName,
        );
      case ReleaseGovernanceRuleTarget.qualityGateCompatibility:
        return _resolveQgEnum(
          qg,
          qgRef,
          'compatibility',
          qg.resolvedArtifact?.compatibility.status.wireName,
        );
      case ReleaseGovernanceRuleTarget.qualityGateCoverage:
        return _resolveQgPercentage(
          qg,
          qgRef,
          qg.resolvedArtifact?.coverage.overallRuleCoveragePercentage,
        );
      case ReleaseGovernanceRuleTarget.qualityGateBlockingFailureCount:
        return _resolveQgInteger(
          qg,
          qgRef,
          qg.resolvedArtifact?.metadata.blockingFailureCount,
        );
      case ReleaseGovernanceRuleTarget.qualityGateCriticalFailureCount:
        return _resolveQgInteger(
          qg,
          qgRef,
          _criticalFailureCount(qg.resolvedArtifact),
        );
      case ReleaseGovernanceRuleTarget.qualityGateFailedRuleCount:
        return _resolveQgInteger(
          qg,
          qgRef,
          qg.resolvedArtifact?.metadata.failedRuleCount,
        );
      case ReleaseGovernanceRuleTarget.qualityGateFingerprint:
        return _resolveQgString(
          qg,
          qgRef,
          qg.resolvedArtifact?.metadata.qualityGateFingerprint,
        );
      case ReleaseGovernanceRuleTarget.qualityGateAge:
        return _resolveQgDuration(qg, qgRef, context.referenceTime);
      case ReleaseGovernanceRuleTarget.qualityGateProjectConsistency:
        return _resolveQgBoolean(
          qg,
          qgRef,
          qg.resolvedArtifact?.metadata.projectId ==
              context.releaseContext.projectId,
        );
      case ReleaseGovernanceRuleTarget.qualityGateCommitConsistency:
        return _resolveQgBoolean(
          qg,
          qgRef,
          qg.resolvedArtifact?.metadata.commitId ==
              context.releaseContext.commitId,
        );
      case ReleaseGovernanceRuleTarget.releaseProjectId:
        return _resolved(
          ReleaseGovernanceStringValue(context.releaseContext.projectId),
          _contextRef(sources),
        );
      case ReleaseGovernanceRuleTarget.releaseCommitId:
        return _resolved(
          ReleaseGovernanceStringValue(context.releaseContext.commitId),
          _contextRef(sources),
        );
      case ReleaseGovernanceRuleTarget.releaseBranch:
        return _resolved(
          ReleaseGovernanceStringValue(context.releaseContext.branch),
          _contextRef(sources),
        );
      case ReleaseGovernanceRuleTarget.releaseVersion:
        return _resolved(
          ReleaseGovernanceStringValue(context.releaseContext.releaseVersion),
          _contextRef(sources),
        );
      case ReleaseGovernanceRuleTarget.releaseEnvironment:
        return _resolved(
          ReleaseGovernanceStringValue(
            context.releaseContext.environment.wireName,
          ),
          _contextRef(sources),
        );
      case ReleaseGovernanceRuleTarget.releaseType:
        return _resolved(
          ReleaseGovernanceStringValue(
            context.releaseContext.releaseType.wireName,
          ),
          _contextRef(sources),
        );
      case ReleaseGovernanceRuleTarget.releaseArtifactCount:
        return _resolved(
          ReleaseGovernanceIntegerValue(
            context.releaseContext.artifactReferences.length,
          ),
          _contextRef(sources),
        );
      case ReleaseGovernanceRuleTarget.releaseRequestedByPresent:
        return _resolved(
          ReleaseGovernanceBooleanValue(
            context.releaseContext.requestedBy.isNotEmpty,
          ),
          _contextRef(sources),
        );
      case ReleaseGovernanceRuleTarget.releaseTargetDateValid:
        return _resolved(
          ReleaseGovernanceBooleanValue(
            _targetDateValid(
              context.releaseContext.targetDate,
              context.referenceTime,
            ),
          ),
          _contextRef(sources),
        );
      case ReleaseGovernanceRuleTarget.requiredApprovalCount:
        return _resolved(
          ReleaseGovernanceIntegerValue(approvalMetrics.requiredApprovalCount),
          _approvalRef(sources),
        );
      case ReleaseGovernanceRuleTarget.validApprovalCount:
        return _resolved(
          ReleaseGovernanceIntegerValue(approvalMetrics.validApprovalCount),
          _approvalRef(sources),
        );
      case ReleaseGovernanceRuleTarget.missingApprovalCount:
        return _resolved(
          ReleaseGovernanceIntegerValue(approvalMetrics.missingApprovalCount),
          _approvalRef(sources),
        );
      case ReleaseGovernanceRuleTarget.rejectedApprovalCount:
        return _resolved(
          ReleaseGovernanceIntegerValue(approvalMetrics.rejectedApprovalCount),
          _approvalRef(sources),
        );
      case ReleaseGovernanceRuleTarget.expiredApprovalCount:
        return _resolved(
          ReleaseGovernanceIntegerValue(approvalMetrics.expiredApprovalCount),
          _approvalRef(sources),
        );
      case ReleaseGovernanceRuleTarget.approvalAuthorityPresent:
        return _resolved(
          ReleaseGovernanceBooleanValue(
              approvalMetrics.approvalAuthorityPresent),
          _approvalRef(sources),
        );
      case ReleaseGovernanceRuleTarget.separationOfDutiesSatisfied:
        return _resolved(
          ReleaseGovernanceBooleanValue(
            approvalMetrics.separationOfDutiesSatisfied,
          ),
          _approvalRef(sources),
        );
      case ReleaseGovernanceRuleTarget.approvalEvidenceComplete:
        return _resolved(
          ReleaseGovernanceBooleanValue(
              approvalMetrics.approvalEvidenceComplete),
          _approvalRef(sources),
        );
      case ReleaseGovernanceRuleTarget.activeWaiverCount:
        return _resolved(
          ReleaseGovernanceIntegerValue(waiverMetrics.activeWaiverCount),
          _waiverRef(sources),
        );
      case ReleaseGovernanceRuleTarget.invalidWaiverCount:
        return _resolved(
          ReleaseGovernanceIntegerValue(waiverMetrics.invalidWaiverCount),
          _waiverRef(sources),
        );
      case ReleaseGovernanceRuleTarget.expiredWaiverCount:
        return _resolved(
          ReleaseGovernanceIntegerValue(waiverMetrics.expiredWaiverCount),
          _waiverRef(sources),
        );
      case ReleaseGovernanceRuleTarget.waiverScopeValid:
        return _resolved(
          ReleaseGovernanceBooleanValue(waiverMetrics.waiverScopeValid),
          _waiverRef(sources),
        );
      case ReleaseGovernanceRuleTarget.waiverAuthorityValid:
        return _resolved(
          ReleaseGovernanceBooleanValue(waiverMetrics.waiverAuthorityValid),
          _waiverRef(sources),
        );
      case ReleaseGovernanceRuleTarget.waiverEvidenceComplete:
        return _resolved(
          ReleaseGovernanceBooleanValue(waiverMetrics.waiverEvidenceComplete),
          _waiverRef(sources),
        );
      case ReleaseGovernanceRuleTarget.waiverExpirationValid:
        return _resolved(
          ReleaseGovernanceBooleanValue(waiverMetrics.waiverExpirationValid),
          _waiverRef(sources),
        );
      case ReleaseGovernanceRuleTarget.waiverLimitSatisfied:
        return _resolved(
          ReleaseGovernanceBooleanValue(waiverMetrics.waiverLimitSatisfied),
          _waiverRef(sources),
        );
      case ReleaseGovernanceRuleTarget.projectConsistency:
        return _resolved(
          ReleaseGovernanceBooleanValue(
            _projectConsistency(sources, context),
          ),
          _contextRef(sources),
        );
      case ReleaseGovernanceRuleTarget.commitConsistency:
        return _resolved(
          ReleaseGovernanceBooleanValue(
            _commitConsistency(sources, context),
          ),
          _contextRef(sources),
        );
      case ReleaseGovernanceRuleTarget.environmentCompatibility:
        return _resolved(
          ReleaseGovernanceBooleanValue(
            context.policy.supportedEnvironments
                .contains(context.releaseContext.environment),
          ),
          _contextRef(sources),
        );
      case ReleaseGovernanceRuleTarget.policyCompatibility:
        return _resolved(
          ReleaseGovernanceBooleanValue(
            sources.policy.isAvailable &&
                sources.policy.resolvedArtifact!.metadata.policyId ==
                    context.policy.metadata.policyId,
          ),
          _policyRef(sources),
        );
      case ReleaseGovernanceRuleTarget.sourceFreshness:
        return _resolveQgDuration(qg, qgRef, context.referenceTime);
      case ReleaseGovernanceRuleTarget.requiredSourcesAvailable:
        return _resolved(
          ReleaseGovernanceBooleanValue(_requiredSourcesAvailable(sources)),
          null,
        );
    }
  }

  static String? _qgDecision(
    ResolvedReleaseGovernanceSource<QualityGateSnapshot> qg,
  ) {
    return qg.resolvedArtifact?.decision.wireName;
  }

  static int _criticalFailureCount(QualityGateSnapshot? snapshot) {
    if (snapshot == null) return 0;
    return snapshot.evaluations
        .where(
          (e) =>
              e.status == QualityGateRuleStatus.failed &&
              e.severity == QualityGateRuleSeverity.critical,
        )
        .length;
  }

  static bool _targetDateValid(String? targetDate, String referenceTime) {
    if (targetDate == null || targetDate.isEmpty) return true;
    final target = DateTime.tryParse(targetDate)?.toUtc();
    final ref = DateTime.tryParse(referenceTime)?.toUtc();
    if (target == null || ref == null) return false;
    return !target.isBefore(ref);
  }

  static bool _projectConsistency(
    ResolvedReleaseGovernanceSources sources,
    ReleaseGovernanceEvaluationContext context,
  ) {
    final expected = context.releaseContext.projectId;
    if (sources.qualityGateSnapshot.isAvailable &&
        sources.qualityGateSnapshot.resolvedArtifact!.metadata.projectId !=
            expected) {
      return false;
    }
    return true;
  }

  static bool _commitConsistency(
    ResolvedReleaseGovernanceSources sources,
    ReleaseGovernanceEvaluationContext context,
  ) {
    final expected = context.releaseContext.commitId;
    if (sources.qualityGateSnapshot.isAvailable) {
      final qgCommit =
          sources.qualityGateSnapshot.resolvedArtifact!.metadata.commitId;
      if (qgCommit != null && qgCommit.isNotEmpty && qgCommit != expected) {
        return false;
      }
    }
    return true;
  }

  static bool _requiredSourcesAvailable(
      ResolvedReleaseGovernanceSources sources) {
    return sources.releaseContext.isAvailable &&
        sources.qualityGateSnapshot.isAvailable &&
        sources.policy.isAvailable;
  }

  ReleaseGovernanceTargetResolution _resolveQgString(
    ResolvedReleaseGovernanceSource<QualityGateSnapshot> qg,
    ReleaseGovernanceSourceReference? ref,
    String? value,
  ) {
    if (!qg.isAvailable || value == null) return _unavailable(qg);
    return _resolved(ReleaseGovernanceStringValue(value), ref);
  }

  ReleaseGovernanceTargetResolution _resolveQgInteger(
    ResolvedReleaseGovernanceSource<QualityGateSnapshot> qg,
    ReleaseGovernanceSourceReference? ref,
    int? value,
  ) {
    if (!qg.isAvailable || value == null) return _unavailable(qg);
    return _resolved(ReleaseGovernanceIntegerValue(value), ref);
  }

  ReleaseGovernanceTargetResolution _resolveQgBoolean(
    ResolvedReleaseGovernanceSource<QualityGateSnapshot> qg,
    ReleaseGovernanceSourceReference? ref,
    bool? value,
  ) {
    if (!qg.isAvailable || value == null) return _unavailable(qg);
    return _resolved(ReleaseGovernanceBooleanValue(value), ref);
  }

  ReleaseGovernanceTargetResolution _resolveQgPercentage(
    ResolvedReleaseGovernanceSource<QualityGateSnapshot> qg,
    ReleaseGovernanceSourceReference? ref,
    double? value,
  ) {
    if (!qg.isAvailable || value == null) return _unavailable(qg);
    return _resolved(ReleaseGovernancePercentageValue(value), ref);
  }

  ReleaseGovernanceTargetResolution _resolveQgEnum(
    ResolvedReleaseGovernanceSource<QualityGateSnapshot> qg,
    ReleaseGovernanceSourceReference? ref,
    String domain,
    String? value,
  ) {
    if (!qg.isAvailable || value == null) return _unavailable(qg);
    return _resolved(
      ReleaseGovernanceEnumValue(domain: domain, value: value),
      ref,
    );
  }

  ReleaseGovernanceTargetResolution _resolveQgDuration(
    ResolvedReleaseGovernanceSource<QualityGateSnapshot> qg,
    ReleaseGovernanceSourceReference? ref,
    String referenceTime,
  ) {
    if (!qg.isAvailable) return _unavailable(qg);
    final evaluatedAt = qg.resolvedArtifact?.metadata.evaluatedAt;
    if (evaluatedAt == null) return _unavailable(qg);
    final refTime = DateTime.tryParse(referenceTime)?.toUtc();
    final evaluated = DateTime.tryParse(evaluatedAt)?.toUtc();
    if (refTime == null || evaluated == null) return _unavailable(qg);
    final seconds = refTime.difference(evaluated).inSeconds.abs();
    return _resolved(
      ReleaseGovernanceDurationValue(_secondsToIso8601(seconds)),
      ref,
    );
  }

  String _secondsToIso8601(int seconds) {
    if (seconds >= 86400) return 'P${seconds ~/ 86400}D';
    if (seconds >= 3600) return 'PT${seconds ~/ 3600}H';
    if (seconds >= 60) return 'PT${seconds ~/ 60}M';
    return 'PT${seconds}S';
  }

  ReleaseGovernanceTargetResolution _resolved(
    ReleaseGovernanceRuleValue value,
    ReleaseGovernanceSourceReference? ref,
  ) {
    return ReleaseGovernanceTargetResolution(
      status: ReleaseGovernanceTargetResolutionStatus.resolved,
      actualValue: value,
      sourceReference: ref,
      evidenceType:
          ref?.sourceType == ReleaseGovernanceSourceType.qualityGateSnapshot
              ? ReleaseGovernanceEvidenceType.qualityGate
              : ReleaseGovernanceEvidenceType.operational,
    );
  }

  ReleaseGovernanceTargetResolution _unavailable(
    ResolvedReleaseGovernanceSource<dynamic> source,
  ) {
    return const ReleaseGovernanceTargetResolution(
      status: ReleaseGovernanceTargetResolutionStatus.unavailable,
      evidenceType: ReleaseGovernanceEvidenceType.unavailable,
    );
  }

  ReleaseGovernanceSourceReference? _qgSourceRef(
    ResolvedReleaseGovernanceSource<QualityGateSnapshot> qg,
  ) {
    if (!qg.isAvailable) return null;
    final snapshot = qg.resolvedArtifact!;
    return ReleaseGovernanceSourceReference(
      sourceType: ReleaseGovernanceSourceType.qualityGateSnapshot,
      resolutionMode: qg.resolutionMode,
      requestedId: qg.requestedId ?? snapshot.metadata.qualityGateSnapshotId,
      resolvedId: snapshot.metadata.qualityGateSnapshotId,
      fingerprint: snapshot.metadata.qualityGateFingerprint,
      projectId: snapshot.metadata.projectId,
      commitId: snapshot.metadata.commitId,
      policyId: snapshot.metadata.policyId,
      policyVersion: snapshot.metadata.policyVersion,
      compatibility: _qgCompatibility(snapshot),
    );
  }

  ReleaseGovernanceCompatibilityStatus _qgCompatibility(
    QualityGateSnapshot snapshot,
  ) {
    return switch (snapshot.compatibility.status) {
      QualityGateCompatibilityStatus.compatible =>
        ReleaseGovernanceCompatibilityStatus.compatible,
      QualityGateCompatibilityStatus.partiallyCompatible =>
        ReleaseGovernanceCompatibilityStatus.partiallyCompatible,
      QualityGateCompatibilityStatus.incompatible =>
        ReleaseGovernanceCompatibilityStatus.incompatible,
      QualityGateCompatibilityStatus.unknown =>
        ReleaseGovernanceCompatibilityStatus.unknown,
    };
  }

  ReleaseGovernanceSourceReference _contextRef(
    ResolvedReleaseGovernanceSources sources,
  ) {
    final ctx = sources.releaseContext;
    return ReleaseGovernanceSourceReference(
      sourceType: ReleaseGovernanceSourceType.releaseContext,
      resolutionMode: ctx.resolutionMode,
      requestedId: ctx.resolvedId ?? ctx.resolvedArtifact!.releaseId,
      resolvedId: ctx.resolvedArtifact!.releaseId,
      fingerprint: ctx.fingerprint,
      projectId: ctx.resolvedArtifact!.projectId,
      commitId: ctx.resolvedArtifact!.commitId,
    );
  }

  ReleaseGovernanceSourceReference? _approvalRef(
    ResolvedReleaseGovernanceSources sources,
  ) {
    if (!sources.approvalSet.isAvailable) return null;
    return ReleaseGovernanceSourceReference(
      sourceType: ReleaseGovernanceSourceType.approvalSet,
      resolutionMode: sources.approvalSet.resolutionMode,
      requestedId: sources.approvalSet.resolvedId ?? '',
      resolvedId: sources.approvalSet.resolvedId,
      fingerprint: sources.approvalSet.fingerprint,
    );
  }

  ReleaseGovernanceSourceReference? _waiverRef(
    ResolvedReleaseGovernanceSources sources,
  ) {
    if (!sources.waiverSet.isAvailable) return null;
    return ReleaseGovernanceSourceReference(
      sourceType: ReleaseGovernanceSourceType.waiverSet,
      resolutionMode: sources.waiverSet.resolutionMode,
      requestedId: sources.waiverSet.resolvedId ?? '',
      resolvedId: sources.waiverSet.resolvedId,
      fingerprint: sources.waiverSet.fingerprint,
    );
  }

  ReleaseGovernanceSourceReference? _policyRef(
    ResolvedReleaseGovernanceSources sources,
  ) {
    if (!sources.policy.isAvailable) return null;
    final policy = sources.policy.resolvedArtifact!;
    return ReleaseGovernanceSourceReference(
      sourceType: ReleaseGovernanceSourceType.releaseGovernancePolicy,
      resolutionMode: sources.policy.resolutionMode,
      requestedId: policy.metadata.policyId,
      resolvedId: policy.metadata.policyId,
      fingerprint: policy.metadata.fingerprint,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
    );
  }
}
