import 'dashboard_enums.dart';

/// Base class for typed widget payloads.
abstract class DashboardWidgetData {
  const DashboardWidgetData();

  String get dataType;
  Map<String, dynamic> toJson();

  static DashboardWidgetData fromJson(Map<String, dynamic> json) {
    final type = json['dataType'] as String;
    switch (type) {
      case 'scalar':
        return DashboardScalarData.fromJson(json);
      case 'percentage':
        return DashboardPercentageData.fromJson(json);
      case 'status':
        return DashboardStatusData.fromJson(json);
      case 'band':
        return DashboardBandData.fromJson(json);
      case 'distribution':
        return DashboardDistributionData.fromJson(json);
      case 'list':
        return DashboardListData.fromJson(json);
      case 'comparison':
        return DashboardComparisonData.fromJson(json);
      case 'delta':
        return DashboardDeltaData.fromJson(json);
      case 'table':
        return DashboardTableData.fromJson(json);
      case 'text':
        return DashboardTextData.fromJson(json);
      case 'sourceList':
        return DashboardSourceListData.fromJson(json);
      case 'limitationList':
        return DashboardLimitationListData.fromJson(json);
      default:
        throw FormatException('Unknown widget data type: $type');
    }
  }
}

class DashboardScalarData extends DashboardWidgetData {
  const DashboardScalarData({
    required this.value,
    this.unit,
    this.precision = 2,
  });

  final double value;
  final String? unit;
  final int precision;

  @override
  String get dataType => 'scalar';

  @override
  Map<String, dynamic> toJson() => {
        'dataType': dataType,
        'value': value,
        if (unit != null) 'unit': unit,
        'precision': precision,
      };

  factory DashboardScalarData.fromJson(Map<String, dynamic> json) {
    return DashboardScalarData(
      value: (json['value'] as num).toDouble(),
      unit: json['unit'] as String?,
      precision: json['precision'] as int? ?? 2,
    );
  }
}

class DashboardPercentageData extends DashboardWidgetData {
  const DashboardPercentageData({required this.value, this.precision = 2});

  final double value;
  final int precision;

  @override
  String get dataType => 'percentage';

  @override
  Map<String, dynamic> toJson() => {
        'dataType': dataType,
        'value': value,
        'precision': precision,
      };

  factory DashboardPercentageData.fromJson(Map<String, dynamic> json) {
    return DashboardPercentageData(
      value: (json['value'] as num).toDouble(),
      precision: json['precision'] as int? ?? 2,
    );
  }
}

class DashboardStatusData extends DashboardWidgetData {
  const DashboardStatusData({required this.status, this.detail});

  final String status;
  final String? detail;

  @override
  String get dataType => 'status';

  @override
  Map<String, dynamic> toJson() => {
        'dataType': dataType,
        'status': status,
        if (detail != null) 'detail': detail,
      };

  factory DashboardStatusData.fromJson(Map<String, dynamic> json) {
    return DashboardStatusData(
      status: json['status'] as String,
      detail: json['detail'] as String?,
    );
  }
}

class DashboardBandData extends DashboardWidgetData {
  const DashboardBandData({required this.bandId, this.label});

  final String bandId;
  final String? label;

  @override
  String get dataType => 'band';

  @override
  Map<String, dynamic> toJson() => {
        'dataType': dataType,
        'bandId': bandId,
        if (label != null) 'label': label,
      };

  factory DashboardBandData.fromJson(Map<String, dynamic> json) {
    return DashboardBandData(
      bandId: json['bandId'] as String,
      label: json['label'] as String?,
    );
  }
}

class DashboardDistributionData extends DashboardWidgetData {
  const DashboardDistributionData({required this.entries});

  final List<MapEntry<String, double>> entries;

  @override
  String get dataType => 'distribution';

  @override
  Map<String, dynamic> toJson() => {
        'dataType': dataType,
        'entries': entries.map((e) => {'key': e.key, 'value': e.value}).toList()
          ..sort((a, b) => a['key'].toString().compareTo(b['key'].toString())),
      };

  factory DashboardDistributionData.fromJson(Map<String, dynamic> json) {
    final entries = (json['entries'] as List<dynamic>)
        .map(
          (e) => MapEntry(
            (e as Map)['key'] as String,
            ((e)['value'] as num).toDouble(),
          ),
        )
        .toList();
    return DashboardDistributionData(entries: entries);
  }
}

class DashboardListData extends DashboardWidgetData {
  const DashboardListData({required this.items, this.ranked = false});

  final List<String> items;
  final bool ranked;

  @override
  String get dataType => 'list';

  @override
  Map<String, dynamic> toJson() => {
        'dataType': dataType,
        'items': items,
        'ranked': ranked,
      };

  factory DashboardListData.fromJson(Map<String, dynamic> json) {
    return DashboardListData(
      items: (json['items'] as List<dynamic>).map((e) => e.toString()).toList(),
      ranked: json['ranked'] as bool? ?? false,
    );
  }
}

class DashboardComparisonData extends DashboardWidgetData {
  const DashboardComparisonData({
    required this.leftLabel,
    required this.rightLabel,
    required this.leftValue,
    required this.rightValue,
  });

