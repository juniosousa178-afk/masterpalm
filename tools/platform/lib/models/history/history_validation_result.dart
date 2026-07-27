import 'history_compatibility.dart';

/// Validation result for [HistorySnapshot].
class HistoryValidationResult {
  const HistoryValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
    required this.artifactCount,
    required this.validArtifactCount,
    required this.invalidArtifactCount,
    required this.compatibilityStatus,
  });

  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  final int artifactCount;
  final int validArtifactCount;
  final int invalidArtifactCount;
  final HistoryCompatibilityStatus compatibilityStatus;
}
