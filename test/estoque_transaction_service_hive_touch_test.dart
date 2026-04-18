import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';

void main() {
  group('touchProdutoUpdatedAtParaHivePosTransacao', () {
    test('define updatedAt posterior ao valor anterior', () {
      final anterior = DateTime(2020, 1, 1);
      final p = Produto(
        nome: 'Teste',
        custoReal: 0,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 0,
        quantidade: 10,
        precoUnitario: 0,
        categoria: 'c',
        dataEntrada: DateTime.now(),
        lojaId: 'loja',
        updatedAt: anterior,
      );

      EstoqueTransactionService.touchProdutoUpdatedAtParaHivePosTransacao(p);

      expect(p.updatedAt, isNotNull);
      expect(p.updatedAt!.isAfter(anterior), isTrue);
    });

    test('não altera quantidade nem campos de saldo', () {
      final p = Produto(
        nome: 'X',
        custoReal: 1,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 10,
        quantidade: 7,
        precoUnitario: 10,
        categoria: 'c',
        dataEntrada: DateTime.now(),
        lojaId: 'l',
      );
      EstoqueTransactionService.touchProdutoUpdatedAtParaHivePosTransacao(p);
      expect(p.quantidade, 7);
      expect(p.nome, 'X');
    });
  });
}
