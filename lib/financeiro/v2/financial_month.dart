import 'brazil_business_date.dart';

/// Mês civil. A identidade é ano + mês, nunca o texto formatado.
class FinancialMonth implements Comparable<FinancialMonth> {
  const FinancialMonth(this.year, this.month)
      : assert(month >= 1 && month <= 12);

  final int year;
  final int month;

  static const monthNamesPt = <String>[
    'Janeiro',
    'Fevereiro',
    'Março',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro',
  ];

  int get orderKey => year * 12 + (month - 1);

  DateTime get start => DateTime(year, month, 1);

  DateTime get endInclusive => DateTime(year, month + 1, 0, 23, 59, 59);

  /// Meia-noite de Brasília do dia 1, em UTC.
  DateTime get startUtcInclusive => DateTime.utc(year, month, 1, 3);

  /// Meia-noite de Brasília do dia 1 do mês seguinte, em UTC.
  DateTime get endExclusiveUtc => DateTime.utc(year, month + 1, 1, 3);

  String get labelPt => '${monthNamesPt[month - 1]} $year';

  String get emptyManualLaunchMessage {
    final nome = monthNamesPt[month - 1].toLowerCase();
    return 'Nenhum lançamento manual em $nome de $year.';
  }

  static FinancialMonth fromInstant(DateTime instant) {
    final day = BrazilBusinessDate.dateOnly(instant);
    return FinancialMonth(day.year, day.month);
  }

  static FinancialMonth fromClock(DateTime now) => FinancialMonth(now.year, now.month);

  bool containsInstant(DateTime instant) {
    final day = BrazilBusinessDate.dateOnly(instant);
    return day.year == year && day.month == month;
  }

  FinancialMonth? previousWithin(FinancialMonthRange range) {
    if (orderKey <= range.earliest.orderKey) return null;
    final cursor = month == 1
        ? FinancialMonth(year - 1, 12)
        : FinancialMonth(year, month - 1);
    return range.contains(cursor) ? cursor : null;
  }

  FinancialMonth? nextWithin(FinancialMonthRange range) {
    if (orderKey >= range.latest.orderKey) return null;
    final cursor = month == 12
        ? FinancialMonth(year + 1, 1)
        : FinancialMonth(year, month + 1);
    return range.contains(cursor) ? cursor : null;
  }

  @override
  int compareTo(FinancialMonth other) => orderKey.compareTo(other.orderKey);

  @override
  bool operator ==(Object other) =>
      other is FinancialMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() =>
      '$year-${month.toString().padLeft(2, '0')}';
}

/// Intervalo inclusivo, em ordem cronológica.
class FinancialMonthRange {
  FinancialMonthRange(this.earliest, this.latest);

  final FinancialMonth earliest;
  final FinancialMonth latest;

  List<FinancialMonth> get months {
    if (earliest.orderKey > latest.orderKey) return [earliest];
    final out = <FinancialMonth>[];
    var year = earliest.year;
    var month = earliest.month;
    while (out.length < 240) {
      final current = FinancialMonth(year, month);
      out.add(current);
      if (current == latest) break;
      if (month == 12) {
        year++;
        month = 1;
      } else {
        month++;
      }
    }
    return out;
  }

  bool contains(FinancialMonth month) =>
      month.orderKey >= earliest.orderKey && month.orderKey <= latest.orderKey;

  /// Monta o intervalo só com meses que alguma fonte confirmou.
  /// O mês corrente entra para a operação ao vivo. Não cria anos anteriores.
  static FinancialMonthRange resolve({
    required List<FinancialMonth> evidence,
    required DateTime now,
  }) {
    final current = FinancialMonth.fromClock(now);
    if (evidence.isEmpty) {
      return FinancialMonthRange(current, current);
    }
    var earliest = evidence.first;
    var latest = evidence.first;
    for (final month in evidence) {
      if (month.orderKey < earliest.orderKey) earliest = month;
      if (month.orderKey > latest.orderKey) latest = month;
    }
    if (current.orderKey > latest.orderKey) latest = current;
    if (current.orderKey < earliest.orderKey) earliest = current;
    return FinancialMonthRange(earliest, latest);
  }
}

/// Período de um mês civil já encerrado. Não vale para o mês corrente nem
/// para um intervalo que cruza meses.
bool periodIsCompletePastMonth({
  required DateTime start,
  required DateTime end,
  required DateTime now,
}) {
  if (start.year != end.year || start.month != end.month) return false;
  if (start.day != 1) return false;
  final lastDay = DateTime(start.year, start.month + 1, 0).day;
  if (end.day != lastDay) return false;
  final current = DateTime(now.year, now.month);
  return DateTime(start.year, start.month).isBefore(current);
}
