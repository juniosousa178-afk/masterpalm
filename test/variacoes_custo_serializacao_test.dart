import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/screens/produto_form_screen.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';

void main() {
  test('parseVariacoesFromFirestore preserva qtd e custo por variacao sem extra', () {
    final raw = <String, dynamic>{
      'Aro 17': <String, dynamic>{
        'Preto': <String, dynamic>{
          '': 3,
          ProdutoVariacaoExtra.kMetaCustoUnitarioKey: 24.0,
        },
      },
    };

    final parsed = ProdutosFirestoreService.parseVariacoesFromFirestore(raw);

    expect(parsed, isNotNull);
    final cell = (parsed!['Aro 17'] as Map<String, dynamic>)['Preto'];
    expect(ProdutoVariacaoExtra.somarCelula(cell), 3);
    expect(ProdutoVariacaoExtra.custoUnitarioNaCelula(cell), 24.0);
    expect(
      (cell as Map<String, dynamic>).containsKey(ProdutoVariacaoExtra.kSemExtraKey),
      isTrue,
    );
  });

  test('merge da grade salva custo no meta da celula correta', () {
    final rows = <Map<String, TextEditingController>>[
      {
        'tamanho': TextEditingController(text: 'Aro 16'),
        'cor': TextEditingController(text: 'Prata'),
        'extraTipo': TextEditingController(text: ''),
        'extraValor': TextEditingController(text: ''),
        'qtd': TextEditingController(text: '2'),
        'custo': TextEditingController(text: '20,00'),
      },
    ];

    final merged = produtoFormMergeVariacoesGrade(rows);
    final variacoes = merged.variacoes;
    final cell = (variacoes['Aro 16'] as Map<String, dynamic>)['Prata'];

    expect(ProdutoVariacaoExtra.somarCelula(cell), 2);
    expect(ProdutoVariacaoExtra.custoUnitarioNaCelula(cell), 20.0);

    for (final row in rows) {
      for (final controller in row.values) {
        controller.dispose();
      }
    }
  });

  test('sanitizeVariacoesForFirestore remove chave vazia e preserva custo', () {
    final variacoes = <String, dynamic>{
      '1': <String, dynamic>{
        'sem-cor': <String, dynamic>{
          '': 2,
          ProdutoVariacaoExtra.kMetaCustoUnitarioKey: 22.99,
        },
      },
    };

    final sanitized =
        ProdutosFirestoreService.sanitizeVariacoesForFirestore(variacoes);
    final cell = (sanitized['1'] as Map<String, dynamic>)['sem-cor'] as Map<String, dynamic>;

    expect(cell.containsKey(''), isFalse);
    expect(cell.containsKey(ProdutoVariacaoExtra.kSemExtraKey), isTrue);
    expect(cell[ProdutoVariacaoExtra.kSemExtraKey], 2);
    expect(cell[ProdutoVariacaoExtra.kMetaCustoUnitarioKey], 22.99);

    final parsed = ProdutosFirestoreService.parseVariacoesFromFirestore(sanitized);
    final parsedCell = (parsed!['1'] as Map<String, dynamic>)['sem-cor'];
    expect(ProdutoVariacaoExtra.somarCelula(parsedCell), 2);
    expect(ProdutoVariacaoExtra.custoUnitarioNaCelula(parsedCell), 22.99);
  });
}
