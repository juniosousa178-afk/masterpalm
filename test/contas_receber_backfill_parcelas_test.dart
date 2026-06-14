// Parcelas no backfill: cr_{vendaId}_p1, p2, ...

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/conta_receber_identity.dart';
import 'package:master_palm/core/conta_receber_venda_vinculo.dart';
import 'package:master_palm/models/venda.dart';

void main() {
  const lojaId = 'loja-parcelas-backfill';
  const vendaId = 'venda-parcelas-2x25';

  test('montarContasReceberFromVenda divide saldo em N parcelas', () {
    final venda = Venda(
      clienteNome: 'Junio',
      produtosDescricao: 'Prod',
      quantidade: 1,
      preco: 100,
      total: 100,
      formasPagamento:
          'Pagamento Pix: R\$ 50,00\nFiado - R\$ 50,00. Vencimento: 15/07/2026 Parcelas fiado: 2. Intervalo: 30 dias.',
      data: DateTime(2026, 6, 14),
      tamanho: '',
      vendedor: 'Loja',
      frete: 0,
      desconto: 0,
      observacao: '',
      pagamentoDinheiro: 0,
      pagamentoPix: 50,
      pagamentoCartao: 0,
      lojaId: lojaId,
      idFirebase: vendaId,
    );

    final contas = montarContasReceberFromVenda(venda: venda, lojaId: lojaId);
    expect(contas.length, 2);
    expect(contas[0].valor, closeTo(25, 0.01));
    expect(contas[1].valor, closeTo(25, 0.01));
    expect(resolveContaReceberDocId(contas[0]), 'cr_${vendaId}_p1');
    expect(resolveContaReceberDocId(contas[1]), 'cr_${vendaId}_p2');
    expect(contas[0].parcelaTotal, 2);
    expect(contas[1].parcelaNumero, 2);
  });

  test('vendaPossuiSaldoAReceber detecta mista sem palavra fiado no texto', () {
    final venda = Venda(
      clienteNome: 'Junio',
      produtosDescricao: 'Prod',
      quantidade: 1,
      preco: 100,
      total: 100,
      formasPagamento: 'Pagamento Pix: R\$ 50,00',
      data: DateTime(2026, 6, 14),
      tamanho: '',
      vendedor: 'Loja',
      frete: 0,
      desconto: 0,
      observacao: '',
      pagamentoDinheiro: 0,
      pagamentoPix: 50,
      pagamentoCartao: 0,
      lojaId: lojaId,
      idFirebase: vendaId,
    );
    expect(vendaPossuiSaldoAReceber(venda), isTrue);
    expect(valorAReceberDaVenda(venda), closeTo(50, 0.01));
  });
}
