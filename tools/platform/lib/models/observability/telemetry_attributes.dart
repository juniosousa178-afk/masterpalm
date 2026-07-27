import 'telemetry_enums.dart';

/// Base class for typed telemetry attributes.
abstract class TelemetryAttribute {
  const TelemetryAttribute({
    required this.key,
    required this.classification,
    this.unit,
    this.redactionStatus = TelemetryRedactionStatus.none,
  });

  final String key;
  final TelemetryAttributeClassification classification;
  final String? unit;
  final TelemetryRedactionStatus redactionStatus;

  TelemetryAttributeType get attributeType;
  Object? get value;

  Map<String, dynamic> toJson();

  static TelemetryAttribute fromJson(Map<String, dynamic> json) {
    final type = TelemetryAttributeTypeX.fromWireName(
      json['attributeType'] as String,
    );
    switch (type) {
      case TelemetryAttributeType.string:
        return TelemetryStringAttribute.fromJson(json);
      case TelemetryAttributeType.integer:
        return TelemetryIntegerAttribute.fromJson(json);
      case TelemetryAttributeType.decimal:
        return TelemetryDecimalAttribute.fromJson(json);
      case TelemetryAttributeType.boolean:
        return TelemetryBooleanAttribute.fromJson(json);
      case TelemetryAttributeType.enumValue:
        return TelemetryEnumAttribute.fromJson(json);
      case TelemetryAttributeType.duration:
        return TelemetryDurationAttribute.fromJson(json);
      case TelemetryAttributeType.artifactReference:
        return TelemetryArtifactReferenceAttribute.fromJson(json);
      case TelemetryAttributeType.count:
        return TelemetryCountAttribute.fromJson(json);
    }
  }
}

class TelemetryStringAttribute extends TelemetryAttribute {
  const TelemetryStringAttribute({
    required super.key,
    required this.stringValue,
    super.classification = TelemetryAttributeClassification.public,
    super.unit,
    super.redactionStatus,
  }) : super();

  final String stringValue;

  @override
  TelemetryAttributeType get attributeType => TelemetryAttributeType.string;

  @override
  Object? get value => stringValue;

  @override
  Map<String, dynamic> toJson() => {
        'attributeType': attributeType.wireName,
        'key': key,
        'value': stringValue,
        'classification': classification.wireName,
        if (unit != null) 'unit': unit,
        'redactionStatus': redactionStatus.wireName,
      };

  factory TelemetryStringAttribute.fromJson(Map<String, dynamic> json) {
    return TelemetryStringAttribute(
      key: json['key'] as String,
      stringValue: json['value'] as String,
      classification: TelemetryAttributeClassificationX.fromWireName(
        json['classification'] as String? ?? 'public',
      ),
      unit: json['unit'] as String?,
      redactionStatus: TelemetryRedactionStatusX.fromWireName(
        json['redactionStatus'] as String? ?? 'none',
      ),
    );
  }
}

class TelemetryIntegerAttribute extends TelemetryAttribute {
  const TelemetryIntegerAttribute({
    required super.key,
    required this.intValue,
    super.classification = TelemetryAttributeClassification.public,
    super.unit,
    super.redactionStatus,
  }) : super();

  final int intValue;

  @override
  TelemetryAttributeType get attributeType => TelemetryAttributeType.integer;

  @override
  Object? get value => intValue;

  @override
  Map<String, dynamic> toJson() => {
        'attributeType': attributeType.wireName,
        'key': key,
        'value': intValue,
        'classification': classification.wireName,
        if (unit != null) 'unit': unit,
        'redactionStatus': redactionStatus.wireName,
      };

  factory TelemetryIntegerAttribute.fromJson(Map<String, dynamic> json) {
    return TelemetryIntegerAttribute(
      key: json['key'] as String,
      intValue: json['value'] as int,
      classification: TelemetryAttributeClassificationX.fromWireName(
        json['classification'] as String? ?? 'public',
      ),
      unit: json['unit'] as String?,
      redactionStatus: TelemetryRedactionStatusX.fromWireName(
        json['redactionStatus'] as String? ?? 'none',
      ),
    );
  }
}

class TelemetryDecimalAttribute extends TelemetryAttribute {
  const TelemetryDecimalAttribute({
    required super.key,
    required this.decimalValue,
    super.classification = TelemetryAttributeClassification.public,
    super.unit,
    super.redactionStatus,
  }) : super();

  final double decimalValue;

  @override
  TelemetryAttributeType get attributeType => TelemetryAttributeType.decimal;

  @override
  Object? get value => decimalValue;

  @override
  Map<String, dynamic> toJson() => {
        'attributeType': attributeType.wireName,
        'key': key,
        'value': decimalValue,
        'classification': classification.wireName,
        if (unit != null) 'unit': unit,
        'redactionStatus': redactionStatus.wireName,
      };

  factory TelemetryDecimalAttribute.fromJson(Map<String, dynamic> json) {
    return TelemetryDecimalAttribute(
      key: json['key'] as String,
      decimalValue: (json['value'] as num).toDouble(),
      classification: TelemetryAttributeClassificationX.fromWireName(
        json['classification'] as String? ?? 'public',
      ),
      unit: json['unit'] as String?,
      redactionStatus: TelemetryRedactionStatusX.fromWireName(
        json['redactionStatus'] as String? ?? 'none',
      ),
    );
  }
}

class TelemetryBooleanAttribute extends TelemetryAttribute {
  const TelemetryBooleanAttribute({
    required super.key,
    required this.boolValue,
    super.classification = TelemetryAttributeClassification.public,
    super.redactionStatus,
  }) : super();

