/// Represents a MasterPalm repository under analysis.
class PlatformProject {
  const PlatformProject({
    required this.rootPath,
    required this.name,
    this.version,
    this.metadata = const {},
  });

  final String rootPath;
  final String name;
  final String? version;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'rootPath': rootPath,
        'name': name,
        if (version != null) 'version': version,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PlatformProject.fromJson(Map<String, dynamic> json) {
    return PlatformProject(
      rootPath: json['rootPath'] as String,
      name: json['name'] as String,
      version: json['version'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}
