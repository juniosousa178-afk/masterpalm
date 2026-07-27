import '../models/dashboard/dashboard_enums.dart';
import '../models/dashboard/dashboard_request.dart';
import '../models/dashboard/dashboard_snapshot.dart';
import '../models/metrics/metrics_snapshot.dart';

/// Validates [DashboardRequest] invariants before composition.
class DashboardRequestValidator {
  const DashboardRequestValidator();

  DashboardValidationResult validate(DashboardRequest request) {
    final errors = <String>[];
    final warnings = <String>[];

    if (request.projectId.trim().isEmpty) {
      errors.add('projectId must not be empty');
    }
    if (request.createdAt.trim().isEmpty) {
      errors.add('createdAt must not be empty');
    }
    if (request.referenceTime.trim().isEmpty) {
      errors.add('referenceTime must not be empty');
    }

    final range = request.timeRange;
    if (range != null && range.from.compareTo(range.to) > 0) {
      errors.add('timeRange.from must not be after timeRange.to');
    }

    final sections = request.requestedSections?.toList() ?? [];
    if (sections.length != sections.toSet().length) {
      errors.add('requestedSections contains duplicates');
    }

    for (final widgetId in request.requestedWidgetIds ?? const {}) {
      if (widgetId.trim().isEmpty) {
        errors.add('requestedWidgetId must not be empty');
      }
    }

    for (final id in [
      request.metricsSnapshotId,
      request.historySnapshotId,
      request.scoreSnapshotId,
      request.mesSnapshotId,
    ]) {
      if (id != null && id.trim().isEmpty) {
        errors.add('source artifact ID must not be empty');
      }
    }

    _validateInjectedProject(
      request.projectId,
      request.metricsSnapshot?.metadata.projectId,
      'metrics',
      errors,
    );
    _validateInjectedProject(
      request.projectId,
      request.historySnapshot?.metadata.projectId,
      'history',
      errors,
    );
    _validateInjectedProject(
      request.projectId,
      request.engineeringScoreSnapshot?.metadata.projectId,
      'score',
      errors,
    );
    _validateInjectedProject(
      request.projectId,
      request.mesSnapshot?.metadata.projectId,
      'mes',
      errors,
    );

    if (request.branch != null) {
      _validateBranch(request.branch, request.metricsSnapshot, errors);
      _validateBranch(request.branch, request.engineeringScoreSnapshot, errors);
      _validateBranch(request.branch, request.mesSnapshot, errors);
    }

    if (request.gitRef != null) {
      _validateGitRef(request.gitRef, request.metricsSnapshot, errors);
      _validateGitRef(request.gitRef, request.engineeringScoreSnapshot, errors);
      _validateGitRef(request.gitRef, request.mesSnapshot, errors);
    }

    if (request.layoutId != null &&
        request.layoutId!.trim().isNotEmpty &&
        request.layoutId != 'dashboard-foundation-v1') {
      errors.add('layoutId is invalid: ${request.layoutId}');
    }

    if (request.comparisonMode == DashboardComparisonMode.baseline &&
        (request.baselineSnapshotId == null ||
            request.baselineSnapshotId!.trim().isEmpty)) {
      errors.add('baselineSnapshotId is required for baseline comparison');
    }

    if (!request.useLatest &&
        request.metricsSnapshot == null &&
        request.historySnapshot == null &&
        request.engineeringScoreSnapshot == null &&
        request.mesSnapshot == null &&
        request.projectGraph == null &&
        request.guardianResult == null &&
        (request.guardianAnalysis == null ||
            request.guardianAnalysis!.isEmpty) &&
        request.metricsSnapshotId == null &&
        request.historySnapshotId == null &&
        request.scoreSnapshotId == null &&
        request.mesSnapshotId == null) {
      errors.add('useLatest is false but no sources were provided');
    }

    if (request.freshnessPolicy.currentMaxAgeHours < 0 ||
        request.freshnessPolicy.recentMaxAgeHours < 0 ||
        request.freshnessPolicy.staleAfterHours < 0 ||
        request.freshnessPolicy.maxSourceSkewHours < 0) {
      errors.add('freshnessPolicy contains negative durations');
    }

    if (request.freshnessPolicy.currentMaxAgeHours >
        request.freshnessPolicy.recentMaxAgeHours) {
      warnings.add('currentMaxAgeHours exceeds recentMaxAgeHours');
    }

    return DashboardValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  void _validateInjectedProject(
    String expected,
    String? actual,
    String source,
    List<String> errors,
  ) {
    if (actual != null && actual != expected) {
      errors.add('Injected $source artifact belongs to another project');
    }
  }

  void _validateBranch(
    String? expected,
    dynamic snapshot,
    List<String> errors,
  ) {
    if (snapshot == null || expected == null) return;
    final branch = _readBranch(snapshot);
    if (branch != null && branch != expected) {
      errors.add('Injected artifact branch is incompatible');
    }
  }

  void _validateGitRef(
    String? expected,
    dynamic snapshot,
    List<String> errors,
  ) {
    if (snapshot == null || expected == null) return;
    final gitRef = _readGitRef(snapshot);
    if (gitRef != null && gitRef != expected) {
      errors.add('Injected artifact gitRef is incompatible');
    }
  }

  String? _readBranch(dynamic snapshot) {
    if (snapshot is MetricsSnapshot) {
      return snapshot.metadata.extra['branch'];
    }
    return snapshot.metadata.branch as String?;
  }

  String? _readGitRef(dynamic snapshot) {
    if (snapshot is MetricsSnapshot) {
      return snapshot.metadata.gitRef;
    }
    return snapshot.metadata.gitRef as String?;
  }
}
