/// Compatibility status between historical artifacts or snapshots.
enum HistoryCompatibilityStatus {
  compatible,
  partiallyCompatible,
  incompatible,
  unknown,
}

/// Compatibility assessment for history comparison.
class HistoryCompatibility {
  const HistoryCompatibility({
    required this.status,
    this.reasons = const [],
  });

  final HistoryCompatibilityStatus status;
  final List<String> reasons;

  Map<String, dynamic> toJson() => {
        'status': status.name,
        if (reasons.isNotEmpty) 'reasons': reasons,
      };

  factory HistoryCompatibility.fromJson(Map<String, dynamic> json) {
    return HistoryCompatibility(
      status: HistoryCompatibilityStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => HistoryCompatibilityStatus.unknown,
      ),
      reasons: (json['reasons'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

extension HistoryCompatibilityStatusX on HistoryCompatibilityStatus {
  String get wireName => name;
}