  final String leftLabel;
  final String rightLabel;
  final String leftValue;
  final String rightValue;

  @override
  String get dataType => 'comparison';

  @override
  Map<String, dynamic> toJson() => {
        'dataType': dataType,
        'leftLabel': leftLabel,
        'rightLabel': rightLabel,
        'leftValue': leftValue,
        'rightValue': rightValue,
      };

  factory DashboardComparisonData.fromJson(Map<String, dynamic> json) {
    return DashboardComparisonData(
      leftLabel: json['leftLabel'] as String,
      rightLabel: json['rightLabel'] as String,
      leftValue: json['leftValue'] as String,
      rightValue: json['rightValue'] as String,
    );
  }
}

class DashboardDeltaData extends DashboardWidgetData {
  const DashboardDeltaData({
    required this.label,
    required this.delta,
    this.absolute = true,
  });

  final String label;
  final double delta;
  final bool absolute;

  @override
  String get dataType => 'delta';

  @override
  Map<String, dynamic> toJson() => {
        'dataType': dataType,
        'label': label,
        'delta': delta,
        'absolute': absolute,
      };

  factory DashboardDeltaData.fromJson(Map<String, dynamic> json) {
    return DashboardDeltaData(
      label: json['label'] as String,
      delta: (json['delta'] as num).toDouble(),
      absolute: json['absolute'] as bool? ?? true,
    );
  }
}

class DashboardTableData extends DashboardWidgetData {
  const DashboardTableData({
    required this.headers,
    required this.rows,
  });

  final List<String> headers;
  final List<List<String>> rows;

  @override
  String get dataType => 'table';

  @override
  Map<String, dynamic> toJson() => {
        'dataType': dataType,
        'headers': headers,
        'rows': rows,
      };

  factory DashboardTableData.fromJson(Map<String, dynamic> json) {
    return DashboardTableData(
      headers:
          (json['headers'] as List<dynamic>).map((e) => e.toString()).toList(),
      rows: (json['rows'] as List<dynamic>)
          .map(
            (row) =>
                (row as List<dynamic>).map((cell) => cell.toString()).toList(),
          )
          .toList(),
    );
  }
}

class DashboardTextData extends DashboardWidgetData {
  const DashboardTextData({required this.text});

  final String text;

  @override
  String get dataType => 'text';

  @override
  Map<String, dynamic> toJson() => {'dataType': dataType, 'text': text};

  factory DashboardTextData.fromJson(Map<String, dynamic> json) {
    return DashboardTextData(text: json['text'] as String);
  }
}

class DashboardSourceListData extends DashboardWidgetData {
  const DashboardSourceListData({required this.sourceIds});

  final List<String> sourceIds;

  @override
  String get dataType => 'sourceList';

  @override
  Map<String, dynamic> toJson() => {
        'dataType': dataType,
        'sourceIds': sourceIds,
      };

  factory DashboardSourceListData.fromJson(Map<String, dynamic> json) {
    return DashboardSourceListData(
      sourceIds: (json['sourceIds'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class DashboardLimitationListData extends DashboardWidgetData {
  const DashboardLimitationListData({required this.limitations});

  final List<String> limitations;

  @override
  String get dataType => 'limitationList';

  @override
  Map<String, dynamic> toJson() => {
        'dataType': dataType,
        'limitations': limitations,
      };

  factory DashboardLimitationListData.fromJson(Map<String, dynamic> json) {
    return DashboardLimitationListData(
      limitations: (json['limitations'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Semantic dashboard widget (presentation intent, not UI).
class DashboardWidget {
  const DashboardWidget({
    required this.widgetId,
    required this.type,
    required this.title,
    required this.availability,
    required this.data,
    this.sourceReferenceIds = const [],
    this.order = 0,
    this.presentationHint = DashboardPresentationHint.primary,
  });

  final String widgetId;
  final DashboardWidgetType type;
  final String title;
  final DashboardAvailability availability;
  final DashboardWidgetData? data;
  final List<String> sourceReferenceIds;
  final int order;
  final DashboardPresentationHint presentationHint;

  Map<String, dynamic> toJson() => {
        'widgetId': widgetId,
        'type': type.wireName,
        'title': title,
        'availability': availability.wireName,
        if (data != null) 'data': data!.toJson(),
        'sourceReferenceIds': sourceReferenceIds,
        'order': order,
        'presentationHint': presentationHint.wireName,
      };

  factory DashboardWidget.fromJson(Map<String, dynamic> json) {
    return DashboardWidget(
      widgetId: json['widgetId'] as String,
      type: DashboardWidgetTypeX.fromWireName(json['type'] as String),
      title: json['title'] as String,
      availability: DashboardAvailabilityX.fromWireName(
        json['availability'] as String,
      ),
      data: json['data'] == null
          ? null
          : DashboardWidgetData.fromJson(
              json['data'] as Map<String, dynamic>,
            ),
      sourceReferenceIds: (json['sourceReferenceIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      order: json['order'] as int? ?? 0,
      presentationHint: DashboardPresentationHintX.fromWireName(
        json['presentationHint'] as String? ?? 'primary',
      ),
    );
  }
}
