import 'quality_gate_enums.dart';
import 'quality_gate_governance.dart';
import 'quality_gate_rule_value.dart';

/// Declarative quality gate rule.
class QualityGateRule {
  const QualityGateRule({
    required this.ruleId,
    required this.name,
    required this.description,
    required this.target,
    required this.operator,
    required this.requirement,
    required this.severity,
    required this.missingDataPolicy,
    required this.incompatibleDataPolicy,
    required this.evidencePolicy,
    required this.explanationTemplateId,
    required this.order,
    this.selector = const QualityGateRuleSelector(),
    this.expectedValue,
    this.tags = const [],
    this.enabled = true,
    this.metadata = const {},
  });

  final String ruleId;
  final String name;
  final String description;
  final QualityGateRuleTarget target;
  final QualityGateRuleSelector selector;
  final QualityGateRuleOperator operator;
  final QualityGateRuleValue? expectedValue;
  final QualityGateRuleRequirement requirement;
  final QualityGateRuleSeverity severity;
  final QualityGateMissingDataPolicy missingDataPolicy;
  final QualityGateIncompatibleDataPolicy incompatibleDataPolicy;
  final QualityGateEvidencePolicy evidencePolicy;
  final String explanationTemplateId;
  final List<String> tags;
  final bool enabled;
  final int order;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'ruleId': ruleId,
        'name': name,
        'description': description,
        'target': target.wireName,
        'selector': selector.toJson(),
        'operator': operator.wireName,
        if (expectedValue != null) 'expectedValue': expectedValue!.toJson(),
        'requirement': requirement.wireName,
        'severity': severity.wireName,
        'missingDataPolicy': missingDataPolicy.wireName,
        'incompatibleDataPolicy': incompatibleDataPolicy.wireName,
        'evidencePolicy': evidencePolicy.toJson(),
        'explanationTemplateId': explanationTemplateId,
        'tags': tags,
        'enabled': enabled,
        'order': order,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory QualityGateRule.fromJson(Map<String, dynamic> json) {
    return QualityGateRule(
      ruleId: json['ruleId'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      target: QualityGateRuleTargetX.fromWireName(json['target'] as String),
      selector: QualityGateRuleSelector.fromJson(
        json['selector'] as Map<String, dynamic>? ?? {},
      ),
      operator:
          QualityGateRuleOperatorX.fromWireName(json['operator'] as String),
      expectedValue: json['expectedValue'] == null
          ? null
          : QualityGateRuleValue.fromJson(
              json['expectedValue'] as Map<String, dynamic>,
            ),
      requirement: QualityGateRuleRequirementX.fromWireName(
        json['requirement'] as String,
      ),
      severity: QualityGateRuleSeverityX.fromWireName(
        json['severity'] as String,
      ),
      missingDataPolicy: QualityGateMissingDataPolicyX.fromWireName(
        json['missingDataPolicy'] as String,
      ),
      incompatibleDataPolicy: QualityGateIncompatibleDataPolicyX.fromWireName(
        json['incompatibleDataPolicy'] as String,
      ),
      evidencePolicy: QualityGateEvidencePolicy.fromJson(
        json['evidencePolicy'] as Map<String, dynamic>,
      ),
      explanationTemplateId: json['explanationTemplateId'] as String,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      enabled: json['enabled'] as bool? ?? true,
      order: json['order'] as int,
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

/// Logical grouping of rules with aggregation semantics.
class QualityGateRuleSet {
  const QualityGateRuleSet({
    required this.ruleSetId,
    required this.name,
    required this.description,
    required this.rules,
    required this.aggregationMode,
    required this.required,
    required this.severity,
    required this.order,
    this.minimumPassCount,
    this.minimumPassPercentage,
    this.tags = const [],
  });

  final String ruleSetId;
  final String name;
  final String description;
  final List<QualityGateRule> rules;
  final QualityGateRuleSetAggregationMode aggregationMode;
  final int? minimumPassCount;
  final double? minimumPassPercentage;
  final bool required;
  final QualityGateRuleSeverity severity;
  final int order;
  final List<String> tags;

  Map<String, dynamic> toJson() => {
        'ruleSetId': ruleSetId,
        'name': name,
        'description': description,
        'rules': rules.map((r) => r.toJson()).toList(),
        'aggregationMode': aggregationMode.wireName,
        if (minimumPassCount != null) 'minimumPassCount': minimumPassCount,
        if (minimumPassPercentage != null)
          'minimumPassPercentage': minimumPassPercentage,
        'required': required,
        'severity': severity.wireName,
        'order': order,
        'tags': tags,
      };

  factory QualityGateRuleSet.fromJson(Map<String, dynamic> json) {
    return QualityGateRuleSet(
      ruleSetId: json['ruleSetId'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      rules: (json['rules'] as List<dynamic>)
          .map((e) => QualityGateRule.fromJson(e as Map<String, dynamic>))
          .toList(),
      aggregationMode: QualityGateRuleSetAggregationModeX.fromWireName(
        json['aggregationMode'] as String,
      ),
      minimumPassCount: json['minimumPassCount'] as int?,
      minimumPassPercentage:
          (json['minimumPassPercentage'] as num?)?.toDouble(),
      required: json['required'] as bool,
      severity: QualityGateRuleSeverityX.fromWireName(
        json['severity'] as String,
      ),
      order: json['order'] as int,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Decision aggregation policy for a quality gate.
class QualityGateDecisionPolicy {
  const QualityGateDecisionPolicy({
    this.failOnBlockingFailure = true,
    this.failOnCriticalFailure = true,
    this.partialOnRequiredUnavailable = true,
    this.unavailableOnMissingRequiredSources = true,
    this.incompatibleOnSourceMismatch = true,
    this.minimumCoveragePercentage = 100,
    this.minimumEvaluatedRequiredRules = 1,
    this.warningsAffectDecision = false,
    this.optionalFailuresAffectDecision = false,
    this.informationalRulesAffectDecision = false,
    this.ruleSetFailureMode = 'blocking',
  });

  final bool failOnBlockingFailure;
  final bool failOnCriticalFailure;
  final bool partialOnRequiredUnavailable;
  final bool unavailableOnMissingRequiredSources;
  final bool incompatibleOnSourceMismatch;
  final double minimumCoveragePercentage;
  final int minimumEvaluatedRequiredRules;
  final bool warningsAffectDecision;
  final bool optionalFailuresAffectDecision;
  final bool informationalRulesAffectDecision;
  final String ruleSetFailureMode;

  Map<String, dynamic> toJson() => {
        'failOnBlockingFailure': failOnBlockingFailure,
        'failOnCriticalFailure': failOnCriticalFailure,
        'partialOnRequiredUnavailable': partialOnRequiredUnavailable,
        'unavailableOnMissingRequiredSources':
            unavailableOnMissingRequiredSources,
        'incompatibleOnSourceMismatch': incompatibleOnSourceMismatch,
        'minimumCoveragePercentage': minimumCoveragePercentage,
        'minimumEvaluatedRequiredRules': minimumEvaluatedRequiredRules,
        'warningsAffectDecision': warningsAffectDecision,
        'optionalFailuresAffectDecision': optionalFailuresAffectDecision,
        'informationalRulesAffectDecision': informationalRulesAffectDecision,
        'ruleSetFailureMode': ruleSetFailureMode,
      };

  factory QualityGateDecisionPolicy.fromJson(Map<String, dynamic> json) {
    return QualityGateDecisionPolicy(
      failOnBlockingFailure: json['failOnBlockingFailure'] as bool? ?? true,
      failOnCriticalFailure: json['failOnCriticalFailure'] as bool? ?? true,
      partialOnRequiredUnavailable:
          json['partialOnRequiredUnavailable'] as bool? ?? true,
      unavailableOnMissingRequiredSources:
          json['unavailableOnMissingRequiredSources'] as bool? ?? true,
      incompatibleOnSourceMismatch:
          json['incompatibleOnSourceMismatch'] as bool? ?? true,
      minimumCoveragePercentage:
          (json['minimumCoveragePercentage'] as num?)?.toDouble() ?? 100,
      minimumEvaluatedRequiredRules:
          json['minimumEvaluatedRequiredRules'] as int? ?? 1,
      warningsAffectDecision: json['warningsAffectDecision'] as bool? ?? false,
      optionalFailuresAffectDecision:
          json['optionalFailuresAffectDecision'] as bool? ?? false,
      informationalRulesAffectDecision:
          json['informationalRulesAffectDecision'] as bool? ?? false,
      ruleSetFailureMode: json['ruleSetFailureMode'] as String? ?? 'blocking',
    );
  }
}

/// Complete declarative quality gate policy.
class QualityGatePolicy {
  const QualityGatePolicy({
    required this.metadata,
    required this.governance,
    required this.decisionPolicy,
    required this.ruleSets,
    this.requiredSourceTypes = const [
      QualityGateSourceType.metrics,
      QualityGateSourceType.guardian,
      QualityGateSourceType.score,
      QualityGateSourceType.mes,
    ],
  });

  static const int currentSchemaVersion =
      QualityGatePolicyMetadata.currentSchemaVersion;
  static const int currentCalculationVersion =
      QualityGatePolicyMetadata.currentCalculationVersion;
  static const int currentCanonicalizationVersion =
      QualityGatePolicyMetadata.currentCanonicalizationVersion;

  final QualityGatePolicyMetadata metadata;
  final QualityGateGovernance governance;
  final QualityGateDecisionPolicy decisionPolicy;
  final List<QualityGateRuleSet> ruleSets;
  final List<QualityGateSourceType> requiredSourceTypes;

  List<QualityGateRule> get allRules =>
      ruleSets.expand((set) => set.rules).toList();

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'governance': governance.toJson(),
        'decisionPolicy': decisionPolicy.toJson(),
        'ruleSets': ruleSets.map((s) => s.toJson()).toList(),
        'requiredSourceTypes':
            requiredSourceTypes.map((e) => e.wireName).toList(),
      };

  factory QualityGatePolicy.fromJson(Map<String, dynamic> json) {
    return QualityGatePolicy(
      metadata: QualityGatePolicyMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      governance: QualityGateGovernance.fromJson(
        json['governance'] as Map<String, dynamic>,
      ),
      decisionPolicy: QualityGateDecisionPolicy.fromJson(
        json['decisionPolicy'] as Map<String, dynamic>,
      ),
      ruleSets: (json['ruleSets'] as List<dynamic>)
          .map((e) => QualityGateRuleSet.fromJson(e as Map<String, dynamic>))
          .toList(),
      requiredSourceTypes: (json['requiredSourceTypes'] as List<dynamic>? ?? [])
          .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
          .toList(),
    );
  }

  Map<String, dynamic> toComparableJson() {
    final json = toJson();
    final meta = Map<String, dynamic>.from(json['metadata'] as Map);
    meta.remove('createdAt');
    meta.remove('policyFingerprint');
    json['metadata'] = meta;
    final sets = (json['ruleSets'] as List<dynamic>)
      ..sort(
        (a, b) => (a as Map)['ruleSetId']
            .toString()
            .compareTo((b as Map)['ruleSetId'].toString()),
      );
    json['ruleSets'] = sets;
    return json;
  }
}
