import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/dashboard/dashboard_widgets.dart';

DashboardWidget scalarWidget({
  required String widgetId,
  required String title,
  required double value,
  String? unit,
  List<String> sourceReferenceIds = const [],
  int order = 0,
}) {
  return DashboardWidget(
    widgetId: widgetId,
    type: DashboardWidgetType.scalar,
    title: title,
    availability: DashboardAvailability.available,
    data: DashboardScalarData(value: value, unit: unit),
    sourceReferenceIds: sourceReferenceIds,
    order: order,
  );
}

DashboardWidget percentageWidget({
  required String widgetId,
  required String title,
  required double value,
  List<String> sourceReferenceIds = const [],
  int order = 0,
}) {
  return DashboardWidget(
    widgetId: widgetId,
    type: DashboardWidgetType.percentage,
    title: title,
    availability: DashboardAvailability.available,
    data: DashboardPercentageData(value: value),
    sourceReferenceIds: sourceReferenceIds,
    order: order,
  );
}

DashboardWidget statusWidget({
  required String widgetId,
  required String title,
  required String status,
  List<String> sourceReferenceIds = const [],
  int order = 0,
}) {
  return DashboardWidget(
    widgetId: widgetId,
    type: DashboardWidgetType.status,
    title: title,
    availability: DashboardAvailability.available,
    data: DashboardStatusData(status: status),
    sourceReferenceIds: sourceReferenceIds,
    order: order,
  );
}

DashboardWidget unavailableWidget(
  String widgetId,
  String title, {
  int order = 0,
}) {
  return DashboardWidget(
    widgetId: widgetId,
    type: DashboardWidgetType.scalar,
    title: title,
    availability: DashboardAvailability.unavailable,
    data: null,
    order: order,
  );
}

DashboardSection buildSection({
  required DashboardSectionType type,
  required String title,
  required int order,
  required List<DashboardWidget> widgets,
  DashboardAvailability availability = DashboardAvailability.available,
  List<String> sourceReferenceIds = const [],
  List<String> limitations = const [],
  List<String> warnings = const [],
  String? description,
}) {
  return DashboardSection(
    sectionId: type.wireName,
    type: type,
    title: title,
    description: description,
    order: order,
    availability:
        widgets.isEmpty ? DashboardAvailability.unavailable : availability,
    widgets: widgets,
    sourceReferenceIds: sourceReferenceIds,
    limitations: limitations,
    warnings: warnings,
  );
}
