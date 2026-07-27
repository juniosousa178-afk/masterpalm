/// Cross-module change impact descriptor.
class ChangeImpact {
  const ChangeImpact({
    required this.domains,
    this.affectedFiles = const [],
    this.affectedMethods = const [],
    this.relatedServices = const [],
    this.metadata = const {},
  });

  final List<String> domains;
  final List<String> affectedFiles;
  final List<String> affectedMethods;
  final List<String> relatedServices;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'domains': domains,
        'affectedFiles': affectedFiles,
        'affectedMethods': affectedMethods,
        'relatedServices': relatedServices,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };
}
