import '../utils/date_helpers.dart';

/// Immutable point-in-time view of platform state for an analysis run.
class PlatformSnapshot {
  const PlatformSnapshot({
    required this.id,
    required this.createdAt,
    this.gitRef,
    this.astReportVersion,
    this.tags = const [],
  });

  final String id;
  final DateTime createdAt;
  final String? gitRef;
  final String? astReportVersion;
  final List<String> tags;

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': DateHelpers.toIso8601(createdAt),
        if (gitRef != null) 'gitRef': gitRef,
        if (astReportVersion != null) 'astReportVersion': astReportVersion,
        if (tags.isNotEmpty) 'tags': tags,
      };

  factory PlatformSnapshot.fresh({String? gitRef}) {
    final now = DateHelpers.utcNow();
    return PlatformSnapshot(
      id: 'snap_${DateHelpers.fileSafeTimestamp(now)}',
      createdAt: now,
      gitRef: gitRef,
    );
  }
}
