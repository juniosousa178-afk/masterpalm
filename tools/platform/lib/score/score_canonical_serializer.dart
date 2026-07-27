import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/score/score_policy.dart';
import '../models/score/score_snapshot.dart';
import 'score_exceptions.dart';

/// Canonical serialization and fingerprinting for score snapshots.
class ScoreCanonicalSerializer {
  const ScoreCanonicalSerializer();

  String fingerprintFromString(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  String policyFingerprint(ScorePolicy policy) {
    return fingerprintFromString(jsonEncode(policy.toComparableJson()));
  }

  String scoreFingerprint({
    required String projectId,
    required String policyId,
    required int policyVersion,
    required String policyFingerprint,
    required String metricsSnapshotId,
    String? historyDiffFingerprint,
    String? guardianFingerprint,
    required String overallScore,
    required List<String> dimensionFingerprints,
  }) {
    final parts = [
      projectId,
      policyId,
      policyVersion.toString(),
      policyFingerprint,
      metricsSnapshotId,
      if (historyDiffFingerprint != null) historyDiffFingerprint,
      if (guardianFingerprint != null) guardianFingerprint,
      overallScore,
      ...dimensionFingerprints,
    ];
    return fingerprintFromString(parts.join('|'));
  }

  String canonicalizeSnapshot(EngineeringScoreSnapshot snapshot) {
    final comparable = snapshot.toComparableJson();
    final dims = (comparable['dimensions'] as List<dynamic>)
      ..sort((a, b) => (a as Map)['dimensionId']
          .toString()
          .compareTo((b as Map)['dimensionId'].toString()));
    comparable['dimensions'] = dims;
    return jsonEncode(_normalizeJson(comparable));
  }

  double roundScore(double value, int precision) {
    if (value.isNaN || value.isInfinite) {
      throw ScoreValidationException('Score value is not finite: $value');
    }
    if (value == 0 || value == -0.0) return 0.0;
    return double.parse(value.toStringAsFixed(precision));
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
      if (value.isNaN || value.isInfinite) return 0.0;
      if (value == 0 || value == -0.0) return 0.0;
      return double.parse(value.toStringAsFixed(6));
    }
    return value;
  }
}
