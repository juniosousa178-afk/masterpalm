import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/dashboard/dashboard_snapshot.dart';
import 'dashboard_exceptions.dart';

/// Canonical serialization and fingerprinting for dashboard snapshots.
class DashboardCanonicalSerializer {
  const DashboardCanonicalSerializer();

  String fingerprintFromString(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  String queryFingerprint({
    required String projectId,
    String? branch,
    String? gitRef,
    String? timeRangeFrom,
    String? timeRangeTo,
    List<String> filters = const [],
    List<String> requestedSections = const [],
    List<String> requestedWidgetIds = const [],
    Map<String, String> sourceArtifactIds = const {},
    String? layoutId,
    bool useLatest = true,
    bool strictCompatibility = false,
    String comparisonMode = 'none',
    String? baselineSnapshotId,
  }) {
    final parts = [
      projectId,
      branch ?? '',
      gitRef ?? '',
      timeRangeFrom ?? '',
      timeRangeTo ?? '',
      ...List<String>.from(filters)..sort(),
      ...List<String>.from(requestedSections)..sort(),
      ...List<String>.from(requestedWidgetIds)..sort(),
      ...sourceArtifactIds.entries.map((e) => '${e.key}=${e.value}').toList()
        ..sort(),
      layoutId ?? '',
      useLatest.toString(),
      strictCompatibility.toString(),
      comparisonMode,
      baselineSnapshotId ?? '',
    ];
    return fingerprintFromString(parts.join('|'));
  }

  String dashboardFingerprint({
    required List<String> sourceFingerprints,
    required List<String> sectionIds,
    required List<String> widgetIds,
    required String availabilitySummary,
    required String compatibility,
    required String freshness,
    required String layoutId,
    required int schemaVersion,
    required int calculationVersion,
    required int canonicalizationVersion,
  }) {
    final parts = [
      ...List<String>.from(sourceFingerprints)..sort(),
      ...List<String>.from(sectionIds)..sort(),
      ...List<String>.from(widgetIds)..sort(),
      availabilitySummary,
      compatibility,
      freshness,
      layoutId,
      schemaVersion.toString(),
      calculationVersion.toString(),
      canonicalizationVersion.toString(),
    ];
    return fingerprintFromString(parts.join('|'));
  }

  String canonicalizeSnapshot(DashboardSnapshot snapshot) {
    return jsonEncode(_normalizeJson(snapshot.toComparableJson()));
  }

  Map<String, dynamic> _normalizeJson(Map<String, dynamic> input) {
    final output = <String, dynamic>{};
    final keys = input.keys.toList()..sort();
    for (final key in keys) {
      output[key] = _normalizeValue(input[key]);
    }
    return output;
  }

  dynamic _normalizeValue(dynamic value) {
    if (value is Map) {
      return _normalizeJson(value.map((k, v) => MapEntry(k.toString(), v)));
    }
    if (value is List) {
      return value.map(_normalizeValue).toList();
    }
    if (value is double) {
      if (value.isNaN || value.isInfinite) {
        throw DashboardValidationException(
          'Non-finite value in canonicalization',
        );
      }
      if (value == 0 || value == -0.0) return 0.0;
      return double.parse(value.toStringAsFixed(6));
    }
    return value;
  }
}
