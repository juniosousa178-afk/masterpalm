/// Result of structural graph validation.
class GraphValidationResult {
  const GraphValidationResult({
    required this.valid,
    this.errors = const [],
    this.warnings = const [],
    this.nodeCount = 0,
    this.edgeCount = 0,
  });

  final bool valid;
  final List<String> errors;
  final List<String> warnings;
  final int nodeCount;
  final int edgeCount;

  Map<String, dynamic> toJson() => {
        'valid': valid,
        'errors': errors,
        'warnings': warnings,
        'nodeCount': nodeCount,
        'edgeCount': edgeCount,
      };
}
