import 'release_governance_enums.dart';

/// Base class for typed rule expected/actual values.
abstract class ReleaseGovernanceRuleValue {
  const ReleaseGovernanceRuleValue();

  String get valueKind;
  Object? get rawValue;
  Map<String, dynamic> toJson();

  static ReleaseGovernanceRuleValue fromJson(Map<String, dynamic> json) {
    switch (json['valueKind'] as String) {
      case 'boolean':
        return ReleaseGovernanceBooleanValue.fromJson(json);
      case 'integer':
        return ReleaseGovernanceIntegerValue.fromJson(json);
      case 'decimal':
        return ReleaseGovernanceDecimalValue.fromJson(json);
      case 'string':
        return ReleaseGovernanceStringValue.fromJson(json);
      case 'enum':
        return ReleaseGovernanceEnumValue.fromJson(json);
      case 'percentage':
        return ReleaseGovernancePercentageValue.fromJson(json);
      case 'dateTime':
        return ReleaseGovernanceDateTimeValue.fromJson(json);
      case 'duration':
        return ReleaseGovernanceDurationValue.fromJson(json);
      case 'range':
        return ReleaseGovernanceRangeValue.fromJson(json);
      case 'set':
        return ReleaseGovernanceSetValue.fromJson(json);
      case 'artifactReference':
        return ReleaseGovernanceArtifactReferenceValue.fromJson(json);
      case 'version':
        return ReleaseGovernanceVersionValue.fromJson(json);
      case 'decision':
        return ReleaseGovernanceDecisionValue.fromJson(json);
      default:
        throw FormatException(
          'Unknown ReleaseGovernanceRuleValue kind: ${json['valueKind']}',
        );
    }
  }
}

class ReleaseGovernanceBooleanValue extends ReleaseGovernanceRuleValue {
  const ReleaseGovernanceBooleanValue(this.value);
  final bool value;
  @override
  String get valueKind => 'boolean';
  @override
  Object? get rawValue => value;
  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};
  factory ReleaseGovernanceBooleanValue.fromJson(Map<String, dynamic> json) =>
      ReleaseGovernanceBooleanValue(json['value'] as bool);
}

class ReleaseGovernanceIntegerValue extends ReleaseGovernanceRuleValue {
  const ReleaseGovernanceIntegerValue(this.value);
  final int value;
  @override
  String get valueKind => 'integer';
  @override
  Object? get rawValue => value;
  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};
  factory ReleaseGovernanceIntegerValue.fromJson(Map<String, dynamic> json) =>
      ReleaseGovernanceIntegerValue(json['value'] as int);
}

class ReleaseGovernanceDecimalValue extends ReleaseGovernanceRuleValue {
  const ReleaseGovernanceDecimalValue(this.value);
  final double value;
  @override
  String get valueKind => 'decimal';
  @override
  Object? get rawValue => value;
  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};
  factory ReleaseGovernanceDecimalValue.fromJson(Map<String, dynamic> json) {
    final v = (json['value'] as num).toDouble();
    if (v.isNaN || v.isInfinite) {
      throw FormatException('Non-finite decimal value');
    }
    return ReleaseGovernanceDecimalValue(v == -0.0 ? 0.0 : v);
  }
}

class ReleaseGovernanceStringValue extends ReleaseGovernanceRuleValue {
  const ReleaseGovernanceStringValue(this.value);
  final String value;
  @override
  String get valueKind => 'string';
  @override
  Object? get rawValue => value;
  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};
  factory ReleaseGovernanceStringValue.fromJson(Map<String, dynamic> json) =>
      ReleaseGovernanceStringValue(json['value'] as String);
}

class ReleaseGovernanceEnumValue extends ReleaseGovernanceRuleValue {
  const ReleaseGovernanceEnumValue({required this.domain, required this.value});
  final String domain;
  final String value;
  @override
  String get valueKind => 'enum';
  @override
  Object? get rawValue => value;
  @override
  Map<String, dynamic> toJson() => {
        'valueKind': valueKind,
        'domain': domain,
        'value': value,
      };
  factory ReleaseGovernanceEnumValue.fromJson(Map<String, dynamic> json) =>
      ReleaseGovernanceEnumValue(
        domain: json['domain'] as String,
        value: json['value'] as String,
      );
}

class ReleaseGovernancePercentageValue extends ReleaseGovernanceRuleValue {
  const ReleaseGovernancePercentageValue(this.value);
  final double value;
  @override
  String get valueKind => 'percentage';
  @override
  Object? get rawValue => value;
  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};
  factory ReleaseGovernancePercentageValue.fromJson(Map<String, dynamic> json) {
    final v = (json['value'] as num).toDouble();
    if (v.isNaN || v.isInfinite || v < 0 || v > 100) {
      throw FormatException('Invalid percentage value: $v');
    }
    return ReleaseGovernancePercentageValue(v == -0.0 ? 0.0 : v);
  }
}

class ReleaseGovernanceDateTimeValue extends ReleaseGovernanceRuleValue {
  const ReleaseGovernanceDateTimeValue(this.value);
  final String value;
  @override
  String get valueKind => 'dateTime';
  @override
  Object? get rawValue => value;
  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};
  factory ReleaseGovernanceDateTimeValue.fromJson(Map<String, dynamic> json) =>
      ReleaseGovernanceDateTimeValue(json['value'] as String);
}

