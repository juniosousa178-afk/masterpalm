import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/compra_fornecedor.dart';
import 'package:master_palm/models/compra_fornecedor_constants.dart';
import 'package:master_palm/models/compra_fornecedor_item.dart';
import 'package:master_palm/services/conta_pagar_service.dart';

void main() {
  CompraFornecedor _compraBase({
    String tipo = CompraFornecedorTipo.produtosEstoque,
    double valorInformado = 0,
    List<CompraFornecedorItem>? itens,
    double frete = 0,
    double desconto = 0,
    double outras = 0,
  }) {
    return CompraFornecedor(
      id: 'c-test',
      lojaId: 'loja',
      fornecedorHiveKey: 1,
      fornecedorNome: 'Forn Teste',
      dataCompra: DateTime(2026, 1, 5),
      tipoCompra: tipo,
      valorInformado: valorInformado,
      frete: frete,
      desconto: desconto,
      outrasDespesas: outras,
      itens: itens,
    );
  }

  group('CompraFornecedorTipo', () {
    test('compras antigas assumem produtos_estoque', () {
      final c = CompraFornecedor(
        id: 'legado',
        lojaId: 'loja',
        fornecedorHiveKey: 1,
        fornecedorNome: 'X',
        dataCompra: DateTime(2026, 1, 1),
      );
      expect(c.tipoCompra, CompraFornecedorTipo.produtosEstoque);
      expect(c.movimentaEstoque, isTrue);
      expect(CompraFornecedorTipo.ouPadrao(null), CompraFornecedorTipo.produtosEstoque);
      expect(CompraFornecedorTipo.ouPadrao(''), CompraFornecedorTipo.produtosEstoque);
      expect(CompraFornecedorTipo.ouPadrao('invalido'), CompraFornecedorTipo.produtosEstoque);
    });

    test('compra financeira não movimenta estoque', () {
      final c = _compraBase(tipo: CompraFornecedorTipo.financeira);
      expect(c.movimentaEstoque, isFalse);
      expect(c.ehCompraFinanceira, isTrue);
    });

    test('compra com produtos usa subtotal dos itens no total', () {
      final c = _compraBase(
        itens: [
          CompraFornecedorItem(
            produtoNome: 'A',
            quantidade: 2,
            custoUnitario: 50,
          ),
        ],
        frete: 10,
        desconto: 5,
      );
      expect(c.valorTotalFinanceiro, 105);
    });

    test('compra financeira usa valorInformado + frete - desconto + outras', () {
      final c = _compraBase(
        tipo: CompraFornecedorTipo.financeira,
        valorInformado: 800,
        frete: 50,
        desconto: 20,
        outras: 70,
        itens: [
          CompraFornecedorItem(
            produtoNome: 'Ignorado',
            quantidade: 99,
            custoUnitario: 999,
          ),
        ],
      );
      expect(c.valorTotalFinanceiro, 900);
    });

    test('compra financeira pode ter lista de itens vazia', () {
      final c = _compraBase(
        tipo: CompraFornecedorTipo.financeira,
        valorInformado: 500,
      );
      expect(c.itensOuVazio, isEmpty);
      expect(c.valorTotalFinanceiro, 500);
    });
  });

  group('Contas a pagar — compra financeira sem itens', () {
    test('parcelamento R\$ 900 em 3x soma 900', () {
      final partes = ContaPagarService.parcelarValores(900, 3);
      expect(partes.fold<double>(0, (a, b) => a + b), 900);
    });

    test('total da compra financeira alimenta parcelas', () {
      final c = _compraBase(
        tipo: CompraFornecedorTipo.financeira,
        valorInformado: 900,
      );
      final partes =
          ContaPagarService.parcelarValores(c.valorTotalFinanceiro, 3);
      expect(partes, [300, 300, 300]);
    });
  });
}
