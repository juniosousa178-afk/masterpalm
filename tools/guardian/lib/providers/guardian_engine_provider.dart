import 'package:masterpalm_platform/masterpalm_platform.dart';

import '../diff_analyzer.dart';
import '../guardian_engine.dart';
import '../mappers/guardian_platform_mappers.dart';
import '../models/guardian_result.dart';

/// Platform [GuardianProvider] implementation delegating to [GuardianEngine].
class GuardianEngineProvider implements GuardianProvider {
  GuardianEngineProvider({required this.engine});

  final GuardianEngine engine;

  @override
  Future<AnalysisResult> analyze(GuardianAnalysisRequest request) async {
    final guardianResult = await analyzeGuardian(request);
    return GuardianPlatformMappers.toAnalysisResult(guardianResult);
  }

  /// Runs Guardian analysis and returns the native result model.
  Future<GuardianResult> analyzeGuardian(
    GuardianAnalysisRequest request, {
    DiffAnalysis? injectedDiff,
    bool g009EvidenceSatisfied = false,
    String? explicitBaseHead,
  }) {
    return engine.analyze(
      workingTree: request.workingTree,
      staged: request.staged,
      base: request.base,
      head: request.head,
      files: request.files ?? request.context.changedFiles,
      simulationOnly: request.simulationOnly,
      injectedDiff: injectedDiff,
      g009EvidenceSatisfied: g009EvidenceSatisfied,
      explicitBaseHead: explicitBaseHead,
    );
  }
}
