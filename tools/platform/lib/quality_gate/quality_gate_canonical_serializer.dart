import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/quality_gate/quality_gate_evidence.dart';
import '../models/quality_gate/quality_gate_policy.dart';
import '../models/quality_gate/quality_gate_request.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';

/// Canonical serialization and fingerprinting for quality gates.
class QualityGateCanonicalSerializer {
  const QualityGateCanonicalSerializer();

  static const String version = 'quality-gate-canonical-v1';

  String fingerprintFromString(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  String policyFingerprint(QualityGatePolicy policy) {
    return fingerprintFromString(jsonEncode(policy.toComparableJson()));
  }

  String requestFingerprint(QualityGateRequest request) {
    final json = request.toJson()..remove('createdAt');
    return fingerprintFromString(jsonEncode(_normalizeJson(json)));
  }

  String evaluationFingerprint(QualityGateEvaluation evaluation) {
    final json = evaluation.toJson()..remove('evaluationFingerprint');
    return fingerprintFromString(jsonEncode(_normalizeJson(json)));
  }

  String evidenceFingerprint(QualityGateEvidence evidence) {
    final json = evidence.toJson()..remove('evidenceId');
    return fingerprintFromString(jsonEncode(_normalizeJson(json)));
  }

  String snapshotFingerprint(QualityGateSnapshot snapshot) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(snapshot.toComparableJson())),
    );
  }

  String sourceSetFingerprint(List<Map<String, dynamic>> sourceRefs) {
    final sorted = sourceRefs.map(_normalizeJson).toList()
      ..sort((a, b) =>
          (a['sourceType'] as String).compareTo(b['sourceType'] as String));
    return fingerprintFromString(jsonEncode(sorted));
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
      if (value == -0.0) return 0.0;
      return value;
    }
    return value;
  }
}
