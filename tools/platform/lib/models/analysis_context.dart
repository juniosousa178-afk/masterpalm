import 'platform_project.dart';
import 'platform_snapshot.dart';

/// Immutable context passed to analysis providers and engines.
class AnalysisContext {
  const AnalysisContext({
    required this.project,
    required this.snapshot,
    this.changedFiles = const [],
    this.labels = const {},
  });

  final PlatformProject project;
  final PlatformSnapshot snapshot;
  final List<String> changedFiles;
  final Map<String, String> labels;

  AnalysisContext copyWith({
    PlatformProject? project,
    PlatformSnapshot? snapshot,
    List<String>? changedFiles,
    Map<String, String>? labels,
  }) {
    return AnalysisContext(
      project: project ?? this.project,
      snapshot: snapshot ?? this.snapshot,
      changedFiles: changedFiles ?? this.changedFiles,
      labels: labels ?? this.labels,
    );
  }

  Map<String, dynamic> toJson() => {
        'project': project.toJson(),
        'snapshot': snapshot.toJson(),
        'changedFiles': changedFiles,
        if (labels.isNotEmpty) 'labels': labels,
      };
}
