import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/financeiro_lancamento_duplicidade_resolver.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-sem-nome';
  final data = DateTime(2026, 6, 1);

  final a = LancamentoFinanceiro(
    id: 'manual-a',
    lojaId: lojaId,
    descricao: 'Recebimento — Rafaela Abelha',
    valor: 99.90,
    status: FinanceiroStatusLancamento.pago,
    dataLancamento: data,
    dataPagamento: data,
    origem: FinanceiroOrigemLancamento.contaReceberFiado,
    formaPagamento: 'Pix',
  );

  final b = LancamentoFinanceiro(
    id: 'manual-b',
    lojaId: lojaId,
    descricao: 'Recebimento — Rafaela Abelha',
    valor: 50.0,
    status: FinanceiroStatusLancamento.pago,
    dataLancamento: data,
    dataPagamento: data,
    origem: FinanceiroOrigemLancamento.contaReceberFiado,
    formaPagamento: 'Pix',
  );

  test('não libera excluir duplicado apenas por nome da cliente', () {
    final diag = FinanceiroLancamentoDuplicidadeResolver.diagnosticar(
      alvo: a,
      lancamentos: [a, b],
      lojaId: lojaId,
    );

    expect(diag.podeExcluirDuplicado, isFalse);
    expect(diag.confianca, isNot(FinanceiroDuplicidadeConfianca.segura));

    final acao = FinanceiroLancamentoExclusaoService.acaoParaUi(
      a,
      lojaId: lojaId,
      lancamentosLoja: [a, b],
    );
    expect(acao.mostrarExcluirDuplicado, isFalse);
  });
}
