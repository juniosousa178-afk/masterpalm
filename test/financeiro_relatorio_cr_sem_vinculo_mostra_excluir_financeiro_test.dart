import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  test('Relatório: CR sem vínculo permite excluir somente financeiro', () {
    final l = LancamentoFinanceiro(
      id: 'rel-junho',
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

    final info = FinanceiroLancamentoExclusaoService.infoLegado(l, lojaId: 'loja');
    expect(info.ehBaixaCr, isTrue);
    expect(info.vinculoCrSeguro, isFalse);

    final acao = FinanceiroLancamentoExclusaoService.acaoParaUi(l, lojaId: 'loja');
    expect(acao.podeExcluirSomenteFinanceiro, isTrue);
    expect(acao.podeEstornar, isFalse);
  });
}
