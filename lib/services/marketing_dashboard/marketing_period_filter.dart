// M3.8 Sprint 2 — filtro de período para dashboards de marketing (somente leitura).

enum MarketingPeriodFilter {
  hoje,
  semana,
  mes,
  ano,
  todo,
}

extension MarketingPeriodFilterX on MarketingPeriodFilter {
  String get label {
    switch (this) {
      case MarketingPeriodFilter.hoje:
        return 'Hoje';
      case MarketingPeriodFilter.semana:
        return 'Semana';
      case MarketingPeriodFilter.mes:
        return 'Mês';
      case MarketingPeriodFilter.ano:
        return 'Ano';
      case MarketingPeriodFilter.todo:
        return 'Todo período';
    }
  }
}

class MarketingPeriodRange {
  const MarketingPeriodRange({required this.inicio, required this.fimExclusivo});

  final DateTime inicio;
  final DateTime fimExclusivo;

  /// [todo] usa início Epoch e fim exclusivo = agora+1d para incluir tudo.
  static MarketingPeriodRange resolve(
    MarketingPeriodFilter filter, {
    DateTime? agora,
  }) {
    final now = agora ?? DateTime.now();
    final hoje = DateTime(now.year, now.month, now.day);
    switch (filter) {
      case MarketingPeriodFilter.hoje:
        return MarketingPeriodRange(
          inicio: hoje,
          fimExclusivo: hoje.add(const Duration(days: 1)),
        );
      case MarketingPeriodFilter.semana:
        final inicioSemana = hoje.subtract(Duration(days: hoje.weekday - 1));
        return MarketingPeriodRange(
          inicio: inicioSemana,
          fimExclusivo: hoje.add(const Duration(days: 1)),
        );
      case MarketingPeriodFilter.mes:
        return MarketingPeriodRange(
          inicio: DateTime(now.year, now.month, 1),
          fimExclusivo: DateTime(now.year, now.month + 1, 1),
        );
      case MarketingPeriodFilter.ano:
        return MarketingPeriodRange(
          inicio: DateTime(now.year, 1, 1),
          fimExclusivo: DateTime(now.year + 1, 1, 1),
        );
      case MarketingPeriodFilter.todo:
        return MarketingPeriodRange(
          inicio: DateTime.fromMillisecondsSinceEpoch(0),
          fimExclusivo: hoje.add(const Duration(days: 1)),
        );
    }
  }

  bool contains(DateTime? dt) {
    if (dt == null) return false;
    return !dt.isBefore(inicio) && dt.isBefore(fimExclusivo);
  }
}
