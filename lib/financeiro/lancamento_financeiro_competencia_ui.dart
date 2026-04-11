// lib/financeiro/lancamento_financeiro_competencia_ui.dart
// Helpers de UI — competência × pagamento (sem alterar KPIs do FinanceiroService).

import '../models/lancamento_financeiro.dart';
import 'financeiro_constants.dart';

abstract final class LancamentoFinanceiroCompetenciaUi {
  LancamentoFinanceiroCompetenciaUi._();

  static bool competenciaNoMes(LancamentoFinanceiro l, int ano, int mes) =>
      l.competenciaAno == ano && l.competenciaMes == mes;

  /// Data usada como “pagamento” para comparar com competência (lançamento se não houver pgto).
  static DateTime dataParaCompararPagamento(LancamentoFinanceiro l) =>
      l.dataPagamento ?? l.dataLancamento;

  /// Linha curta para subtítulo de lista (uma linha).
  static String subtituloCompetenciaPagamento(
    LancamentoFinanceiro l,
    String Function(DateTime d) fmtMesAno,
  ) {
    final c = fmtMesAno(DateTime(l.competenciaAno, l.competenciaMes));
    if (l.status == FinanceiroStatusLancamento.pendente) {
      return 'Competência: $c · Pendente';
    }
    final dp = dataParaCompararPagamento(l);
    final p = fmtMesAno(dp);
    if (l.competenciaAno == dp.year && l.competenciaMes == dp.month) {
      return 'Competência: $c · Pago em $p';
    }
    return 'Competência: $c · Pago em: $p';
  }

  static int contarPendentesCompetenciaMes(
    Iterable<LancamentoFinanceiro> todos,
    String lojaId,
    int ano,
    int mes,
  ) {
    final id = lojaId.trim();
    var n = 0;
    for (final l in todos) {
      if (l.lojaId != id) continue;
      if (l.status != FinanceiroStatusLancamento.pendente) continue;
      if (!competenciaNoMes(l, ano, mes)) continue;
      n++;
    }
    return n;
  }

  /// Pagos cuja **data de pagamento** (ou lançamento) cai no mês, mas competência é outro mês/ano.
  static int contarPagosNoMesComCompetenciaOutra(
    Iterable<LancamentoFinanceiro> todos,
    String lojaId,
    int ano,
    int mes,
    DateTime inicioMes,
    DateTime fimMes,
  ) {
    final id = lojaId.trim();
    var n = 0;
    for (final l in todos) {
      if (l.lojaId != id) continue;
      if (l.status != FinanceiroStatusLancamento.pago) continue;
      final dp = dataParaCompararPagamento(l);
      if (dp.isBefore(inicioMes) || dp.isAfter(fimMes)) continue;
      if (l.competenciaAno == dp.year && l.competenciaMes == dp.month) continue;
      n++;
    }
    return n;
  }
}
