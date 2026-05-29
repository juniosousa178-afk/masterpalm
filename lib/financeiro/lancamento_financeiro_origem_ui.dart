// Rótulos de UI para lançamentos gerados automaticamente (não altera cálculos).

import '../core/conta_pagar_lancamento_vinculo.dart';
import '../core/conta_receber_lancamento_vinculo.dart';
import '../models/lancamento_financeiro.dart';
import 'financeiro_constants.dart';

/// Texto do chip na lista de lançamentos, ou null se manual/outro.
String? chipOrigemAutomaticaLancamento(LancamentoFinanceiro l) {
  if (lancamentoVinculadoAContaPagar(l)) {
    return 'Gerado por Conta a Pagar';
  }
  if (lancamentoVinculadoAContaReceber(l)) {
    return 'Gerado por Conta a Receber';
  }
  if (l.origem == FinanceiroOrigemLancamento.geradoGastoFixo) {
    return 'Gerado por gasto fixo';
  }
  return null;
}
