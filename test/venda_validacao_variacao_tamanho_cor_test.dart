// Validação de variação na venda: cor-only vs tamanho real vs legado.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/venda_combo_estoque_expansion.dart';

Produto _produtoCorPinkComLegadoUnico() {
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
    dataEntrada: DateTime(2026, 6, 9),
    lojaId: 'nathy-pratas-e-folheados',
    estoquePorTamanho: const {'Único': 5},
    tamanhos: const ['Único'],
    variacoes: {
      'sem-tamanho': {
        'Pink': 5,
      },
    },
  );
}

Produto _produtoTamanhoReal() {
  return Produto(
    nome: 'Anel Ajustável',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 80,
    quantidade: 9,
    precoUnitario: 80,
    categoria: 'Joias',
    dataEntrada: DateTime(2026, 6, 9),
    lojaId: 'loja-teste',
    variacoes: {
      'P': {'sem-cor': 3},
      'M': {'sem-cor': 3},
      'G': {'sem-cor': 3},
    },
  );
}

void main() {
  group('Produto.ehChaveTamanhoTecnicoLegado', () {
    test('sem-tamanho, único e vazio são técnicos', () {
      expect(Produto.ehChaveTamanhoTecnicoLegado('sem-tamanho'), isTrue);
      expect(Produto.ehChaveTamanhoTecnicoLegado('Único'), isTrue);
      expect(Produto.ehChaveTamanhoTecnicoLegado('unico'), isTrue);
      expect(Produto.ehChaveTamanhoTecnicoLegado(''), isTrue);
      expect(Produto.ehChaveTamanhoTecnicoLegado('P'), isFalse);
      expect(Produto.ehChaveTamanhoTecnicoLegado('M'), isFalse);
    });
  });

  group('validarExpansaoParaBaixaFirestore — cor vs tamanho', () {
    test('1 — produto só cor Pink finaliza sem tamanho', () {
      final produto = _produtoCorPinkComLegadoUnico();
      expect(produto.temVariacaoSoloCor, isTrue);
      expect(produto.exigeSelecaoTamanhoNaVenda, isFalse);

      final item = VendaItem(
        produtoNome: produto.nome,
        quantidade: 1,
        precoUnitario: produto.precoFinal,
        tamanho: '',
        cor: 'Pink',
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

    test('2 — produto com tamanho real exige tamanho', () {
      final produto = _produtoTamanhoReal();
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
            (e) => e.toString().contains('variação de tamanho'),
          ),
        ),
      );
    });

    test('3 — tamanho real + cor exige ambos', () {
      final produto = Produto(
        nome: 'Camiseta',
        custoReal: 15,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 50,
        quantidade: 4,
        precoUnitario: 50,
        categoria: 'Roupas',
        dataEntrada: DateTime(2026, 6, 9),
        lojaId: 'loja',
        variacoes: {
          'P': {'Azul': 2, 'Branco': 2},
        },
      );
      expect(produto.temVariacaoTamanhoECor, isTrue);

      expect(
        () => VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
          itensParaEstoque: [
            VendaItem(
              produtoNome: produto.nome,
              quantidade: 1,
              precoUnitario: 50,
              tamanho: 'P',
              cor: '',
              lojaId: produto.lojaId,
            ),
          ],
          produtosEncontrados: [produto],
        ),
        throwsA(
          predicate<Exception>(
            (e) => e.toString().contains('tamanho + cor'),
          ),
        ),
      );
    });

    test('4 — produto simples sem variação não exige selecionar', () {
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
        dataEntrada: DateTime(2026, 6, 9),
        lojaId: 'loja',
      );

      expect(
        () => VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
          itensParaEstoque: [
            VendaItem(
              produtoNome: produto.nome,
              quantidade: 1,
              precoUnitario: 25,
              tamanho: '',
              cor: '',
              lojaId: produto.lojaId,
            ),
          ],
          produtosEncontrados: [produto],
        ),
        returnsNormally,
      );
    });

    test('5 — estoquePorTamanho só com Único não exige tamanho', () {
      final produto = Produto(
        nome: 'Item legado único',
        custoReal: 1,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 10,
        quantidade: 3,
        precoUnitario: 10,
        categoria: 'X',
        dataEntrada: DateTime(2026, 6, 9),
        lojaId: 'loja',
        estoquePorTamanho: const {'Único': 3},
      );
      expect(produto.exigeSelecaoTamanhoNaVenda, isFalse);

      expect(
        () => VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
          itensParaEstoque: [
            VendaItem(
              produtoNome: produto.nome,
              quantidade: 1,
              precoUnitario: 10,
              tamanho: '',
              cor: '',
              lojaId: produto.lojaId,
            ),
          ],
          produtosEncontrados: [produto],
        ),
        returnsNormally,
      );
    });

    test('6 — cor selecionada não mostra erro de tamanho', () {
      final produto = _produtoCorPinkComLegadoUnico();
      final item = VendaItem(
        produtoNome: produto.nome,
        quantidade: 1,
        precoUnitario: produto.precoFinal,
        tamanho: '',
        cor: 'Pink',
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

    test('7 — falta cor mostra mensagem de cor', () {
      final produto = _produtoCorPinkComLegadoUnico();
      expect(
        () => VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
          itensParaEstoque: [
            VendaItem(
              produtoNome: produto.nome,
              quantidade: 1,
              precoUnitario: produto.precoFinal,
              tamanho: '',
              cor: '',
              lojaId: produto.lojaId,
            ),
          ],
          produtosEncontrados: [produto],
        ),
        throwsA(
          predicate<Exception>(
            (e) =>
                e.toString().contains('variação de cor') &&
                !e.toString().contains('variação de tamanho'),
          ),
        ),
      );
    });

    test('8 — falta tamanho real mostra mensagem de tamanho', () {
      final produto = _produtoTamanhoReal();
      expect(
        () => VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
          itensParaEstoque: [
            VendaItem(
              produtoNome: produto.nome,
              quantidade: 1,
              precoUnitario: produto.precoFinal,
              tamanho: '',
              cor: '',
              lojaId: produto.lojaId,
            ),
          ],
          produtosEncontrados: [produto],
        ),
        throwsA(
          predicate<Exception>(
            (e) => e.toString().contains('variação de tamanho'),
          ),
        ),
      );
    });

    test('9 — fiado não transforma cor em tamanho', () {
      final produto = _produtoCorPinkComLegadoUnico();
      expect(produto.temVariacaoSoloCor, isTrue);
      expect(produto.temVariacaoSoloTamanho, isFalse);
      expect(produto.exigeSelecaoTamanhoNaVenda, isFalse);
    });
  });
}
