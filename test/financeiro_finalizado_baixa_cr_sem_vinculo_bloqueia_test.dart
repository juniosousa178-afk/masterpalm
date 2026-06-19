import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/financeiro_lancamento_acao.dart';
import 'package:master_palm/core/financeiro_lancamento_legacy_resolver.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  test('baixa CR finalizada Giovana sem vínculo bloqueia estorno', () async {
    final l = LancamentoFinanceiro(
      id: 'cr-giovana',
      lojaId: 'loja-x',
      descricao: 'Recebimento — Giovana Almeida',
      valor: 80,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      categoria: 'recebimentos_fiado',
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: DateTime(2026, 6, 1),
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      observacao: 'Conta a receber',
    );

    final acao = FinanceiroLancamentoAcaoResolver.resolver(l);
    expect(acao.ehBaixaCr, isTrue);
    expect(acao.podeEstornar, isFalse);
    expect(acao.bloqueadoEstorno, isTrue);
    expect(acao.podeExcluirSomenteFinanceiro, isTrue);
    expect(acao.mostrarExcluirSomenteFinanceiro, isTrue);
    expect(acao.mostrarEstornar, isFalse);

    final r = await FinanceiroLancamentoExclusaoService.estornarBaixaContaReceber(
      lojaId: 'loja-x',
      lancamento: l,
    );
    expect(r.sucesso, isFalse);
    expect(r.bloqueado, isTrue);
    expect(
      r.mensagemErro,
      FinanceiroLancamentoLegacyResolver.msgEstornoLegadoSemVinculo,
    );
  });
}
