import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/estoque_service.dart';

void main() {
  group('touchProdutoUpdatedAtParaDevolucaoHive', () {
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
        quantidade: 5,
        precoUnitario: 0,
        categoria: 'c',
        dataEntrada: DateTime.now(),
        lojaId: 'loja',
        updatedAt: anterior,
      );

      EstoqueService.touchProdutoUpdatedAtParaDevolucaoHive(p);

      expect(p.updatedAt, isNotNull);
      expect(p.updatedAt!.isAfter(anterior), isTrue);
    });

    test('não altera quantidade nem outros campos', () {
      final p = Produto(
        nome: 'X',
        custoReal: 1,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 10,
        quantidade: 3,
        precoUnitario: 10,
        categoria: 'c',
        dataEntrada: DateTime.now(),
        lojaId: 'l',
      );
      EstoqueService.touchProdutoUpdatedAtParaDevolucaoHive(p);
      expect(p.quantidade, 3);
      expect(p.nome, 'X');
      expect(p.precoFinal, 10);
    });
  });
}
