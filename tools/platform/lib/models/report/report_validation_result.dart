/// Result of report document validation.
class ReportValidationResult {
  const ReportValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
    this.sectionCount = 0,
    this.blockCount = 0,
    this.findingCount = 0,
  });

  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  final int sectionCount;
  final int blockCount;
  final int findingCount;

  Map<String, dynamic> toJson() => {
        'isValid': isValid,
        'errors': errors,
        'warnings': warnings,
        'sectionCount': sectionCount,
        'blockCount': blockCount,
        'findingCount': findingCount,
      };
}
