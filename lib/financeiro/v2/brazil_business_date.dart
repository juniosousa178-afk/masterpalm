/// Data de negócio no fuso de Brasília (UTC−3, sem horário de verão).
///
/// Instantes UTC são convertidos. DateTime não-UTC já é relógio de parede
/// gravado pelo app e mantém o dia civil dos campos.
abstract final class BrazilBusinessDate {
  static const Duration brasiliaOffset = Duration(hours: -3);

  static DateTime dateOnly(DateTime instant) {
    final wall = instant.isUtc ? instant.add(brasiliaOffset) : instant;
    return DateTime(wall.year, wall.month, wall.day);
  }

  static bool inInclusiveRange({
    required DateTime instant,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    final day = dateOnly(instant);
    final start = dateOnly(periodStart);
    final end = dateOnly(periodEnd);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  static bool isBeforeDay(DateTime dueAt, DateTime today) {
    return dateOnly(dueAt).isBefore(dateOnly(today));
  }
}
