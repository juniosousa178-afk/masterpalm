import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';

import 'release_evidence_enums.dart';
import 'release_evidence_rule_value.dart';

/// Selector narrowing a collection rule to a specific evidence context.
class ReleaseEvidenceCollectionRuleSelector {
  const ReleaseEvidenceCollectionRuleSelector({
    this.evidenceType,
    this.artifactType,
    this.attestationType,
    this.sourceType,
    this.environment,
    this.releaseType,
    this.metadata = const {},
  });

  final ReleaseEvidenceType? evidenceType;
  final ReleaseEvidenceArtifactType? artifactType;
  final ReleaseAttestationType? attestationType;
  final ReleaseEvidenceType? sourceType;
  final ReleaseEnvironment? environment;
  final ReleaseType? releaseType;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        if (evidenceType != null) 'evidenceType': evidenceType!.wireName,
        if (artifactType != null) 'artifactType': artifactType!.wireName,
        if (attestationType != null)
          'attestationType': attestationType!.wireName,
        if (sourceType != null) 'sourceType': sourceType!.wireName,
        if (environment != null) 'environment': environment!.wireName,
        if (releaseType != null) 'releaseType': releaseType!.wireName,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseEvidenceCollectionRuleSelector.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseEvidenceCollectionRuleSelector(
      evidenceType: json['evidenceType'] == null
          ? null
          : ReleaseEvidenceTypeX.fromWireName(json['evidenceType'] as String),
      artifactType: json['artifactType'] == null
          ? null
          : ReleaseEvidenceArtifactTypeX.fromWireName(
              json['artifactType'] as String,
            ),
      attestationType: json['attestationType'] == null
          ? null
          : ReleaseAttestationTypeX.fromWireName(
              json['attestationType'] as String,
            ),
      sourceType: json['sourceType'] == null
          ? null
          : ReleaseEvidenceTypeX.fromWireName(json['sourceType'] as String),
      environment: json['environment'] == null
          ? null
          : ReleaseEnvironmentX.fromWireName(json['environment'] as String),
      releaseType: json['releaseType'] == null
          ? null
          : ReleaseTypeX.fromWireName(json['releaseType'] as String),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceCollectionRuleSelector &&
          runtimeType == other.runtimeType &&
          evidenceType == other.evidenceType &&
          artifactType == other.artifactType &&
          attestationType == other.attestationType &&
          sourceType == other.sourceType &&
          environment == other.environment &&
          releaseType == other.releaseType &&
          _mapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        evidenceType,
        artifactType,
        attestationType,
        sourceType,
        environment,
        releaseType,
        Object.hashAll(metadata.entries),
      );
}

/// Declarative release evidence collection rule.
class ReleaseEvidenceCollectionRule {
  const ReleaseEvidenceCollectionRule({
    required this.ruleId,
    required this.ruleSetId,
    required this.name,
    required this.description,
    required this.target,
    required this.operator,
    required this.severity,
    required this.requirement,
    required this.missingDataPolicy,
    required this.incompatibleDataPolicy,
    required this.evidenceRole,
    required this.rationale,
    required this.order,
    this.selector = const ReleaseEvidenceCollectionRuleSelector(),
    this.expectedValue,
    this.freshnessRequirement,
    this.attestationRequirement,
    this.enabled = true,
    this.tags = const [],
  });

  final String ruleId;
  final String ruleSetId;
  final String name;
  final String description;
  final ReleaseEvidenceCollectionRuleTarget target;
  final ReleaseEvidenceCollectionRuleSelector selector;
  final ReleaseEvidenceCollectionRuleOperator operator;
  final ReleaseEvidenceRuleValue? expectedValue;
  final ReleaseEvidenceCollectionRuleSeverity severity;
  final ReleaseEvidenceCollectionRuleRequirement requirement;
  final ReleaseEvidenceMissingDataPolicy missingDataPolicy;
  final ReleaseEvidenceIncompatibleDataPolicy incompatibleDataPolicy;
  final ReleaseEvidenceRole evidenceRole;
  final ReleaseEvidenceDurationValue? freshnessRequirement;
  final String? attestationRequirement;
  final String rationale;
  final bool enabled;
  final int order;
  final List<String> tags;

  Map<String, dynamic> toJson() => {
        'ruleId': ruleId,
        'ruleSetId': ruleSetId,
        'name': name,
        'description': description,
        'target': target.wireName,
        'selector': selector.toJson(),
        'operator': operator.wireName,
        if (expectedValue != null) 'expectedValue': expectedValue!.toJson(),
        'severity': severity.wireName,
        'requirement': requirement.wireName,
        'missingDataPolicy': missingDataPolicy.wireName,
        'incompatibleDataPolicy': incompatibleDataPolicy.wireName,
        'evidenceRole': evidenceRole.wireName,
        if (freshnessRequirement != null)
          'freshnessRequirement': freshnessRequirement!.toJson(),
        if (attestationRequirement != null)
          'attestationRequirement': attestationRequirement,
        'rationale': rationale,
        'enabled': enabled,
        'order': order,
        if (tags.isNotEmpty) 'tags': tags,
      };

