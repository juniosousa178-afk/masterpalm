import 'quality_gate_enums.dart';

/// Base class for typed rule expected/actual values.
abstract class QualityGateRuleValue {
  const QualityGateRuleValue();

  String get valueKind;

  Object? get rawValue;

  Map<String, dynamic> toJson();

  static QualityGateRuleValue fromJson(Map<String, dynamic> json) {
    final kind = json['valueKind'] as String;
    switch (kind) {
      case 'boolean':
        return QualityGateBooleanValue.fromJson(json);
      case 'integer':
        return QualityGateIntegerValue.fromJson(json);
      case 'decimal':
        return QualityGateDecimalValue.fromJson(json);
      case 'string':
        return QualityGateStringValue.fromJson(json);
      case 'enum':
        return QualityGateEnumValue.fromJson(json);
      case 'percentage':
        return QualityGatePercentageValue.fromJson(json);
      case 'range':
        return QualityGateRangeValue.fromJson(json);
      case 'set':
        return QualityGateSetValue.fromJson(json);
      case 'artifactReference':
        return QualityGateArtifactReferenceValue.fromJson(json);
      case 'version':
        return QualityGateVersionValue.fromJson(json);
      default:
        throw FormatException('Unknown QualityGateRuleValue kind: $kind');
    }
  }
}

class QualityGateBooleanValue extends QualityGateRuleValue {
  const QualityGateBooleanValue(this.value);

  final bool value;

  @override
  String get valueKind => 'boolean';

  @override
  Object? get rawValue => value;

  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};

  factory QualityGateBooleanValue.fromJson(Map<String, dynamic> json) {
    return QualityGateBooleanValue(json['value'] as bool);
  }
}

class QualityGateIntegerValue extends QualityGateRuleValue {
  const QualityGateIntegerValue(this.value);

  final int value;

  @override
  String get valueKind => 'integer';

  @override
  Object? get rawValue => value;

  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};

  factory QualityGateIntegerValue.fromJson(Map<String, dynamic> json) {
    return QualityGateIntegerValue(json['value'] as int);
  }
}

class QualityGateDecimalValue extends QualityGateRuleValue {
  const QualityGateDecimalValue(this.value);

  final double value;

  @override
  String get valueKind => 'decimal';

  @override
  Object? get rawValue => value;

  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};

  factory QualityGateDecimalValue.fromJson(Map<String, dynamic> json) {
    final v = (json['value'] as num).toDouble();
    if (v.isNaN || v.isInfinite) {
      throw FormatException('Non-finite decimal value');
    }
    return QualityGateDecimalValue(v == -0.0 ? 0.0 : v);
  }
}

class QualityGateStringValue extends QualityGateRuleValue {
  const QualityGateStringValue(this.value);

  final String value;

  @override
  String get valueKind => 'string';

  @override
  Object? get rawValue => value;

  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};

  factory QualityGateStringValue.fromJson(Map<String, dynamic> json) {
    return QualityGateStringValue(json['value'] as String);
  }
}

class QualityGateEnumValue extends QualityGateRuleValue {
  const QualityGateEnumValue({required this.domain, required this.value});

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

  factory QualityGateEnumValue.fromJson(Map<String, dynamic> json) {
    return QualityGateEnumValue(
      domain: json['domain'] as String,
      value: json['value'] as String,
    );
  }
}

class QualityGatePercentageValue extends QualityGateRuleValue {
  const QualityGatePercentageValue(this.value);

  final double value;

  @override
  String get valueKind => 'percentage';

  @override
  Object? get rawValue => value;

  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};

  factory QualityGatePercentageValue.fromJson(Map<String, dynamic> json) {
    final v = (json['value'] as num).toDouble();
    if (v.isNaN || v.isInfinite || v < 0 || v > 100) {
      throw FormatException('Invalid percentage value: $v');
    }
    return QualityGatePercentageValue(v == -0.0 ? 0.0 : v);
  }
}

class QualityGateRangeValue extends QualityGateRuleValue {
  const QualityGateRangeValue({required this.lower, required this.upper});

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

  factory QualityGateRangeValue.fromJson(Map<String, dynamic> json) {
    final lower = (json['lower'] as num).toDouble();
    final upper = (json['upper'] as num).toDouble();
    if (lower > upper) {
      throw FormatException('Range lower must be <= upper');
    }
    return QualityGateRangeValue(lower: lower, upper: upper);
  }
}

class QualityGateSetValue extends QualityGateRuleValue {
  const QualityGateSetValue(this.values);

  final List<String> values;

  @override
  String get valueKind => 'set';

  @override
  Object? get rawValue => values;

  @override
  Map<String, dynamic> toJson() => {
        'valueKind': valueKind,
        'values': List<String>.from(values)..sort(),
      };

  factory QualityGateSetValue.fromJson(Map<String, dynamic> json) {
    final values = (json['values'] as List<dynamic>)
        .map((e) => e.toString())
        .toList()
      ..sort();
    return QualityGateSetValue(values);
  }
}

class QualityGateArtifactReferenceValue extends QualityGateRuleValue {
  const QualityGateArtifactReferenceValue({
    required this.artifactType,
    required this.artifactId,
    this.fingerprint,
  });

  final String artifactType;
  final String artifactId;
  final String? fingerprint;

  @override
  String get valueKind => 'artifactReference';

  @override
  Object? get rawValue => artifactId;

  @override
  Map<String, dynamic> toJson() => {
        'valueKind': valueKind,
        'artifactType': artifactType,
        'artifactId': artifactId,
        if (fingerprint != null) 'fingerprint': fingerprint,
      };

