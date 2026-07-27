import 'dart:convert';

import '../models/graph/project_graph.dart';
import '../models/metrics/metrics_snapshot.dart';
import 'metrics_math.dart';

/// Produces stable canonical representations for fingerprints and comparison.
class MetricsCanonicalSerializer {
  const MetricsCanonicalSerializer();

  String canonicalizeGraph(ProjectGraph graph) {
    final json = Map<String, dynamic>.from(graph.toComparableJson());
    final nodes = (json['nodes'] as List<dynamic>).map((e) {
      return Map<String, dynamic>.from(e as Map);
    }).toList()
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final edges = (json['edges'] as List<dynamic>).map((e) {
      return Map<String, dynamic>.from(e as Map);
    }).toList()
      ..sort((a, b) {
        final aKey =
            '${a['sourceId']}|${a['type']}|${a['targetId']}|${a['context'] ?? ''}';
        final bKey =
            '${b['sourceId']}|${b['type']}|${b['targetId']}|${b['context'] ?? ''}';
        return aKey.compareTo(bKey);
      });
    json['nodes'] = nodes;
    json['edges'] = edges;
    return jsonEncode(_normalizeJson(json));
  }

  String canonicalizeSnapshot(MetricsSnapshot snapshot) {
    final comparable = snapshot.toComparableJson();
    final metrics = (comparable['metrics'] as List<dynamic>)
      ..sort((a, b) {
        final aId = (a as Map)['definition']['id'] as String;
        final bId = (b as Map)['definition']['id'] as String;
        return aId.compareTo(bId);
      });
    comparable['metrics'] = metrics;
    return jsonEncode(_normalizeJson(comparable));
  }

  Map<String, dynamic> _normalizeJson(Map<String, dynamic> input) {
    final output = <String, dynamic>{};
    final keys = input.keys.toList()..sort();
    for (final key in keys) {
      final value = input[key];
      output[key] = _normalizeValue(value);
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
      return MetricsMath.normalizeDecimal(value);
    }
    return value;
  }
}
