/// Base class for typed collection rule expected/observed values.
abstract class ReleaseEvidenceRuleValue {
  const ReleaseEvidenceRuleValue();

  String get valueKind;
  Object? get rawValue;
  Map<String, dynamic> toJson();

  static ReleaseEvidenceRuleValue fromJson(Map<String, dynamic> json) {
    switch (json['valueKind'] as String) {
      case 'boolean':
        return ReleaseEvidenceBooleanValue.fromJson(json);
      case 'integer':
        return ReleaseEvidenceIntegerValue.fromJson(json);
      case 'decimal':
        return ReleaseEvidenceDecimalValue.fromJson(json);
      case 'percentage':
        return ReleaseEvidencePercentageValue.fromJson(json);
      case 'duration':
        return ReleaseEvidenceDurationValue.fromJson(json);
      case 'string':
        return ReleaseEvidenceStringValue.fromJson(json);
      case 'set':
        return ReleaseEvidenceSetValue.fromJson(json);
      default:
        throw FormatException(
          'Unknown ReleaseEvidenceRuleValue kind: ${json['valueKind']}',
        );
    }
  }
}

class ReleaseEvidenceBooleanValue extends ReleaseEvidenceRuleValue {
  const ReleaseEvidenceBooleanValue(this.value);

  final bool value;

  @override
  String get valueKind => 'boolean';

  @override
  Object? get rawValue => value;

  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};

  factory ReleaseEvidenceBooleanValue.fromJson(Map<String, dynamic> json) =>
      ReleaseEvidenceBooleanValue(json['value'] as bool);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceBooleanValue && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

class ReleaseEvidenceIntegerValue extends ReleaseEvidenceRuleValue {
  const ReleaseEvidenceIntegerValue(this.value);

  final int value;

  @override
  String get valueKind => 'integer';

  @override
  Object? get rawValue => value;

  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};

  factory ReleaseEvidenceIntegerValue.fromJson(Map<String, dynamic> json) =>
      ReleaseEvidenceIntegerValue(json['value'] as int);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceIntegerValue && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

class ReleaseEvidenceDecimalValue extends ReleaseEvidenceRuleValue {
  const ReleaseEvidenceDecimalValue(this.value);

  final double value;

  @override
  String get valueKind => 'decimal';

  @override
  Object? get rawValue => value;

  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};

  factory ReleaseEvidenceDecimalValue.fromJson(Map<String, dynamic> json) {
    final v = (json['value'] as num).toDouble();
    if (v.isNaN || v.isInfinite) {
      throw FormatException('Non-finite decimal value');
    }
    return ReleaseEvidenceDecimalValue(v == -0.0 ? 0.0 : v);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceDecimalValue && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

class ReleaseEvidencePercentageValue extends ReleaseEvidenceRuleValue {
  const ReleaseEvidencePercentageValue(this.value);

  final double value;

  @override
  String get valueKind => 'percentage';

  @override
  Object? get rawValue => value;

  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};

  factory ReleaseEvidencePercentageValue.fromJson(Map<String, dynamic> json) {
    final v = (json['value'] as num).toDouble();
    if (v.isNaN || v.isInfinite || v < 0 || v > 100) {
      throw FormatException('Invalid percentage value: $v');
    }
    return ReleaseEvidencePercentageValue(v == -0.0 ? 0.0 : v);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidencePercentageValue && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

class ReleaseEvidenceDurationValue extends ReleaseEvidenceRuleValue {
  const ReleaseEvidenceDurationValue(this.iso8601Duration);

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

  factory ReleaseEvidenceDurationValue.fromJson(Map<String, dynamic> json) =>
      ReleaseEvidenceDurationValue(json['iso8601Duration'] as String);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceDurationValue &&
          iso8601Duration == other.iso8601Duration;

  @override
  int get hashCode => iso8601Duration.hashCode;
}

class ReleaseEvidenceStringValue extends ReleaseEvidenceRuleValue {
  const ReleaseEvidenceStringValue(this.value);

  final String value;

  @override
  String get valueKind => 'string';

  @override
  Object? get rawValue => value;

  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'value': value};

  factory ReleaseEvidenceStringValue.fromJson(Map<String, dynamic> json) =>
      ReleaseEvidenceStringValue(json['value'] as String);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceStringValue && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

class ReleaseEvidenceSetValue extends ReleaseEvidenceRuleValue {
  ReleaseEvidenceSetValue(List<String> values)
      : values = List.unmodifiable(List<String>.from(values)..sort());

  final List<String> values;

  @override
  String get valueKind => 'set';

  @override
  Object? get rawValue => values;

  @override
  Map<String, dynamic> toJson() => {'valueKind': valueKind, 'values': values};

  factory ReleaseEvidenceSetValue.fromJson(Map<String, dynamic> json) {
    final values = (json['values'] as List<dynamic>)
        .map((e) => e.toString())
        .toList()
      ..sort();
    return ReleaseEvidenceSetValue(values);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceSetValue && _listEquals(values, other.values);

  @override
  int get hashCode => Object.hashAll(values);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
