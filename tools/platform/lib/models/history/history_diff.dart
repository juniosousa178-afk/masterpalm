import 'history_change_type.dart';
import 'history_compatibility.dart';

/// Single neutral change between two history snapshots.
class HistoryChange {
  const HistoryChange({
    required this.changeType,
    required this.category,
    required this.subjectId,
    this.description,
    this.previousValue,
    this.currentValue,
    this.absoluteDelta,
    this.relativeDelta,
    this.metadata = const {},
  });

  final HistoryChangeType changeType;
  final HistoryChangeCategory category;
  final String subjectId;
  final String? description;
  final String? previousValue;
  final String? currentValue;
  final double? absoluteDelta;
  final double? relativeDelta;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'changeType': changeType.wireName,
        'category': category.wireName,
        'subjectId': subjectId,
        if (description != null) 'description': description,
        if (previousValue != null) 'previousValue': previousValue,
        if (currentValue != null) 'currentValue': currentValue,
        if (absoluteDelta != null) 'absoluteDelta': absoluteDelta,
        if (relativeDelta != null) 'relativeDelta': relativeDelta,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory HistoryChange.fromJson(Map<String, dynamic> json) {
    return HistoryChange(
      changeType: HistoryChangeTypeX.fromWireName(json['changeType'] as String),
      category: HistoryChangeCategoryX.fromWireName(json['category'] as String),
      subjectId: json['subjectId'] as String,
      description: json['description'] as String?,
      previousValue: json['previousValue'] as String?,
      currentValue: json['currentValue'] as String?,
      absoluteDelta: (json['absoluteDelta'] as num?)?.toDouble(),
      relativeDelta: (json['relativeDelta'] as num?)?.toDouble(),
      metadata: (json['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

/// Summary counts for a [HistoryDiff].
class HistoryDiffSummary {
  const HistoryDiffSummary({
    required this.totalChanges,
    required this.addedCount,
    required this.removedCount,
    required this.changedCount,
    required this.unchangedCount,
  });

  final int totalChanges;
  final int addedCount;
  final int removedCount;
  final int changedCount;
  final int unchangedCount;

  Map<String, dynamic> toJson() => {
        'totalChanges': totalChanges,
        'addedCount': addedCount,
        'removedCount': removedCount,
        'changedCount': changedCount,
        'unchangedCount': unchangedCount,
      };

  factory HistoryDiffSummary.fromJson(Map<String, dynamic> json) {
    return HistoryDiffSummary(
      totalChanges: json['totalChanges'] as int? ?? 0,
      addedCount: json['addedCount'] as int? ?? 0,
      removedCount: json['removedCount'] as int? ?? 0,
      changedCount: json['changedCount'] as int? ?? 0,
      unchangedCount: json['unchangedCount'] as int? ?? 0,
    );
  }
}

/// Structural diff between two history snapshots.
class HistoryDiff {
  const HistoryDiff({
    required this.fromSnapshotId,
    required this.toSnapshotId,
    required this.compatibility,
    required this.changes,
    required this.summary,
    this.warnings = const [],
    this.comparedArtifactTypes = const [],
  });

  final String fromSnapshotId;
  final String toSnapshotId;
  final HistoryCompatibility compatibility;
  final List<HistoryChange> changes;
  final HistoryDiffSummary summary;
  final List<String> warnings;
  final List<String> comparedArtifactTypes;

  Map<String, dynamic> toJson() => {
        'fromSnapshotId': fromSnapshotId,
        'toSnapshotId': toSnapshotId,
        'compatibility': compatibility.toJson(),
        'changes': changes.map((c) => c.toJson()).toList(),
        'summary': summary.toJson(),
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (comparedArtifactTypes.isNotEmpty)
          'comparedArtifactTypes': comparedArtifactTypes,
      };

  factory HistoryDiff.fromJson(Map<String, dynamic> json) {
    return HistoryDiff(
      fromSnapshotId: json['fromSnapshotId'] as String,
      toSnapshotId: json['toSnapshotId'] as String,
      compatibility: HistoryCompatibility.fromJson(
        json['compatibility'] as Map<String, dynamic>,
      ),
      changes: (json['changes'] as List<dynamic>)
          .map((e) => HistoryChange.fromJson(e as Map<String, dynamic>))
          .toList(),
      summary: HistoryDiffSummary.fromJson(
        json['summary'] as Map<String, dynamic>,
      ),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      comparedArtifactTypes:
          (json['comparedArtifactTypes'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
    );
  }
}