  final bool boolValue;

  @override
  TelemetryAttributeType get attributeType => TelemetryAttributeType.boolean;

  @override
  Object? get value => boolValue;

  @override
  Map<String, dynamic> toJson() => {
        'attributeType': attributeType.wireName,
        'key': key,
        'value': boolValue,
        'classification': classification.wireName,
        'redactionStatus': redactionStatus.wireName,
      };

  factory TelemetryBooleanAttribute.fromJson(Map<String, dynamic> json) {
    return TelemetryBooleanAttribute(
      key: json['key'] as String,
      boolValue: json['value'] as bool,
      classification: TelemetryAttributeClassificationX.fromWireName(
        json['classification'] as String? ?? 'public',
      ),
      redactionStatus: TelemetryRedactionStatusX.fromWireName(
        json['redactionStatus'] as String? ?? 'none',
      ),
    );
  }
}

class TelemetryEnumAttribute extends TelemetryAttribute {
  const TelemetryEnumAttribute({
    required super.key,
    required this.enumValue,
    super.classification = TelemetryAttributeClassification.public,
    super.redactionStatus,
  }) : super();

  final String enumValue;

  @override
  TelemetryAttributeType get attributeType => TelemetryAttributeType.enumValue;

  @override
  Object? get value => enumValue;

  @override
  Map<String, dynamic> toJson() => {
        'attributeType': attributeType.wireName,
        'key': key,
        'value': enumValue,
        'classification': classification.wireName,
        'redactionStatus': redactionStatus.wireName,
      };

  factory TelemetryEnumAttribute.fromJson(Map<String, dynamic> json) {
    return TelemetryEnumAttribute(
      key: json['key'] as String,
      enumValue: json['value'] as String,
      classification: TelemetryAttributeClassificationX.fromWireName(
        json['classification'] as String? ?? 'public',
      ),
      redactionStatus: TelemetryRedactionStatusX.fromWireName(
        json['redactionStatus'] as String? ?? 'none',
      ),
    );
  }
}

class TelemetryDurationAttribute extends TelemetryAttribute {
  const TelemetryDurationAttribute({
    required super.key,
    required this.durationMicroseconds,
    super.classification = TelemetryAttributeClassification.public,
    super.redactionStatus,
  }) : super(unit: 'microseconds');

  final int durationMicroseconds;

  @override
  TelemetryAttributeType get attributeType => TelemetryAttributeType.duration;

  @override
  Object? get value => durationMicroseconds;

  @override
  Map<String, dynamic> toJson() => {
        'attributeType': attributeType.wireName,
        'key': key,
        'value': durationMicroseconds,
        'classification': classification.wireName,
        'unit': unit,
        'redactionStatus': redactionStatus.wireName,
      };

  factory TelemetryDurationAttribute.fromJson(Map<String, dynamic> json) {
    return TelemetryDurationAttribute(
      key: json['key'] as String,
      durationMicroseconds: json['value'] as int,
      classification: TelemetryAttributeClassificationX.fromWireName(
        json['classification'] as String? ?? 'public',
      ),
      redactionStatus: TelemetryRedactionStatusX.fromWireName(
        json['redactionStatus'] as String? ?? 'none',
      ),
    );
  }
}

class TelemetryArtifactReferenceAttribute extends TelemetryAttribute {
  const TelemetryArtifactReferenceAttribute({
    required super.key,
    required this.artifactId,
    super.classification = TelemetryAttributeClassification.public,
    super.redactionStatus,
  }) : super();

  final String artifactId;

  @override
  TelemetryAttributeType get attributeType =>
      TelemetryAttributeType.artifactReference;

  @override
  Object? get value => artifactId;

  @override
  Map<String, dynamic> toJson() => {
        'attributeType': attributeType.wireName,
        'key': key,
        'value': artifactId,
        'classification': classification.wireName,
        'redactionStatus': redactionStatus.wireName,
      };

  factory TelemetryArtifactReferenceAttribute.fromJson(
    Map<String, dynamic> json,
  ) {
    return TelemetryArtifactReferenceAttribute(
      key: json['key'] as String,
      artifactId: json['value'] as String,
      classification: TelemetryAttributeClassificationX.fromWireName(
        json['classification'] as String? ?? 'public',
      ),
      redactionStatus: TelemetryRedactionStatusX.fromWireName(
        json['redactionStatus'] as String? ?? 'none',
      ),
    );
  }
}

class TelemetryCountAttribute extends TelemetryAttribute {
  const TelemetryCountAttribute({
    required super.key,
    required this.count,
    super.classification = TelemetryAttributeClassification.public,
    super.redactionStatus,
  }) : super();

  final int count;

  @override
  TelemetryAttributeType get attributeType => TelemetryAttributeType.count;

  @override
  Object? get value => count;

  @override
  Map<String, dynamic> toJson() => {
        'attributeType': attributeType.wireName,
        'key': key,
        'value': count,
        'classification': classification.wireName,
        'redactionStatus': redactionStatus.wireName,
      };

  factory TelemetryCountAttribute.fromJson(Map<String, dynamic> json) {
    return TelemetryCountAttribute(
      key: json['key'] as String,
      count: json['value'] as int,
      classification: TelemetryAttributeClassificationX.fromWireName(
        json['classification'] as String? ?? 'public',
      ),
      redactionStatus: TelemetryRedactionStatusX.fromWireName(
        json['redactionStatus'] as String? ?? 'none',
      ),
    );
  }
}
