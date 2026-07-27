/// Metadata describing a [ProjectGraph] snapshot.
class GraphMetadata {
  const GraphMetadata({
    required this.graphSchemaVersion,
    required this.source,
    this.projectRoot,
    this.generatedAt,
    this.nodeCount = 0,
    this.edgeCount = 0,
    this.extra = const {},
  });

  static const int currentSchemaVersion = 1;

  final int graphSchemaVersion;
  final String source;
  final String? projectRoot;
  final String? generatedAt;
  final int nodeCount;
  final int edgeCount;
  final Map<String, String> extra;

  GraphMetadata copyWith({
    int? graphSchemaVersion,
    String? source,
    String? projectRoot,
    String? generatedAt,
    int? nodeCount,
    int? edgeCount,
    Map<String, String>? extra,
  }) {
    return GraphMetadata(
      graphSchemaVersion: graphSchemaVersion ?? this.graphSchemaVersion,
      source: source ?? this.source,
      projectRoot: projectRoot ?? this.projectRoot,
      generatedAt: generatedAt ?? this.generatedAt,
      nodeCount: nodeCount ?? this.nodeCount,
      edgeCount: edgeCount ?? this.edgeCount,
      extra: extra ?? this.extra,
    );
  }

  Map<String, dynamic> toJson() => {
        'graphSchemaVersion': graphSchemaVersion,
        'source': source,
        if (projectRoot != null) 'projectRoot': projectRoot,
        if (generatedAt != null) 'generatedAt': generatedAt,
        'nodeCount': nodeCount,
        'edgeCount': edgeCount,
        if (extra.isNotEmpty) 'extra': extra,
      };

  factory GraphMetadata.fromJson(Map<String, dynamic> json) {
    return GraphMetadata(
      graphSchemaVersion: json['graphSchemaVersion'] as int? ?? 1,
      source: json['source'] as String? ?? 'unknown',
      projectRoot: json['projectRoot'] as String?,
      generatedAt: json['generatedAt'] as String?,
      nodeCount: json['nodeCount'] as int? ?? 0,
      edgeCount: json['edgeCount'] as int? ?? 0,
      extra: (json['extra'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}
