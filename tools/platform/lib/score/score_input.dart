import '../models/metrics/metric_availability.dart';
import '../models/metrics/metric_record.dart';
import '../models/metrics/metric_unit.dart';
import '../models/metrics/metric_value.dart';
import '../models/metrics/metrics_snapshot.dart';
import '../models/history/history_diff.dart';
import '../models/score/score_enums.dart';
import '../models/score/score_policy.dart';

/// Resolved typed input for score calculation.
class ScoreInput {
  const ScoreInput({
    required this.projectId,
    required this.metricsSnapshot,
    required this.policy,
    this.guardianAnalysis,
    this.historyDiff,
    this.historySnapshot,
    this.requestedDimensions,
    this.requestedRuleIds,
    this.strictCompatibility = false,
    this.includeTrace = false,
    this.includeExplanations = true,
    this.gitRef,
    this.branch,
    this.sourceEventId,
    this.createdAt,
  });

  final String projectId;
  final MetricsSnapshot metricsSnapshot;
  final ScorePolicy policy;
  final Map<String, dynamic>? guardianAnalysis;
  final HistoryDiff? historyDiff;
  final Map<String, dynamic>? historySnapshot;
  final Set<String>? requestedDimensions;
  final Set<String>? requestedRuleIds;
  final bool strictCompatibility;
  final bool includeTrace;
  final bool includeExplanations;
  final String? gitRef;
  final String? branch;
  final String? sourceEventId;
  final String? createdAt;

  Map<String, MetricRecord> get metricsById => {
        for (final m in metricsSnapshot.metrics) m.definition.id: m,
      };

  bool hasGuardian() =>
      guardianAnalysis != null && guardianAnalysis!.isNotEmpty;

  bool hasHistoryDiff() => historyDiff != null;
}

/// Extracted numeric or text evidence from a metric record.
class MetricEvidenceValue {
  const MetricEvidenceValue({
    required this.availability,
    this.numericValue,
    this.textValue,
    this.booleanValue,
    this.message,
    this.unit,
    this.calculationVersion,
  });

  final ScoreAvailability availability;
  final double? numericValue;
  final String? textValue;
  final bool? booleanValue;
  final String? message;
  final String? unit;
  final int? calculationVersion;

  factory MetricEvidenceValue.fromRecord(MetricRecord record) {
    if (record.availability != MetricAvailability.available) {
      return MetricEvidenceValue(
        availability: ScoreAvailability.unavailable,
        message: record.message ?? 'Metric unavailable',
        unit: record.definition.unit.wireName,
        calculationVersion: record.definition.calculationVersion,
      );
    }
    final value = record.value;
    if (value is IntegerMetricValue) {
      return MetricEvidenceValue(
        availability: ScoreAvailability.available,
        numericValue: value.value.toDouble(),
        unit: record.definition.unit.wireName,
        calculationVersion: record.definition.calculationVersion,
      );
    }
    if (value is DecimalMetricValue || value is PercentageMetricValue) {
      final n = value is DecimalMetricValue
          ? value.value
          : (value as PercentageMetricValue).value;
      return MetricEvidenceValue(
        availability: ScoreAvailability.available,
        numericValue: n,
        unit: record.definition.unit.wireName,
        calculationVersion: record.definition.calculationVersion,
      );
    }
    if (value is BooleanMetricValue) {
      return MetricEvidenceValue(
        availability: ScoreAvailability.available,
        booleanValue: value.value,
        unit: record.definition.unit.wireName,
        calculationVersion: record.definition.calculationVersion,
      );
    }
    if (value is TextMetricValue) {
      return MetricEvidenceValue(
        availability: ScoreAvailability.available,
        textValue: value.value,
        unit: record.definition.unit.wireName,
        calculationVersion: record.definition.calculationVersion,
      );
    }
    return MetricEvidenceValue(
      availability: ScoreAvailability.partial,
      message: 'Unsupported metric value type for scoring',
      unit: record.definition.unit.wireName,
      calculationVersion: record.definition.calculationVersion,
    );
  }
}
