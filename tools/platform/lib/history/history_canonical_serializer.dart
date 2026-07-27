import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/history/history_artifact.dart';
import '../models/history/history_artifact_type.dart';
import '../models/history/history_snapshot.dart';

/// Produces stable canonical representations for history fingerprints.
class HistoryCanonicalSerializer {
  const HistoryCanonicalSerializer();

  String fingerprintFromString(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  String snapshotFingerprint(
      List<HistoryArtifact> artifacts, String projectId) {
    final parts = <String>[projectId];
    final sorted = artifacts.toList()
      ..sort((a, b) {
        final typeCmp =
            a.artifactType.wireName.compareTo(b.artifactType.wireName);
        if (typeCmp != 0) return typeCmp;
        return a.artifactId.compareTo(b.artifactId);
      });
    for (final artifact in sorted) {
      parts.add(
          '${artifact.artifactType.wireName}:${artifact.artifactId}:${artifact.fingerprint}');
    }
    return fingerprintFromString(parts.join('|'));
  }

  String canonicalizeSnapshot(HistorySnapshot snapshot) {
    final comparable = snapshot.toComparableJson();
    final artifacts = (comparable['artifacts'] as List<dynamic>)
      ..sort((a, b) {
        final aMap = a as Map;
        final bMap = b as Map;
        final typeCmp = (aMap['artifactType'] as String)
            .compareTo(bMap['artifactType'] as String);
        if (typeCmp != 0) return typeCmp;
        return (aMap['artifactId'] as String)
            .compareTo(bMap['artifactId'] as String);
      });
    comparable['artifacts'] = artifacts;
    return jsonEncode(_normalizeJson(comparable));
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
