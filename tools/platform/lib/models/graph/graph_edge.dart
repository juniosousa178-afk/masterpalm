import 'graph_edge_type.dart';

/// Immutable edge in a [ProjectGraph].
class GraphEdge {
  const GraphEdge({
    required this.sourceId,
    required this.targetId,
    required this.type,
    this.context,
    this.metadata = const {},
  });

  final String sourceId;
  final String targetId;
  final GraphEdgeType type;
  final String? context;
  final Map<String, String> metadata;

  String get dedupeKey =>
      '$sourceId|${type.wireName}|$targetId|${context ?? ''}';

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'targetId': targetId,
        'type': type.wireName,
        if (context != null) 'context': context,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    return GraphEdge(
      sourceId: json['sourceId'] as String,
      targetId: json['targetId'] as String,
      type: GraphEdgeTypeX.fromWireName(json['type'] as String),
      context: json['context'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphEdge && dedupeKey == other.dedupeKey;

  @override
  int get hashCode => dedupeKey.hashCode;
}
