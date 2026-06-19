import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/financeiro_lancamento_acao.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_lancamento_edicao_service.dart';

void main() {
  test('gasto fixo gerado finalizado não edita', () {
    final l = LancamentoFinanceiro(
      id: 'gf1',
      lojaId: 'loja',
      descricao: 'Gasto fixo',
      valor: 10,
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: DateTime(2026, 6, 1),
      origem: FinanceiroOrigemLancamento.geradoGastoFixo,
    );
    final acao = FinanceiroLancamentoAcaoResolver.resolver(l);
    expect(acao.podeEditar, isFalse);
    expect(acao.podeExcluir, isFalse);
    expect(FinanceiroLancamentoEdicaoService.podeEditar(l), isFalse);
  });
}
