import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_messages.dart';
import '../models/quality_gate/quality_gate_policy.dart';
import '../models/quality_gate/quality_gate_request.dart';
import 'quality_gate_canonical_serializer.dart';
import 'resolved_quality_gate_sources.dart';

/// Evaluates whether a policy can be applied to the current context.
class QualityGateEligibilityEvaluator {
  const QualityGateEligibilityEvaluator({
    QualityGateCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const QualityGateCanonicalSerializer();

  final QualityGateCanonicalSerializer _serializer;

  QualityGateEligibility evaluate({
    required QualityGateRequest request,
    required QualityGatePolicy policy,
    required ResolvedQualityGateSources sources,
    required QualityGateCompatibility compatibility,
    required List<QualityGateRule> enabledRules,
  }) {
    final reasons = <String>[];
    final requiredSources = policy.requiredSourceTypes;
    final availableSources = <QualityGateSourceType>[];
    final missingSources = <QualityGateSourceType>[];
    final incompatibleSources = compatibility.incompatibleSources;

    for (final type in requiredSources) {
      final source = sources.allSources.firstWhere((s) => s.sourceType == type);
      if (source.isAvailable) {
        availableSources.add(type);
      } else {
        missingSources.add(type);
        reasons.add('Missing required source ${type.wireName}');
      }
    }

    if (policy.metadata.status == QualityGatePolicyStatus.retired &&
        !request.historicalEvaluation) {
      reasons.add('Policy retired for normal evaluation');
    }

    if (enabledRules.isEmpty) {
      reasons.add('No enabled normative rules to evaluate');
    }

    final status = _deriveStatus(
      reasons: reasons,
      missingSources: missingSources,
      incompatibleSources: incompatibleSources,
      compatibility: compatibility,
      enabledRules: enabledRules,
    );

    final fingerprint = _serializer.fingerprintFromString(
      {
        'status': status.wireName,
        'required': requiredSources.map((e) => e.wireName).toList()..sort(),
        'missing': missingSources.map((e) => e.wireName).toList()..sort(),
        'incompatible': incompatibleSources.map((e) => e.wireName).toList()
          ..sort(),
      }.toString(),
    );

    return QualityGateEligibility(
      status: status,
      reasons: reasons,
      requiredSources: requiredSources,
      availableSources: availableSources,
      missingSources: missingSources,
      incompatibleSources: incompatibleSources,
      eligibilityFingerprint: fingerprint,
    );
  }

  QualityGateEligibilityStatus _deriveStatus({
    required List<String> reasons,
    required List<QualityGateSourceType> missingSources,
    required List<QualityGateSourceType> incompatibleSources,
    required QualityGateCompatibility compatibility,
    required List<QualityGateRule> enabledRules,
  }) {
    if (compatibility.status == QualityGateCompatibilityStatus.incompatible &&
        incompatibleSources.isNotEmpty) {
      return QualityGateEligibilityStatus.ineligible;
    }
    if (missingSources.isNotEmpty) {
      return missingSources.length == reasons.length
          ? QualityGateEligibilityStatus.ineligible
          : QualityGateEligibilityStatus.partiallyEligible;
    }
    if (enabledRules.isEmpty) {
      return QualityGateEligibilityStatus.ineligible;
    }
    if (reasons.isNotEmpty) {
      return QualityGateEligibilityStatus.partiallyEligible;
    }
    return QualityGateEligibilityStatus.eligible;
  }
}
