/// Options for AST and structural analysis providers.
class AnalysisOptions {
  const AnalysisOptions({
    this.cacheAstReport = true,
    this.strictMode = false,
  });

  final bool cacheAstReport;
  final bool strictMode;

  AnalysisOptions copyWith({
    bool? cacheAstReport,
    bool? strictMode,
  }) {
    return AnalysisOptions(
      cacheAstReport: cacheAstReport ?? this.cacheAstReport,
      strictMode: strictMode ?? this.strictMode,
    );
  }
}
