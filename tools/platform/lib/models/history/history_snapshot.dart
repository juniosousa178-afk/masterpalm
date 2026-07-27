import 'history_artifact.dart';
import 'history_metadata.dart';

/// Immutable historical snapshot of platform artifacts.
class HistorySnapshot {
  const HistorySnapshot({
    required this.metadata,
    required this.artifacts,
  });

  final HistoryMetadata metadata;
  final List<HistoryArtifact> artifacts;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'artifacts': artifacts.map((a) => a.toJson()).toList(),
      };

  factory HistorySnapshot.fromJson(Map<String, dynamic> json) {
    return HistorySnapshot(
      metadata: HistoryMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      artifacts: (json['artifacts'] as List<dynamic>)
          .map((e) => HistoryArtifact.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'metadata': metadata.toComparableJson(),
        'artifacts': artifacts.map((a) => a.toJson()).toList(),
      };
}
