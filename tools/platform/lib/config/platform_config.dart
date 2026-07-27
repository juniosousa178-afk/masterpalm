import 'analysis_options.dart';
import 'guardian_options.dart';
import 'history_options.dart';
import '../utils/paths.dart';

/// Central configuration for Platform Core and registered providers.
class PlatformConfig {
  PlatformConfig({
    required this.repoRoot,
    required this.paths,
    this.analysis = const AnalysisOptions(),
    this.guardian = const GuardianOptions(),
    this.history = const HistoryOptions(),
  });

  final String repoRoot;
  final Paths paths;
  final AnalysisOptions analysis;
  final GuardianOptions guardian;
  final HistoryOptions history;

  factory PlatformConfig.forRepo(String repoRoot) {
    return PlatformConfig(
      repoRoot: repoRoot,
      paths: Paths(repoRoot: repoRoot),
    );
  }

  PlatformConfig copyWith({
    String? repoRoot,
    Paths? paths,
    AnalysisOptions? analysis,
    GuardianOptions? guardian,
    HistoryOptions? history,
  }) {
    return PlatformConfig(
      repoRoot: repoRoot ?? this.repoRoot,
      paths: paths ?? this.paths,
      analysis: analysis ?? this.analysis,
      guardian: guardian ?? this.guardian,
      history: history ?? this.history,
    );
  }
}
