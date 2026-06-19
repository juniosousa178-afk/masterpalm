import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/financeiro_lancamento_acao.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  test('Recebimento — Junho oferece excluir somente financeiro', () {
    final l = LancamentoFinanceiro(
      id: 'junho',
      lojaId: 'loja',
      descricao: 'Recebimento — Junho',
      valor: 8,
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: DateTime(2026, 6, 1),
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      observacao: 'Conta a receber',
      categoria: 'recebimentos_fiado',
      tipo: FinanceiroTipoLancamento.entradaExtra,
    );

    final acao = FinanceiroLancamentoAcaoResolver.resolver(l);
    expect(acao.ehBaixaCr, isTrue);
    expect(acao.podeEstornar, isFalse);
    expect(acao.bloqueadoEstorno, isTrue);
    expect(acao.podeExcluirSomenteFinanceiro, isTrue);
    expect(acao.mostrarExcluirSomenteFinanceiro, isTrue);
    expect(acao.mostrarEstornar, isFalse);

    expect(
      FinanceiroLancamentoExclusaoService.msgModalExcluirSomenteFinanceiroCr,
      contains('excluir somente o lançamento financeiro'),
    );
  });
}
