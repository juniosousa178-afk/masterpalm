import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/mes/mes_policy.dart';
import '../models/mes/mes_snapshot.dart';
import '../score/score_canonical_serializer.dart';
import 'mes_exceptions.dart';

/// Canonical serialization and fingerprinting for MES snapshots.
class MESCanonicalSerializer {
  const MESCanonicalSerializer({ScoreCanonicalSerializer? scoreSerializer})
      : _scoreSerializer = scoreSerializer ?? const ScoreCanonicalSerializer();

  final ScoreCanonicalSerializer _scoreSerializer;

  String fingerprintFromString(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  String policyFingerprint(MESPolicy policy) {
    return fingerprintFromString(jsonEncode(policy.toComparableJson()));
  }

  String mesFingerprint({
    required String projectId,
    required String policyId,
    required int policyVersion,
    required String policyFingerprint,
    required String engineeringScoreSnapshotId,
    required String engineeringScoreFingerprint,
    required String eligibilityStatus,
    required String mesValue,
    required List<String> dimensionFingerprints,
    required String policyCoverage,
    required String confidence,
  }) {
    final parts = [
      projectId,
      policyId,
      policyVersion.toString(),
      policyFingerprint,
      engineeringScoreSnapshotId,
      engineeringScoreFingerprint,
      eligibilityStatus,
      mesValue,
      policyCoverage,
      confidence,
      ...dimensionFingerprints,
    ];
    return fingerprintFromString(parts.join('|'));
  }

  String canonicalizeSnapshot(MESSnapshot snapshot) {
    return jsonEncode(_normalizeJson(snapshot.toComparableJson()));
  }

  double roundScore(double value, int precision) {
    return _scoreSerializer.roundScore(value, precision);
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
        throw MESValidationException('Non-finite value in canonicalization');
      }
      if (value == 0 || value == -0.0) return 0.0;
      return double.parse(value.toStringAsFixed(6));
    }
    return value;
  }
}
