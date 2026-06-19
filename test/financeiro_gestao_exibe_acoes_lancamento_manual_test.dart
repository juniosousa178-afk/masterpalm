import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/financeiro_lancamento_acao.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  test('manual pago exibe editar e excluir', () {
    final l = LancamentoFinanceiro(
      id: 'm',
      lojaId: 'loja',
      descricao: 'X',
      valor: 1,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: DateTime(2026, 6, 1),
    );
    final a = FinanceiroLancamentoExclusaoService.acaoParaUi(l);
    expect(a.mostrarEditar, isTrue);
    expect(a.mostrarExcluir, isTrue);
  });
}
