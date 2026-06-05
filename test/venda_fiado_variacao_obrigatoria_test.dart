import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/venda_combo_estoque_expansion.dart';

Produto _produtoComTamanhoSemSelecao() {
  return Produto(
    nome: 'Conjunto Coração Cravejado - Pingente E Brinco',
    custoReal: 20,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 120,
    quantidade: 5,
    precoUnitario: 120,
    categoria: 'Joias',
    dataEntrada: DateTime(2026, 6, 5),
    lojaId: 'nathy-pratas-e-folheados',
    estoquePorTamanho: const {'Único': 5},
    tamanhos: const ['Único'],
  );
}

void main() {
  group('venda fiada — variação obrigatória', () {
    test('sem tamanho selecionado bloqueia antes da baixa de estoque', () {
      final produto = _produtoComTamanhoSemSelecao();
      final item = VendaItem(
        produtoNome: produto.nome,
        quantidade: 1,
        precoUnitario: produto.precoFinal,
        tamanho: '',
        cor: '',
        lojaId: produto.lojaId,
      );

      expect(
        () => VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
          itensParaEstoque: [item],
          produtosEncontrados: [produto],
        ),
        throwsA(
          predicate<Exception>(
            (e) =>
                e.toString().contains('possui variação de tamanho') &&
                e.toString().contains('Selecionar'),
          ),
        ),
      );
    });

    test('isErroVariacaoObrigatoria identifica mensagem de seleção', () {
      final e = Exception(
        'O produto "X" possui variação de tamanho. '
        'Clique em "Selecionar" e escolha o tamanho (ex.: P, M, G).',
      );
      expect(VendaComboEstoqueExpansion.isErroVariacaoObrigatoria(e), isTrue);
      expect(
        VendaComboEstoqueExpansion.isErroVariacaoObrigatoria(
          ArgumentError('Não foi possível vincular a venda à conta a receber.'),
        ),
        isFalse,
      );
    });

    test('com tamanho selecionado passa na validação de expansão', () {
      final produto = _produtoComTamanhoSemSelecao();
      produto.variacoes = {
        'Único': {
          'sem-cor': {'': 5},
        },
      };
      final item = VendaItem(
        produtoNome: produto.nome,
        quantidade: 1,
        precoUnitario: produto.precoFinal,
        tamanho: 'Único',
        cor: '',
        lojaId: produto.lojaId,
      );

      expect(
        () => VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
          itensParaEstoque: [item],
          produtosEncontrados: [produto],
        ),
        returnsNormally,
      );
    });

    test('produto sem variação vende sem exigir tamanho', () {
      final produto = Produto(
        nome: 'Pulseira Lisa',
        custoReal: 5,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 25,
        quantidade: 10,
        precoUnitario: 25,
        categoria: 'Joias',
        dataEntrada: DateTime(2026, 6, 5),
        lojaId: 'loja-teste',
      );
      final item = VendaItem(
        produtoNome: produto.nome,
        quantidade: 1,
        precoUnitario: produto.precoFinal,
        tamanho: '',
        cor: '',
        lojaId: produto.lojaId,
      );

      expect(
        () => VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
          itensParaEstoque: [item],
          produtosEncontrados: [produto],
        ),
        returnsNormally,
      );
    });
  });
}
