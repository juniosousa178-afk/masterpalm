import 'analysis_context.dart';

/// Request payload for Guardian analysis via Platform Core.
class GuardianAnalysisRequest {
  const GuardianAnalysisRequest({
    required this.context,
    this.workingTree = false,
    this.staged = false,
    this.base,
    this.head,
    this.files,
    this.simulationOnly = true,
  });

  final AnalysisContext context;
  final bool workingTree;
  final bool staged;
  final String? base;
  final String? head;
  final List<String>? files;
  final bool simulationOnly;
}