  factory ReleaseEvidenceCollectionRule.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceCollectionRule(
      ruleId: json['ruleId'] as String,
      ruleSetId: json['ruleSetId'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      target: ReleaseEvidenceCollectionRuleTargetX.fromWireName(
        json['target'] as String,
      ),
      selector: ReleaseEvidenceCollectionRuleSelector.fromJson(
        json['selector'] as Map<String, dynamic>? ?? {},
      ),
      operator: ReleaseEvidenceCollectionRuleOperatorX.fromWireName(
        json['operator'] as String,
      ),
      expectedValue: json['expectedValue'] == null
          ? null
          : ReleaseEvidenceRuleValue.fromJson(
              json['expectedValue'] as Map<String, dynamic>,
            ),
      severity: ReleaseEvidenceCollectionRuleSeverityX.fromWireName(
        json['severity'] as String,
      ),
      requirement: ReleaseEvidenceCollectionRuleRequirementX.fromWireName(
        json['requirement'] as String,
      ),
      missingDataPolicy: ReleaseEvidenceMissingDataPolicyX.fromWireName(
        json['missingDataPolicy'] as String,
      ),
      incompatibleDataPolicy:
          ReleaseEvidenceIncompatibleDataPolicyX.fromWireName(
        json['incompatibleDataPolicy'] as String,
      ),
      evidenceRole: ReleaseEvidenceRoleX.fromWireName(
        json['evidenceRole'] as String,
      ),
      freshnessRequirement: json['freshnessRequirement'] == null
          ? null
          : ReleaseEvidenceDurationValue.fromJson(
              json['freshnessRequirement'] as Map<String, dynamic>,
            ),
      attestationRequirement: json['attestationRequirement'] as String?,
      rationale: json['rationale'] as String,
      enabled: json['enabled'] as bool? ?? true,
      order: json['order'] as int,
      tags: List.unmodifiable(
        (json['tags'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }
}

/// Logical grouping of release evidence collection rules.
class ReleaseEvidenceCollectionRuleSet {
  const ReleaseEvidenceCollectionRuleSet({
    required this.ruleSetId,
    required this.name,
    required this.description,
    required this.order,
    required this.enabled,
    required this.required,
    required this.severity,
    required this.aggregationMode,
    required this.ruleIds,
    required this.rationale,
    this.minimumPassCount,
    this.minimumPassPercentage,
    this.tags = const [],
  });

  final String ruleSetId;
  final String name;
  final String description;
  final int order;
  final bool enabled;
  final bool required;
  final ReleaseEvidenceCollectionRuleSeverity severity;
  final ReleaseEvidenceRuleSetAggregationMode aggregationMode;
  final int? minimumPassCount;
  final double? minimumPassPercentage;
  final List<String> ruleIds;
  final String rationale;
  final List<String> tags;

  Map<String, dynamic> toJson() => {
        'ruleSetId': ruleSetId,
        'name': name,
        'description': description,
        'order': order,
        'enabled': enabled,
        'required': required,
        'severity': severity.wireName,
        'aggregationMode': aggregationMode.wireName,
        if (minimumPassCount != null) 'minimumPassCount': minimumPassCount,
        if (minimumPassPercentage != null)
          'minimumPassPercentage': minimumPassPercentage,
        'ruleIds': ruleIds,
        'rationale': rationale,
        if (tags.isNotEmpty) 'tags': tags,
      };

  factory ReleaseEvidenceCollectionRuleSet.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceCollectionRuleSet(
      ruleSetId: json['ruleSetId'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      order: json['order'] as int,
      enabled: json['enabled'] as bool? ?? true,
      required: json['required'] as bool,
      severity: ReleaseEvidenceCollectionRuleSeverityX.fromWireName(
        json['severity'] as String,
      ),
      aggregationMode: ReleaseEvidenceRuleSetAggregationModeX.fromWireName(
        json['aggregationMode'] as String,
      ),
      minimumPassCount: json['minimumPassCount'] as int?,
      minimumPassPercentage:
          (json['minimumPassPercentage'] as num?)?.toDouble(),
      ruleIds: List.unmodifiable(
        (json['ruleIds'] as List<dynamic>).map((e) => e.toString()).toList(),
      ),
      rationale: json['rationale'] as String,
      tags: List.unmodifiable(
        (json['tags'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
