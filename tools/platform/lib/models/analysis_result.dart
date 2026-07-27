/// Generic analysis outcome shared across platform modules.
class AnalysisResult {
  const AnalysisResult({
    required this.success,
    required this.summary,
    this.details = const {},
    this.errors = const [],
    this.warnings = const [],
  });

  final bool success;
  final String summary;
  final Map<String, dynamic> details;
  final List<String> errors;
  final List<String> warnings;

  Map<String, dynamic> toJson() => {
        'success': success,
        'summary': summary,
        if (details.isNotEmpty) 'details': details,
        if (errors.isNotEmpty) 'errors': errors,
        if (warnings.isNotEmpty) 'warnings': warnings,
      };
}
