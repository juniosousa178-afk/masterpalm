// Filtro de exibição da lista de lançamentos já gravada.
// Não grava, não muda status e não entra no cálculo do dashboard.

import 'financeiro_constants.dart';

enum LancamentoListaRecorte { todos, entradas, saidas, pendentes, pagos }

class LancamentoListaConsulta {
  const LancamentoListaConsulta({
    this.recorte = LancamentoListaRecorte.todos,
    this.categoria = '',
    this.periodoInicio,
    this.periodoFimExclusivo,
  });

  final LancamentoListaRecorte recorte;
  final String categoria;
  final DateTime? periodoInicio;
  final DateTime? periodoFimExclusivo;

  bool aceita({
    required String tipo,
    required double valor,
    required String status,
    required String categoria,
    required DateTime data,
  }) {
    final categoriaFiltro = this.categoria.trim();
    if (categoriaFiltro.isNotEmpty && categoria.trim() != categoriaFiltro) {
      return false;
    }
    if (!_noPeriodo(data)) return false;
    switch (recorte) {
      case LancamentoListaRecorte.todos:
        return true;
      case LancamentoListaRecorte.entradas:
        return lancamentoEhEntrada(tipo: tipo, valor: valor);
      case LancamentoListaRecorte.saidas:
        return !lancamentoEhEntrada(tipo: tipo, valor: valor);
      case LancamentoListaRecorte.pendentes:
        return status.trim().toLowerCase() ==
            FinanceiroStatusLancamento.pendente;
      case LancamentoListaRecorte.pagos:
        return FinanceiroStatusLancamento.statusLiquidado(status);
    }
  }

  bool _noPeriodo(DateTime data) {
    final dia = DateTime(data.year, data.month, data.day);
    final inicio = periodoInicio;
    if (inicio != null) {
      final s = DateTime(inicio.year, inicio.month, inicio.day);
      if (dia.isBefore(s)) return false;
    }
    final fim = periodoFimExclusivo;
    if (fim != null) {
      final e = DateTime(fim.year, fim.month, fim.day);
      if (!dia.isBefore(e)) return false;
    }
    return true;
  }
}

/// Entrada que não é venda. Ajuste negativo continua saída.
bool lancamentoEhEntrada({required String tipo, required double valor}) {
  if (tipo == FinanceiroTipoLancamento.entradaExtra) return true;
  if (tipo == FinanceiroTipoLancamento.ajusteFinanceiro && valor > 0) {
    return true;
  }
  return false;
}
