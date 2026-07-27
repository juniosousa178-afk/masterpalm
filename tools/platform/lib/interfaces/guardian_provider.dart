import '../models/analysis_result.dart';
import '../models/guardian_analysis_request.dart';

/// Contract for Guardian analysis exposed through Platform Core.
abstract class GuardianProvider {
  Future<AnalysisResult> analyze(GuardianAnalysisRequest request);
}
