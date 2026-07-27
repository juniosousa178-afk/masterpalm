/// Neutral change classification for [HistoryDiff].
enum HistoryChangeType {
  artifactAdded,
  artifactRemoved,
  artifactChanged,
  artifactUnchanged,
  metricAdded,
  metricRemoved,
  metricValueChanged,
  graphNodeAdded,
  graphNodeRemoved,
  graphEdgeAdded,
  graphEdgeRemoved,
  reportSectionAdded,
  reportSectionRemoved,
  guardianDecisionChanged,
  guardianViolationAdded,
  guardianViolationRemoved,
  astSummaryChanged,
  telemetryStatusChanged,
  eventCountChanged,
  failureCountChanged,
  componentCoverageChanged,
  incompleteOperationCountChanged,
  compatibilityChanged,
}

extension HistoryChangeTypeX on HistoryChangeType {
  String get wireName => name;

  static HistoryChangeType fromWireName(String value) {
    return HistoryChangeType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown HistoryChangeType: $value'),
    );
  }
}

/// Category grouping for history changes.
enum HistoryChangeCategory {
  artifact,
  metrics,
  graph,
  report,
  guardian,
  ast,
  compatibility,
  telemetry,
}

extension HistoryChangeCategoryX on HistoryChangeCategory {
  String get wireName => name;

  static HistoryChangeCategory fromWireName(String value) {
    return HistoryChangeCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown HistoryChangeCategory: $value'),
    );
  }
}