class ReleaseGovernanceDurationValue extends ReleaseGovernanceRuleValue {
  const ReleaseGovernanceDurationValue(this.iso8601Duration);
  final String iso8601Duration;
  @override
  String get valueKind => 'duration';
  @override
  Object? get rawValue => iso8601Duration;
  @override
  Map<String, dynamic> toJson() => {
        'valueKind': valueKind,
        'iso8601Duration': iso8601Duration,
      };
  factory ReleaseGovernanceDurationValue.fromJson(Map<String, dynamic> json) =>
      ReleaseGovernanceDurationValue(json['iso8601Duration'] as String);
}

class ReleaseGovernanceRangeValue extends ReleaseGovernanceRuleValue {
  const ReleaseGovernanceRangeValue({required this.lower, required this.upper});
  final double lower;
  final double upper;
  @override
  String get valueKind => 'range';
  @override
  Object? get rawValue => {'lower': lower, 'upper': upper};
  @override
  Map<String, dynamic> toJson() => {
        'valueKind': valueKind,
        'lower': lower,
        'upper': upper,
      };
  factory ReleaseGovernanceRangeValue.fromJson(Map<String, dynamic> json) {
    final lower = (json['lower'] as num).toDouble();
    final upper = (json['upper'] as num).toDouble();
    if (lower.isNaN || lower.isInfinite || upper.isNaN || upper.isInfinite) {
      throw FormatException('Non-finite range value');
    }
    return ReleaseGovernanceRangeValue(lower: lower, upper: upper);
  }
}

class ReleaseGovernanceSetValue extends ReleaseGovernanceRuleValue {
  const ReleaseGovernanceSetValue(this.values);
  final List<String> values;
  @override
  String get valueKind => 'set';
  @override
  Object? get rawValue => values;
  @override
  Map<String, dynamic> toJson() {
    final sorted = List<String>.from(values)..sort();
    return {'valueKind': valueKind, 'values': sorted};
  }

  factory ReleaseGovernanceSetValue.fromJson(Map<String, dynamic> json) {
    final values = (json['values'] as List<dynamic>)
        .map((e) => e.toString())
        .toList()
      ..sort();
    return ReleaseGovernanceSetValue(values);
  }
}

class ReleaseGovernanceArtifactReferenceValue
    extends ReleaseGovernanceRuleValue {
  const ReleaseGovernanceArtifactReferenceValue({
    required this.artifactId,
    required this.artifactType,
    this.fingerprint,
  });
  final String artifactId;
  final String artifactType;
  final String? fingerprint;
  @override
  String get valueKind => 'artifactReference';
  @override
  Object? get rawValue => artifactId;
  @override
  Map<String, dynamic> toJson() => {
        'valueKind': valueKind,
        'artifactId': artifactId,
        'artifactType': artifactType,
        if (fingerprint != null) 'fingerprint': fingerprint,
      };
  factory ReleaseGovernanceArtifactReferenceValue.fromJson(
    Map<String, dynamic> json,
  ) =>
      ReleaseGovernanceArtifactReferenceValue(
        artifactId: json['artifactId'] as String,
        artifactType: json['artifactType'] as String,
        fingerprint: json['fingerprint'] as String?,
      );
}

class ReleaseGovernanceVersionValue extends ReleaseGovernanceRuleValue {
  const ReleaseGovernanceVersionValue(this.value);
  final String value;
  @override
  String get valueKind => 'version';
  @override
  Object? get rawValue => value;
  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};
  factory ReleaseGovernanceVersionValue.fromJson(Map<String, dynamic> json) =>
      ReleaseGovernanceVersionValue(json['value'] as String);
}

class ReleaseGovernanceDecisionValue extends ReleaseGovernanceRuleValue {
  const ReleaseGovernanceDecisionValue(this.decision);
  final ReleaseGovernanceDecision decision;
  @override
  String get valueKind => 'decision';
  @override
  Object? get rawValue => decision.wireName;
  @override
  Map<String, dynamic> toJson() => {
        'valueKind': valueKind,
        'decision': decision.wireName,
      };
  factory ReleaseGovernanceDecisionValue.fromJson(Map<String, dynamic> json) =>
      ReleaseGovernanceDecisionValue(
        ReleaseGovernanceDecisionX.fromWireName(json['decision'] as String),
      );
}

/// Optional selector for targets that require disambiguation.
class ReleaseGovernanceRuleSelector {
  const ReleaseGovernanceRuleSelector({
    this.qualityGateRuleId,
    this.approvalType,
    this.waiverId,
    this.ruleSetId,
    this.metadata = const {},
  });

  final String? qualityGateRuleId;
  final ReleaseApprovalType? approvalType;
  final String? waiverId;
  final String? ruleSetId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        if (qualityGateRuleId != null) 'qualityGateRuleId': qualityGateRuleId,
        if (approvalType != null) 'approvalType': approvalType!.wireName,
        if (waiverId != null) 'waiverId': waiverId,
        if (ruleSetId != null) 'ruleSetId': ruleSetId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseGovernanceRuleSelector.fromJson(Map<String, dynamic> json) {
    return ReleaseGovernanceRuleSelector(
      qualityGateRuleId: json['qualityGateRuleId'] as String?,
      approvalType: json['approvalType'] == null
          ? null
          : ReleaseApprovalTypeX.fromWireName(json['approvalType'] as String),
      waiverId: json['waiverId'] as String?,
      ruleSetId: json['ruleSetId'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}
