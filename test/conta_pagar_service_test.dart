import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/conta_pagar_lancamento_vinculo.dart';
import 'package:master_palm/models/conta_pagar.dart';
import 'package:master_palm/models/conta_pagar_constants.dart';
import 'package:master_palm/services/conta_pagar_pagamento_caixa_service.dart';
import 'package:master_palm/services/conta_pagar_service.dart';

void main() {
  group('ContaPagar parcelamento', () {
    test('R\$ 900 em 3x gera valores que somam 900', () {
      final partes =
          ContaPagarPagamentoCaixaService.parcelarValores(900, 3);
      expect(partes.length, 3);
      expect(partes[0], 300);
      expect(partes[1], 300);
      expect(partes[2], 300);
      expect(partes.fold<double>(0, (a, b) => a + b), 900);
    });

    test('centavos restantes distribuídos na primeira parcela', () {
      final partes =
          ContaPagarPagamentoCaixaService.parcelarValores(100, 3);
      expect(partes.fold<double>(0, (a, b) => a + b), closeTo(100, 0.001));
    });
  });

  group('ContaPagar resumo caixa', () {
    test('saldo aberto R\$ 600 após 1ª parcela paga', () {
      final contas = [
        ContaPagar(
          id: 'c1_p1',
          lojaId: 'loja',
          fornecedorId: 1,
          fornecedorNome: 'Forn',
          compraId: 'c1',
          descricao: 'P1',
          valorTotalCompra: 900,
          valorParcela: 300,
          parcelaNumero: 1,
          parcelaTotal: 3,
          dataVencimento: DateTime(2026, 1, 10),
          dataCompra: DateTime(2026, 1, 5),
          status: ContaPagarStatus.pago,
          dataPagamento: DateTime(2026, 1, 15),
        ),
        ContaPagar(
          id: 'c1_p2',
          lojaId: 'loja',
          fornecedorId: 1,
          fornecedorNome: 'Forn',
          compraId: 'c1',
          descricao: 'P2',
          valorTotalCompra: 900,
          valorParcela: 300,
          parcelaNumero: 2,
          parcelaTotal: 3,
          dataVencimento: DateTime(2026, 2, 10),
          dataCompra: DateTime(2026, 1, 5),
        ),
        ContaPagar(
          id: 'c1_p3',
          lojaId: 'loja',
          fornecedorId: 1,
          fornecedorNome: 'Forn',
          compraId: 'c1',
          descricao: 'P3',
          valorTotalCompra: 900,
          valorParcela: 300,
          parcelaNumero: 3,
          parcelaTotal: 3,
          dataVencimento: DateTime(2026, 3, 10),
          dataCompra: DateTime(2026, 1, 5),
        ),
      ];

      final r = ContaPagarService.resumo(
        contas: contas,
        ano: 2026,
        mes: 2,
        visaoCompetencia: false,
      );
      expect(r.totalAberto, 600);
      expect(r.totalPagoNoMes, 0);
    });

    test('pago no mês reflete data de pagamento', () {
      final contas = [
        ContaPagar(
          id: 'c1_p1',
          lojaId: 'loja',
          fornecedorId: 1,
          fornecedorNome: 'Forn',
          compraId: 'c1',
          descricao: 'P1',
          valorTotalCompra: 900,
          valorParcela: 300,
          parcelaNumero: 1,
          parcelaTotal: 3,
          dataVencimento: DateTime(2026, 1, 10),
          dataCompra: DateTime(2026, 1, 5),
          status: ContaPagarStatus.pago,
          dataPagamento: DateTime(2026, 1, 20),
        ),
      ];
      final r = ContaPagarService.resumo(
        contas: contas,
        ano: 2026,
        mes: 1,
      );
      expect(r.totalPagoNoMes, 300);
      expect(r.totalAberto, 0);
    });
  });

  group('Idempotência lançamento', () {
    test('doc id canônico estável por conta', () {
      expect(
        lancamentoFinanceiroDocIdParaContaPagar('abc-123'),
        'mp_cp_abc-123',
      );
      expect(
        referenciaExternaContaPagar(
          contaPagarId: 'abc-123',
          compraId: 'compra-1',
        ),
        'cp_pag:abc-123:compra:compra-1',
      );
    });
  });
}
