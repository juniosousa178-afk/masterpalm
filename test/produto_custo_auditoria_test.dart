import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_custo_guard.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_upsert_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Produto _produtoBase({
  double custoReal = 0,
  bool custoEditadoNoCadastro = false,
  String id = 'doc-custo-guard',
}) {
  return Produto(
    nome: 'Produto Guard',
    custoReal: custoReal,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 100,
    precoFinal: 100,
    quantidade: 5,
    precoUnitario: 100,
    categoria: 'Cat',
    dataEntrada: DateTime.now(),
    lojaId: 'loja-test',
    idFirebase: id,
    slug: id,
    custoEditadoNoCadastro: custoEditadoNoCadastro,
  );
}

void main() {
  group('ProdutoCustoGuard — regras unitárias', () {
    test('remoto ausente mantém custo local > 0', () {
      final p = _produtoBase(custoReal: 42);
      expect(
        ProdutoCustoGuard.resolveCustoAfterRemotePull(
          local: p,
          remoteData: {'nome': 'X'},
        ),
        isNull,
      );
      expect(p.custoReal, 42);
    });

    test('remoto 0 não sobrescreve local > 0 sem intenção explícita', () {
      final p = _produtoBase(custoReal: 30);
      expect(
        ProdutoCustoGuard.resolveCustoAfterRemotePull(
          local: p,
          remoteData: {'custoReal': 0},
        ),
        isNull,
      );
    });

    test('custoEditadoNoCadastro true preserva local contra remoto 0', () {
      final p = _produtoBase(custoReal: 18, custoEditadoNoCadastro: true);
      ProdutoCustoGuard.applyRemoteCustoOnExistingProduct(
        local: p,
        remoteData: {'custoReal': 0, 'custoEditadoNoCadastro': false},
        logContext: 'test',
      );
      expect(p.custoReal, 18);
      expect(p.custoEditadoNoCadastro, isTrue);
    });

    test('remoto zerado explícito (flag cadastro) aplica 0 mesmo em legado', () {
      final p = _produtoBase(custoReal: 12, custoEditadoNoCadastro: false);
      ProdutoCustoGuard.applyRemoteCustoOnExistingProduct(
        local: p,
        remoteData: {
          'custoReal': 0,
          'custoEditadoNoCadastro': true,
        },
        logContext: 'test',
      );
      expect(p.custoReal, 0);
    });

    test('legado custoReal > 0 e flag false é protegido contra remoto 0', () {
      final p = _produtoBase(custoReal: 22, custoEditadoNoCadastro: false);
      expect(ProdutoCustoGuard.isCustoLocalProtegido(p), isTrue);
      expect(
        ProdutoCustoGuard.resolveCustoAfterRemotePull(
          local: p,
          remoteData: {'custoReal': 0},
        ),
        isNull,
      );
    });

    test('remoto positivo aplica quando local sem custo protegido', () {
      final p = _produtoBase(custoReal: 0, custoEditadoNoCadastro: false);
      expect(
        ProdutoCustoGuard.resolveCustoAfterRemotePull(
          local: p,
          remoteData: {'custoReal': 15.5},
        ),
        15.5,
      );
    });

    test('remoteIndicaCustoZeradoExplicitamente detecta flag + custo 0', () {
      expect(
        ProdutoCustoGuard.remoteIndicaCustoZeradoExplicitamente({
          'custoReal': 0,
          'custoEditadoNoCadastro': true,
        }),
        isTrue,
      );
      expect(
        ProdutoCustoGuard.resolveCustoAfterRemotePull(
          local: _produtoBase(custoReal: 12, custoEditadoNoCadastro: false),
          remoteData: {
            'custoReal': 0,
            'custoEditadoNoCadastro': true,
          },
        ),
        0.0,
      );
    });

    test('parseRemoteCusto ignora NaN e infinito', () {
      expect(
        ProdutoCustoGuard.parseRemoteCusto({'custoReal': double.nan}),
        isNull,
      );
      expect(
        ProdutoCustoGuard.parseRemoteCusto({'custoReal': double.infinity}),
        isNull,
      );
    });

    test('import coluna ausente não zera custo existente', () {
      final existente = _produtoBase(custoReal: 55);
      ProdutoCustoGuard.applyImportCustoMerge(
        existente: existente,
        importCusto: ImportCustoInput.colunaAusente,
        fallbackNovoProduto: 0,
      );
      expect(existente.custoReal, 55);
    });

    test('import célula vazia não zera custo existente', () {
      final existente = _produtoBase(custoReal: 40);
      ProdutoCustoGuard.applyImportCustoMerge(
        existente: existente,
        importCusto: const ImportCustoInput(colunaPresente: true),
        fallbackNovoProduto: 0,
      );
      expect(existente.custoReal, 40);
    });

    test('import custo explícito positivo atualiza', () {
      final existente = _produtoBase(custoReal: 10);
      ProdutoCustoGuard.applyImportCustoMerge(
        existente: existente,
        importCusto: const ImportCustoInput(
          colunaPresente: true,
          valorExplicito: 33,
        ),
        fallbackNovoProduto: 0,
      );
      expect(existente.custoReal, 33);
    });

    test('import custo explícito 0 pode zerar se não protegido', () {
      final existente = _produtoBase(custoReal: 10);
      ProdutoCustoGuard.applyImportCustoMerge(
        existente: existente,
        importCusto: const ImportCustoInput(
          colunaPresente: true,
          valorExplicito: 0,
        ),
        fallbackNovoProduto: 0,
      );
      expect(existente.custoReal, 0);
    });

    test('ImportCustoInput.fromRowMap distingue ausente e vazio', () {
      expect(
        ImportCustoInput.fromRowMap({'nome': 'A'}).colunaPresente,
        isFalse,
      );
      expect(
        ImportCustoInput.fromRowMap({'custo': ''}).temValorExplicito,
        isFalse,
      );
      expect(
        ImportCustoInput.fromRowMap({'custo': '12,5'}).valorExplicito,
        12.5,
      );
    });

    test('custoInicialFromRemoteDoc sem chave retorna 0 para produto novo', () {
      expect(
        ProdutoCustoGuard.custoInicialFromRemoteDoc({'nome': 'Novo'}),
        0,
      );
    });
  });

  group('ProdutoCustoGuard — pull Firestore → Hive', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    const lojaId = 'loja-custo-guard';
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_custo_guard_');
      hivePath = dir.path;
      Hive.init(hivePath);
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    });

    tearDownAll(() async {
      try {
        await Directory(hivePath).delete(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      final s = DateTime.now().microsecondsSinceEpoch;
      produtosBox = await Hive.openBox<Produto>('p_custo_guard_$s');
    });

    tearDown(() async {
      ProdutosFirestoreService.debugFirestoreOverride = null;
      await produtosBox.close();
    });

    Future<void> seedRemote(String docId, Map<String, dynamic> data) async {
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId)
          .set({'nome': 'P', 'slug': docId, 'lojaId': lojaId, ...data});
    }

    test('pull não sobrescreve custo local 25 com remoto 0', () async {
      const docId = 'prod-pull-zero';
      await seedRemote(docId, {'custoReal': 0, 'quantidade': 1, 'preco': 10});

      final local = _produtoBase(custoReal: 25, id: docId);
      local.lojaId = lojaId;
      await produtosBox.add(local);

      await ProdutosFirestoreService.syncFirestoreToHive(
        lojaId: lojaId,
        produtosBox: produtosBox,
      );

      final p = produtosBox.values
          .where((x) => x.idFirebase == docId)
          .single;
      expect(p.custoReal, closeTo(25, 0.01));
    });

    test('pull aplica custo remoto positivo quando local é 0', () async {
      const docId = 'prod-pull-positivo';
      await seedRemote(docId, {
        'custoReal': 19,
        'quantidade': 2,
        'preco': 50,
      });

      final local = _produtoBase(custoReal: 0, id: docId);
      local.lojaId = lojaId;
      await produtosBox.add(local);

      await ProdutosFirestoreService.syncFirestoreToHive(
        lojaId: lojaId,
        produtosBox: produtosBox,
      );

      final matches =
          produtosBox.values.where((x) => x.idFirebase == docId).toList();
      expect(matches.length, 1);
      expect(matches.single.custoReal, closeTo(19, 0.01));
    });
  });

  group('ProdutoCustoGuard — importação upsert', () {
    late String hivePath;
    late Box<Produto> box;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_import_custo_');
      hivePath = dir.path;
      Hive.init(hivePath);
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    });

    tearDownAll(() async {
      try {
        await Directory(hivePath).delete(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      final s = DateTime.now().microsecondsSinceEpoch;
      box = await Hive.openBox<Produto>('import_custo_$s');
    });

    tearDown(() async {
      await box.close();
    });

    test('upsert com coluna custo ausente preserva custo existente', () async {
      const lojaId = 'loja-import';
      final existente = _produtoBase(custoReal: 77, id: 'imp-1');
      existente.nome = 'Camiseta Unica Guard';
      existente.categoria = 'Imp';
      existente.lojaId = lojaId;
      await box.add(existente);

      final novo = _produtoBase(custoReal: 0, id: 'imp-1');
      novo.nome = 'Camiseta Unica Guard';
      novo.categoria = 'Imp';
      novo.lojaId = lojaId;
      novo.quantidade = 99;

      await upsertProduto(
        box,
        lojaId,
        novo,
        importCusto: ImportCustoInput.colunaAusente,
      );

      final atualizado = box.values
          .where((p) => p.nome == 'Camiseta Unica Guard')
          .single;
      expect(atualizado.custoReal, closeTo(77, 0.01));
    });
  });

  group('Venda e catálogo não alteram Produto.custoReal', () {
    test('salvar produto só com preço/nome não zera custo (simulação cadastro)', () {
      final p = _produtoBase(custoReal: 61, custoEditadoNoCadastro: true);
      p.nome = 'Nome novo';
      p.precoFinal = 200;
      p.precoUnitario = 200;
      expect(p.custoReal, 61);
    });
  });
}
