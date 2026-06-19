import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/financeiro_lancamento_acao.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';

void main() {
  test('baixa CR não edita', () {
    final l = LancamentoFinanceiro(
      id: 'cr',
      lojaId: 'loja',
      descricao: 'Recebimento — X',
      valor: 1,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: DateTime(2026, 6, 1),
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      observacao: 'Conta a receber',
    );
    final a = FinanceiroLancamentoAcaoResolver.resolver(l);
    expect(a.podeEditar, isFalse);
    expect(a.mostrarEstornar, isFalse);
    expect(a.mostrarExcluirSomenteFinanceiro, isTrue);
  });
}
