import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/screens/produto_form_screen.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';

void _assertNenhumaChaveLegadaSemExtra(dynamic v) {
  if (v is Map) {
    for (final e in v.entries) {
      expect(e.key, isNot(ProdutoVariacaoExtra.kSemExtraKeyLegacy));
      _assertNenhumaChaveLegadaSemExtra(e.value);
    }
  }
}

void main() {
  test(
      'parseVariacoesFromFirestore preserva qtd e custo por variacao sem extra',
      () {
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
      (cell as Map<String, dynamic>)
          .containsKey(ProdutoVariacaoExtra.kSemExtraKey),
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
    final cell = (sanitized['1'] as Map<String, dynamic>)['sem-cor']
        as Map<String, dynamic>;

    expect(cell.containsKey(''), isFalse);
    expect(cell.containsKey(ProdutoVariacaoExtra.kSemExtraKeyLegacy), isFalse);
    expect(cell.containsKey(ProdutoVariacaoExtra.kSemExtraKey), isTrue);
    expect(cell[ProdutoVariacaoExtra.kSemExtraKey], 2);
    expect(cell[ProdutoVariacaoExtra.kMetaCustoUnitarioKey], 22.99);

    final parsed =
        ProdutosFirestoreService.parseVariacoesFromFirestore(sanitized);
    final parsedCell = (parsed!['1'] as Map<String, dynamic>)['sem-cor'];
    expect(ProdutoVariacaoExtra.somarCelula(parsedCell), 2);
    expect(ProdutoVariacaoExtra.custoUnitarioNaCelula(parsedCell), 22.99);
  });

  test('parseVariacoesFromFirestore aceita chave legada __sem_extra__', () {
    final raw = <String, dynamic>{
      'Aro 18': <String, dynamic>{
        'Branco': <String, dynamic>{
          ProdutoVariacaoExtra.kSemExtraKeyLegacy: 4,
          ProdutoVariacaoExtra.kMetaCustoUnitarioKey: 10.0,
        },
      },
    };
    final parsed = ProdutosFirestoreService.parseVariacoesFromFirestore(raw);
    final cell = (parsed!['Aro 18'] as Map<String, dynamic>)['Branco'];
    expect(ProdutoVariacaoExtra.somarCelula(cell), 4);
    expect(ProdutoVariacaoExtra.custoUnitarioNaCelula(cell), 10.0);
    expect(
      (cell as Map<String, dynamic>)
          .containsKey(ProdutoVariacaoExtra.kSemExtraKey),
      isTrue,
    );
  });

  test(
      'sanitizeVariacoesForFirestore converte legado para chave Firestore-safe',
      () {
    final variacoes = <String, dynamic>{
      '1': <String, dynamic>{
        'sem-cor': <String, dynamic>{
          ProdutoVariacaoExtra.kSemExtraKeyLegacy: 3,
          ProdutoVariacaoExtra.kMetaCustoUnitarioKey: 5.0,
        },
      },
    };
    final sanitized =
        ProdutosFirestoreService.sanitizeVariacoesForFirestore(variacoes);
    final cell = (sanitized['1'] as Map<String, dynamic>)['sem-cor']
        as Map<String, dynamic>;
    expect(cell.containsKey(ProdutoVariacaoExtra.kSemExtraKeyLegacy), isFalse);
    expect(cell[ProdutoVariacaoExtra.kSemExtraKey], 3);
  });

  test('produtoFormTamanhoKeyPrecoPorTamanho: vazio usa sem-tamanho', () {
    expect(produtoFormTamanhoKeyPrecoPorTamanho(''), 'sem-tamanho');
    expect(produtoFormTamanhoKeyPrecoPorTamanho('  P  '), 'P');
  });

  test(
      'precoParaVariacao usa precoPorTamanho[sem-tamanho] quando tamanho vazio',
      () {
    final p = Produto.vazio();
    p.precoFinal = 99.0;
    p.precoPorTamanho = {'sem-tamanho': 42.5, 'G': 50.0};
    expect(p.precoParaVariacao(''), 42.5);
    expect(p.precoParaVariacao('sem-tamanho'), 42.5);
    expect(p.precoParaVariacao('G'), 50.0);
    expect(p.precoParaVariacao('X'), 99.0);
  });

  test('precoParaVariacao usa precoUnitario quando precoFinal estiver zerado',
      () {
    final p = Produto.vazio();
    p.precoFinal = 0.0;
    p.precoUnitario = 49.9;
    expect(p.precoParaVariacao(''), 49.9);
    expect(p.precoParaVariacao('G'), 49.9);
  });

  test('precoParaVariacao encontra precoPorTamanho por chave normalizada', () {
    final p = Produto.vazio();
    p.precoFinal = 73.9;
    p.precoUnitario = 73.9;
    p.precoPorTamanho = {
      '45 cm': 49.9,
      '40 cm': 52.9,
      '60 cm': 59.9,
    };
    expect(p.precoParaVariacao('45cm'), 49.9);
    expect(p.precoParaVariacao('40cm'), 52.9);
    expect(p.precoParaVariacao('60cm'), 59.9);
  });

  test('precoParaVariacao encontra precoPorTamanho no sentido inverso', () {
    final p = Produto.vazio();
    p.precoFinal = 73.9;
    p.precoUnitario = 73.9;
    p.precoPorTamanho = {'45cm': 49.9};
    expect(p.precoParaVariacao('45 cm'), 49.9);
  });

  test(
      'build precoPorTamanho a partir de controllers canoniza tamanho e ignora vazios',
      () {
    final controllers = <String, TextEditingController>{
      '40cm': TextEditingController(text: '99,90'),
      ' 45cm ': TextEditingController(text: '109,90'),
      '': TextEditingController(text: '129,90'),
      '60cm': TextEditingController(text: ''),
      '70cm': TextEditingController(text: '0,00'),
    };
    final out = produtoFormBuildPrecoPorTamanhoFromControllers(controllers);
    expect(out, {
      '40cm': 99.9,
      '45cm': 109.9,
      'sem-tamanho': 129.9,
    });
    for (final c in controllers.values) {
      c.dispose();
    }
  });

  test('precoPorTamanho roundtrip Firestore preserva valores', () {
    final payload = <String, dynamic>{
      '40cm': 99.90,
      '45cm': 109.90,
      '60cm': 129.90,
    };
    final parsed =
        ProdutosFirestoreService.parsePrecoPorTamanhoFromFirestore(payload);
    expect(parsed, {
      '40cm': 99.90,
      '45cm': 109.90,
      '60cm': 129.90,
    });
  });

  test('precoPorTamanho parse aceita valores numéricos como string', () {
    final payload = <String, dynamic>{
      '40cm': '99.90',
      '45cm': '109,90',
      '60cm': '129.90',
    };
    final parsed =
        ProdutosFirestoreService.parsePrecoPorTamanhoFromFirestore(payload);
    expect(parsed, {
      '40cm': 99.9,
      '45cm': 109.9,
      '60cm': 129.9,
    });
  });

  test(
      'sanitizeVariacoesForFirestore: custo + _sem_extra e nunca __sem_extra__',
      () {
    final sanitized = ProdutosFirestoreService.sanitizeVariacoesForFirestore(
      <String, dynamic>{
        '1': <String, dynamic>{
          'sem-cor': <String, dynamic>{
            '': 1,
            ProdutoVariacaoExtra.kMetaCustoUnitarioKey: 3.0,
          },
        },
      },
    );
    _assertNenhumaChaveLegadaSemExtra(sanitized);
    final cell = (sanitized['1'] as Map<String, dynamic>)['sem-cor']
        as Map<String, dynamic>;
    expect(cell[ProdutoVariacaoExtra.kSemExtraKey], 1);
    expect(cell[ProdutoVariacaoExtra.kMetaCustoUnitarioKey], 3.0);
  });

  test('Produto Hive roundtrip preserva precoPorTamanho', () async {
    final hiveDir =
        Directory.systemTemp.createTempSync('produto_hive_roundtrip_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }

    try {
      final box = await Hive.openBox<Produto>('produtos_roundtrip_test');
      final original = Produto(
        nome: 'Produto Teste',
        custoReal: 10.0,
        frete: 0.0,
        gastosFixos: 0.0,
        gastosVariaveis: 0.0,
        precoSugerido: 0.0,
        precoFinal: 100.0,
        quantidade: 5,
        precoUnitario: 100.0,
        categoria: 'Teste',
        dataEntrada: DateTime.now(),
        precoPorTamanho: const {
          '40cm': 75.9,
          '45cm': 79.9,
          '60cm': 119.9,
        },
      );
      final key = await box.add(original);
      final loaded = box.get(key);

      expect(loaded, isNotNull);
      expect(loaded!.precoPorTamanho, {
        '40cm': 75.9,
        '45cm': 79.9,
        '60cm': 119.9,
      });
      await box.close();
    } finally {
      Hive.close();
      if (hiveDir.existsSync()) {
        hiveDir.deleteSync(recursive: true);
      }
    }
  });
}
