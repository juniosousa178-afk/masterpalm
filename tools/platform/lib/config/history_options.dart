/// Options reserved for future History Engine integration.
class HistoryOptions {
  const HistoryOptions({
    this.enabled = false,
    this.retentionDays = 90,
  });

  final bool enabled;
  final int retentionDays;

  HistoryOptions copyWith({
    bool? enabled,
    int? retentionDays,
  }) {
    return HistoryOptions(
      enabled: enabled ?? this.enabled,
      retentionDays: retentionDays ?? this.retentionDays,
    );
  }
}