  factory QualityGateArtifactReferenceValue.fromJson(
      Map<String, dynamic> json) {
    return QualityGateArtifactReferenceValue(
      artifactType: json['artifactType'] as String,
      artifactId: json['artifactId'] as String,
      fingerprint: json['fingerprint'] as String?,
    );
  }
}

class QualityGateVersionValue extends QualityGateRuleValue {
  const QualityGateVersionValue({
    required this.major,
    this.minor = 0,
    this.patch = 0,
  });

  final int major;
  final int minor;
  final int patch;

  @override
  String get valueKind => 'version';

  @override
  Object? get rawValue => '$major.$minor.$patch';

  @override
  Map<String, dynamic> toJson() => {
        'valueKind': valueKind,
        'major': major,
        'minor': minor,
        'patch': patch,
      };

  factory QualityGateVersionValue.fromJson(Map<String, dynamic> json) {
    return QualityGateVersionValue(
      major: json['major'] as int,
      minor: json['minor'] as int? ?? 0,
      patch: json['patch'] as int? ?? 0,
    );
  }
}

/// Typed selector for resolving rule targets within artifacts.
class QualityGateRuleSelector {
  const QualityGateRuleSelector({
    this.metricId,
    this.dimensionId,
    this.guardianRuleId,
    this.componentId,
    this.artifactType,
    this.policyId,
    this.operationId,
  });

  final String? metricId;
  final String? dimensionId;
  final String? guardianRuleId;
  final String? componentId;
  final String? artifactType;
  final String? policyId;
  final String? operationId;

  bool get isEmpty =>
      metricId == null &&
      dimensionId == null &&
      guardianRuleId == null &&
      componentId == null &&
      artifactType == null &&
      policyId == null &&
      operationId == null;

  Map<String, dynamic> toJson() => {
        if (metricId != null) 'metricId': metricId,
        if (dimensionId != null) 'dimensionId': dimensionId,
        if (guardianRuleId != null) 'guardianRuleId': guardianRuleId,
        if (componentId != null) 'componentId': componentId,
        if (artifactType != null) 'artifactType': artifactType,
        if (policyId != null) 'policyId': policyId,
        if (operationId != null) 'operationId': operationId,
      };

  factory QualityGateRuleSelector.fromJson(Map<String, dynamic> json) {
    return QualityGateRuleSelector(
      metricId: json['metricId'] as String?,
      dimensionId: json['dimensionId'] as String?,
      guardianRuleId: json['guardianRuleId'] as String?,
      componentId: json['componentId'] as String?,
      artifactType: json['artifactType'] as String?,
      policyId: json['policyId'] as String?,
      operationId: json['operationId'] as String?,
    );
  }
}

/// Evidence collection policy for a rule.
class QualityGateEvidencePolicy {
  const QualityGateEvidencePolicy({
    this.requireSourceReference = true,
    this.requireArtifactId = true,
    this.requireFingerprint = false,
    this.requirePolicyReference = false,
    this.requireActualValue = true,
    this.requireExpectedValue = true,
    this.requireExplanation = true,
    this.minimumEvidenceCount = 1,
    this.acceptedEvidenceTypes = const [
      QualityGateEvidenceType.authoritative,
      QualityGateEvidenceType.derived,
      QualityGateEvidenceType.contextual,
      QualityGateEvidenceType.operational,
      QualityGateEvidenceType.historical,
    ],
    this.acceptedSourceTypes = const [],
  });

  final bool requireSourceReference;
  final bool requireArtifactId;
  final bool requireFingerprint;
  final bool requirePolicyReference;
  final bool requireActualValue;
  final bool requireExpectedValue;
  final bool requireExplanation;
  final int minimumEvidenceCount;
  final List<QualityGateEvidenceType> acceptedEvidenceTypes;
  final List<QualityGateSourceType> acceptedSourceTypes;

  Map<String, dynamic> toJson() => {
        'requireSourceReference': requireSourceReference,
        'requireArtifactId': requireArtifactId,
        'requireFingerprint': requireFingerprint,
        'requirePolicyReference': requirePolicyReference,
        'requireActualValue': requireActualValue,
        'requireExpectedValue': requireExpectedValue,
        'requireExplanation': requireExplanation,
        'minimumEvidenceCount': minimumEvidenceCount,
        'acceptedEvidenceTypes':
            acceptedEvidenceTypes.map((e) => e.wireName).toList(),
        'acceptedSourceTypes':
            acceptedSourceTypes.map((e) => e.wireName).toList(),
      };

  factory QualityGateEvidencePolicy.fromJson(Map<String, dynamic> json) {
    return QualityGateEvidencePolicy(
      requireSourceReference: json['requireSourceReference'] as bool? ?? true,
      requireArtifactId: json['requireArtifactId'] as bool? ?? true,
      requireFingerprint: json['requireFingerprint'] as bool? ?? false,
      requirePolicyReference: json['requirePolicyReference'] as bool? ?? false,
      requireActualValue: json['requireActualValue'] as bool? ?? true,
      requireExpectedValue: json['requireExpectedValue'] as bool? ?? true,
      requireExplanation: json['requireExplanation'] as bool? ?? true,
      minimumEvidenceCount: json['minimumEvidenceCount'] as int? ?? 1,
      acceptedEvidenceTypes:
          (json['acceptedEvidenceTypes'] as List<dynamic>? ?? [])
              .map((e) => QualityGateEvidenceTypeX.fromWireName(e as String))
              .toList(),
      acceptedSourceTypes: (json['acceptedSourceTypes'] as List<dynamic>? ?? [])
          .map((e) => QualityGateSourceTypeX.fromWireName(e as String))
          .toList(),
    );
  }
}
