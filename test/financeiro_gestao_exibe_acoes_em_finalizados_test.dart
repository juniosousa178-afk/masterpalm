import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/financeiro_lancamento_acao.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  test('finalizado manual mostra editar e excluir', () {
    final l = LancamentoFinanceiro(
      id: 'm1',
      lojaId: 'loja',
      descricao: 'Manual',
      valor: 1,
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: DateTime(2026, 6, 1),
    );
    final acao = FinanceiroLancamentoExclusaoService.acaoParaUi(l);
    expect(acao.mostrarEditar, isTrue);
    expect(acao.mostrarExcluir, isTrue);
    expect(acao.mostrarEstornar, isFalse);
  });

  test('finalizado CR sem vínculo mostra excluir somente financeiro', () {
    final l = LancamentoFinanceiro(
      id: 'cr1',
      lojaId: 'loja',
      descricao: 'Recebimento — Cliente',
      valor: 1,
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: DateTime(2026, 6, 1),
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      observacao: 'Conta a receber',
    );
    final acao = FinanceiroLancamentoAcaoResolver.resolver(l);
    expect(acao.mostrarEstornar, isFalse);
    expect(acao.mostrarExcluirSomenteFinanceiro, isTrue);
    expect(acao.mostrarExcluir, isFalse);
  });
}
