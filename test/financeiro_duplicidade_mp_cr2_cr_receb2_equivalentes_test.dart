import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/core/financeiro_lancamento_duplicidade_resolver.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';

void main() {
  const lojaId = 'loja-equiv';
  const vendaId = 'venda-equiv';
  const stable = '${vendaId}_p1';
  const valor = 99.90;
  final data = DateTime(2026, 6, 8);

  final conta = ContaReceber(
    lojaId: lojaId,
    clienteNome: 'Rafaela Abelha',
    valor: valor,
    valorOriginal: valor,
    dataVencimento: DateTime(2026, 7, 1),
    dataVenda: DateTime(2026, 6, 1),
    vendaIdFirebase: vendaId,
    parcelaNumero: 1,
    idFirebase: vendaId,
    pago: true,
    valorPago: valor,
  );

  final correto = LancamentoFinanceiro(
    id: lancamentoFinanceiroDocIdParaContaReceberStable(
      contaReceberStableId: stable,
      parcelaNumero: 1,
      valor: valor,
      dataRecebimento: data,
    ),
    lojaId: lojaId,
    descricao: 'Recebimento — Rafaela Abelha',
    valor: valor,
    status: FinanceiroStatusLancamento.pago,
    dataLancamento: data,
    dataPagamento: data,
    origem: FinanceiroOrigemLancamento.contaReceberFiado,
    formaPagamento: 'Pix',
    referenciaExterna: referenciaExternaContaReceberStable(
      contaReceberStableId: stable,
      parcelaNumero: 1,
      valor: valor,
      dataRecebimento: data,
    ),
  );

  final duplicado = LancamentoFinanceiro(
    id: 'mp_cr2_${vendaId}__bx_equiv',
    lojaId: lojaId,
    descricao: 'Recebimento — Rafaela Abelha',
    valor: valor,
    status: FinanceiroStatusLancamento.pago,
    dataLancamento: data,
    dataPagamento: data,
    origem: FinanceiroOrigemLancamento.contaReceberFiado,
    formaPagamento: 'Cartão',
    observacao: 'pull firestore',
    referenciaExterna: referenciaExternaContaReceberFirestore(
      contaReceberDocId: vendaId,
      baixaId: 'bx_equiv',
    ),
  );

  test('mp_cr2 firestore e cr_receb2 estável são equivalentes com conta resolvida', () {
    expect(
      FinanceiroLancamentoDuplicidadeResolver.saoMesmaBaixaContaReceber(
        correto,
        duplicado,
        contas: [conta],
        lojaId: lojaId,
      ),
      isTrue,
    );

    final diag = FinanceiroLancamentoDuplicidadeResolver.diagnosticar(
      alvo: duplicado,
      lancamentos: [correto, duplicado],
      contas: [conta],
      lojaId: lojaId,
    );

    expect(diag.confianca, FinanceiroDuplicidadeConfianca.segura);
    expect(diag.podeExcluirDuplicado, isTrue);
    expect(diag.lancamentoAManter?.id, correto.id);
  });
}
