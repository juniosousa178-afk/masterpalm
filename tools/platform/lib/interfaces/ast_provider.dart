/// Contract for accessing AST intelligence data without direct file coupling.
abstract class AstProvider {
  /// Canonical output path for the AST report JSON file.
  String get reportPath;

  /// Raw AST report payload (empty map when report is missing).
  Map<String, dynamic> loadReport();

  /// Persists the AST report to the canonical path.
  void saveReport(Map<String, dynamic> report);

  int? complexityForMethod(String methodKey);

  int? complexityForFile(String relPath);

  int? linesForFile(String relPath);

  List<String> callersForFile(String relPath);

  bool hasImportCycle(List<String> changedFiles);
}
