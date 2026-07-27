/// Status of a captured [HistorySnapshot].
enum HistorySnapshotStatus {
  complete,
  partial,
  invalid,
}

extension HistorySnapshotStatusX on HistorySnapshotStatus {
  String get wireName => name;

  static HistorySnapshotStatus fromWireName(String value) {
    return HistorySnapshotStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown HistorySnapshotStatus: $value'),
    );
  }
}
