import 'graph_node_type.dart';

/// Immutable node in a [ProjectGraph].
class GraphNode {
  const GraphNode({
    required this.id,
    required this.type,
    required this.label,
    this.metadata = const {},
  });

  final String id;
  final GraphNodeType type;
  final String label;
  final Map<String, String> metadata;

  GraphNode copyWith({
    String? id,
    GraphNodeType? type,
    String? label,
    Map<String, String>? metadata,
  }) {
    return GraphNode(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.wireName,
        'label': label,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    return GraphNode(
      id: json['id'] as String,
      type: GraphNodeTypeX.fromWireName(json['type'] as String),
      label: json['label'] as String,
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphNode &&
          id == other.id &&
          type == other.type &&
          label == other.label;

  @override
  int get hashCode => Object.hash(id, type, label);
}
