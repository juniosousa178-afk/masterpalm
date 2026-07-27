import 'dart:convert';

import '../../models/history/history_artifact.dart';
import '../../models/history/history_artifact_payload.dart';
import '../../models/history/history_artifact_type.dart';
import '../history_canonical_serializer.dart';

/// Maps Guardian analysis payload to [HistoryArtifact].
class GuardianHistoryMapper {
  const GuardianHistoryMapper({HistoryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const HistoryCanonicalSerializer();

  final HistoryCanonicalSerializer _serializer;

  HistoryArtifact fromMap(Map<String, dynamic> json) {
    final canonical = _canonicalGuardian(json);
    final fingerprint = _serializer.fingerprintFromString(
      jsonEncode(canonical),
    );
    return HistoryArtifact(
      artifactType: HistoryArtifactType.guardian,
      artifactId: 'guardian:$fingerprint',
      schemaVersion: 1,
      fingerprint: fingerprint,
      payload: HistoryArtifactPayload(
        encoding: HistoryArtifactPayload.jsonEncoding,
        data: Map<String, dynamic>.from(json),
      ),
    );
  }

  Map<String, dynamic> _canonicalGuardian(Map<String, dynamic> json) {
    final violations = (json['violations'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList()
      ..sort((a, b) {
        final aKey = '${a['code']}|${a['file']}|${a['message']}';
        final bKey = '${b['code']}|${b['file']}|${b['message']}';
        return aKey.compareTo(bKey);
      });
    final tests = json['tests'] as Map<String, dynamic>? ?? {};
    final risk = json['risk'] as Map<String, dynamic>? ?? {};
    return {
      'decision': json['decision'],
      'risk': risk['overall'],
      'violations': violations,
      'requiredTests': (tests['required'] as List<dynamic>? ?? [])..sort(),
    };
  }
}
