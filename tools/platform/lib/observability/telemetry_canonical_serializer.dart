import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/observability/telemetry_event.dart';
import '../models/observability/telemetry_snapshot.dart';

/// Canonical serialization and fingerprinting for telemetry.
class TelemetryCanonicalSerializer {
  const TelemetryCanonicalSerializer();

  String fingerprintFromString(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  String eventFingerprint(TelemetryEvent event) {
    return fingerprintFromString(jsonEncode(event.toComparableJson()));
  }

  String scopeFingerprint({
    String? projectId,
    String? correlationId,
    String? operationId,
    String? timeRangeFrom,
    String? timeRangeTo,
    List<String> components = const [],
    List<String> operations = const [],
    List<String> statuses = const [],
    List<String> severities = const [],
    bool includeEvents = true,
    bool includeAttributes = true,
    bool includeErrors = true,
    bool includeWarnings = true,
    bool includeSourceReferences = true,
    bool includeSummaries = true,
    bool strictCompatibility = false,
    int maximumEventCount = 10000,
    String ordering = 'startedAt',
  }) {
    final parts = [
      projectId ?? '',
      correlationId ?? '',
      operationId ?? '',
      timeRangeFrom ?? '',
      timeRangeTo ?? '',
      ...List<String>.from(components)..sort(),
      ...List<String>.from(operations)..sort(),
      ...List<String>.from(statuses)..sort(),
      ...List<String>.from(severities)..sort(),
      includeEvents.toString(),
      includeAttributes.toString(),
      includeErrors.toString(),
      includeWarnings.toString(),
      includeSourceReferences.toString(),
      includeSummaries.toString(),
      strictCompatibility.toString(),
      maximumEventCount.toString(),
      ordering,
    ];
    return fingerprintFromString(parts.join('|'));
  }

  String telemetryFingerprint({
    required List<String> eventFingerprints,
    required String summaryFingerprint,
    required String coverageFingerprint,
    required String compatibility,
    required int schemaVersion,
    required int calculationVersion,
    required int canonicalizationVersion,
  }) {
    final parts = [
      ...List<String>.from(eventFingerprints)..sort(),
      summaryFingerprint,
      coverageFingerprint,
      compatibility,
      schemaVersion.toString(),
      calculationVersion.toString(),
      canonicalizationVersion.toString(),
    ];
    return fingerprintFromString(parts.join('|'));
  }

  String canonicalizeEvent(TelemetryEvent event) {
    return jsonEncode(_normalizeJson(event.toComparableJson()));
  }

  String canonicalizeSnapshot(TelemetrySnapshot snapshot) {
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
        throw FormatException('Non-finite value in canonicalization');
      }
      if (value == 0 || value == -0.0) return 0.0;
      return double.parse(value.toStringAsFixed(6));
    }
    return value;
  }
}
