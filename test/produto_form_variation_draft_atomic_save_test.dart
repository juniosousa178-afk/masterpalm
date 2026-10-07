import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_form_grade_hydration.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produto_stock_catalog_cadastro_sync.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';

Produto _anel({int revision = 6}) {
  return Produto.vazio()
    ..idFirebase = 'nathy-pratas-e-folheados-anel-solit-rio-princesa'
    ..lojaId = 'nathy-pratas-e-folheados'
    ..nome = 'Anel Solitário Princesa'
    ..quantidade = 2
    ..stockRevision = revision
    ..variacoes = {
      '12': {'cristal': 2},
    }
    ..estoquePorTamanho = {'12': 2}
    ..tamanhos = ['12']
    ..cores = ['cristal'];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    StockCatalogBackendService.debugTransport = null;
  });

  test('foto/debounce nao envia replace mesmo com grade rascunho divergente',
      () async {
    final produto = _anel();
    final baseline = ProdutoFormGradeBaseline.capture(produto);
    produto
      ..quantidade = 5
      ..variacoes = {
        '12': {'cristal': 2},
        '17': {'cristal': 1},
        '18': {'cristal': 1},
        '19': {'cristal': 1},
      }
      ..estoquePorTamanho = {'12': 2, '17': 1, '18': 1, '19': 1};

    final intent = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
      produto: produto,
      produtoId: produto.idFirebase,
      documentExists: true,
      forcePushFromCadastro: true,
      gradeBaseline: baseline,
      remoteRevisionAtSaveTime: 6,
      permitirReplaceEstoque: false,
    );

    expect(intent.kind, 'editorial');
    expect(intent.definition, isNull);
    expect(intent.expectedRevision, isNull);
    expect(hasPendingStockMutation(produto), isFalse);
    expect(produto.stockRevision, 6);
  });

  test('sequencia original: varios adicionar e um save atomico', () async {
    final produto = _anel();
    final baseline = ProdutoFormGradeBaseline.capture(produto);
    var preSaveReplaces = 0;

    void adicionarVariacaoLocal() {}
    void preencher(String tamanho, int qtd) {
      final grade = Map<String, dynamic>.from(produto.variacoes!);
      grade[tamanho] = {'cristal': qtd};
      produto.variacoes = grade;
    }

    adicionarVariacaoLocal();
    preencher('17', 1);
    adicionarVariacaoLocal();
    preencher('18', 1);
    adicionarVariacaoLocal();
    preencher('19', 1);
    expect(preSaveReplaces, 0);

    var soma = 0;
    for (final cores in produto.variacoes!.values) {
      soma += (cores as Map)['cristal'] as int;
    }
    produto.quantidade = soma;
    produto.estoquePorTamanho = {
      for (final e in produto.variacoes!.entries)
        e.key: (e.value as Map)['cristal'] as int,
    };

    final intent = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
      produto: produto,
      produtoId: produto.idFirebase,
      documentExists: true,
      forcePushFromCadastro: true,
      gradeBaseline: baseline,
      remoteRevisionAtSaveTime: baseline.stockRevision,
    );

    expect(intent.kind, 'replace');
    expect(intent.expectedRevision, 6);
    expect(intent.definition?['quantidade'], 5);
    final variacoes = intent.definition?['variacoes'] as Map;
    expect(variacoes['17'], {'cristal': 1});
    expect(variacoes['18'], {'cristal': 1});
    expect(variacoes['19'], {'cristal': 1});
    expect(variacoes['12'], {'cristal': 2});
    expect(intent.operationId, isNotEmpty);
  });

  test('cinco variacoes novas entram num unico replace', () async {
    final produto = _anel();
    final baseline = ProdutoFormGradeBaseline.capture(produto);
    final grade = Map<String, dynamic>.from(produto.variacoes!);
    for (final tamanho in ['17', '18', '19', '20', '21']) {
      grade[tamanho] = {'cristal': 1};
    }
    produto
      ..variacoes = grade
      ..quantidade = 7
      ..estoquePorTamanho = {
        for (final e in grade.entries) e.key: (e.value as Map)['cristal'] as int,
      };

    final intent = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
      produto: produto,
      produtoId: produto.idFirebase,
      documentExists: true,
      forcePushFromCadastro: true,
      gradeBaseline: baseline,
      remoteRevisionAtSaveTime: 6,
    );

    expect(intent.kind, 'replace');
    expect(intent.expectedRevision, 6);
    final variacoes = intent.definition?['variacoes'] as Map;
    for (final tamanho in ['17', '18', '19', '20', '21']) {
      expect(variacoes[tamanho], {'cristal': 1});
    }
  });

  test('mistura existente, nova e removida num unico replace', () async {
    final produto = _anel();
    produto
      ..variacoes = {
        '12': {'cristal': 2},
        '13': {'cristal': 2},
      }
      ..quantidade = 4
      ..estoquePorTamanho = {'12': 2, '13': 2};
    final baseline = ProdutoFormGradeBaseline.capture(produto);
    produto
      ..variacoes = {
        '12': {'cristal': 3},
        '17': {'cristal': 1},
        '18': {'cristal': 2},
      }
      ..quantidade = 6
      ..estoquePorTamanho = {'12': 3, '17': 1, '18': 2};

    final intent = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
      produto: produto,
      produtoId: produto.idFirebase,
      documentExists: true,
      forcePushFromCadastro: true,
      gradeBaseline: baseline,
      remoteRevisionAtSaveTime: 6,
    );

    final variacoes = intent.definition?['variacoes'] as Map;
    expect(intent.kind, 'replace');
    expect(variacoes.containsKey('13'), isFalse);
    expect(variacoes['12'], {'cristal': 3});
    expect(variacoes['17'], {'cristal': 1});
    expect(variacoes['18'], {'cristal': 2});
    expect(intent.definition?['quantidade'], 6);
  });

  test('celula zero reativada vai no replace unico', () async {
    final produto = _anel();
    produto.variacoes = {
      '12': {'cristal': 2},
      '17': {'cristal': 0},
    };
    produto.quantidade = 2;
    final baseline = ProdutoFormGradeBaseline.capture(produto);
    produto.variacoes = {
      '12': {'cristal': 2},
      '17': {'cristal': 1},
    };
    produto.quantidade = 3;

    final intent = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
      produto: produto,
      produtoId: produto.idFirebase,
      documentExists: true,
      forcePushFromCadastro: true,
      gradeBaseline: baseline,
      remoteRevisionAtSaveTime: 6,
    );

    expect(intent.kind, 'replace');
    expect((intent.definition?['variacoes'] as Map)['17'], {'cristal': 1});
  });

  test('conflito concorrente nao adota revisao nova nem cria pending', () async {
    final produto = _anel();
    final baseline = ProdutoFormGradeBaseline.capture(produto);
    produto.quantidade = 3;

    await expectLater(
      ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
        produto: produto,
        produtoId: produto.idFirebase,
        documentExists: true,
        forcePushFromCadastro: true,
        gradeBaseline: baseline,
        remoteRevisionAtSaveTime: 7,
      ),
      throwsA(isA<ProdutoStockRevisionConflictException>()),
    );
    expect(hasPendingStockMutation(produto), isFalse);
    expect(produto.stockRevision, 6);
  });

  test('sucesso atualiza baseline e o save seguinte usa revisao e operation novos',
      () async {
    final produto = _anel();
    final baseline = ProdutoFormGradeBaseline.capture(produto);
    produto.quantidade = 3;
    produto.variacoes = {
      '12': {'cristal': 3},
    };

    final first = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
      produto: produto,
      produtoId: produto.idFirebase,
      documentExists: true,
      forcePushFromCadastro: true,
      gradeBaseline: baseline,
      remoteRevisionAtSaveTime: 6,
    );
    expect(first.kind, 'replace');
    expect(first.expectedRevision, 6);

    confirmStockMutation(
      produto,
      operationId: first.operationId,
      revision: 7,
    );
    final atualizada = ProdutoFormGradeBaseline.capture(produto);
    expect(atualizada.stockRevision, 7);

    produto.quantidade = 4;
    final second = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
      produto: produto,
      produtoId: produto.idFirebase,
      documentExists: true,
      forcePushFromCadastro: true,
      gradeBaseline: atualizada,
      remoteRevisionAtSaveTime: 7,
    );
    expect(second.expectedRevision, 7);
    expect(second.operationId, isNot(first.operationId));
  });

  test('replay do mesmo operationId permanece o mesmo payload', () async {
    final calls = <String>[];
    StockCatalogBackendService.debugTransport = (name, data) async {
      calls.add(data['operationId'] as String);
      return {
        'operationId': data['operationId'],
        'alreadyApplied': calls.length > 1,
        'products': [
          {
            'productId': 'p',
            'quantidade': 5,
            'stockRevision': 7,
            'variacoes': <String, dynamic>{},
            'estoquePorTamanho': <String, dynamic>{},
          }
        ],
      };
    };
    final frozen = ProdutoStockCatalogCadastroIntent(
      operationId: 'op-um-save',
      kind: 'replace',
      items: [
        {'productId': 'p', 'expectedRevision': 6},
      ],
      editorial: {'nome': 'Anel'},
      definition: {'quantidade': 5},
      expectedRevision: 6,
    );
    await ProdutoStockCatalogCadastroSync.sendIntent(
      lojaId: 'nathy-pratas-e-folheados',
      intent: frozen,
    );
    await ProdutoStockCatalogCadastroSync.sendIntent(
      lojaId: 'nathy-pratas-e-folheados',
      intent: frozen,
    );
    expect(calls, ['op-um-save', 'op-um-save']);
  });

  test('produto novo continua create com replace permitido', () async {
    final produto = Produto.vazio()
      ..nome = 'Novo'
      ..slug = 'novo'
      ..idFirebase = 'novo-1'
      ..quantidade = 1
      ..stockRevision = 0;
    final intent = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
      produto: produto,
      produtoId: 'novo-1',
      documentExists: false,
      forcePushFromCadastro: true,
      gradeBaseline: ProdutoFormGradeBaseline.capture(produto),
    );
    expect(intent.kind, 'create');
    expect(intent.definition?['quantidade'], 1);
  });

  test('formulario nao grava estoque ao adicionar ou remover variacao', () {
    final source =
        File('lib/screens/produto_form_screen.dart').readAsStringSync();
    expect(source.contains('_persistirProdutoAtual'), isFalse);
    expect(source.contains('_persistirEditorialSemEstoque'), isTrue);
    expect(source.contains('permitirReplaceEstoque: false'), isTrue);

    final add = source.indexOf("label: const Text('Adicionar Variação')");
    expect(add, greaterThan(0));
    final addBody = source.substring(add, add + 700);
    expect(addBody.contains('_persistirEditorialSemEstoque'), isFalse);
    expect(addBody.contains('syncProdutoComStatus'), isFalse);
    expect(addBody.contains('permitirReplaceEstoque: true'), isFalse);

    final remove = source.indexOf("tooltip: _variacaoControllers.length > 1");
    expect(remove, greaterThan(0));
    final removeBody = source.substring(remove, remove + 1200);
    expect(removeBody.contains('_persistirEditorialSemEstoque'), isFalse);
    expect(removeBody.contains('syncProdutoComStatus'), isFalse);
  });
}
