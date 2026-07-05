// Diagnóstico: erro genérico "converted Future" na finalização de venda,
// combo pendente de sync, estoque qtd==disponível.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/dart_error_unwrap.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/combo_kit_stock_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/sync_queue_service.dart';
import 'package:master_palm/services/venda_combo_estoque_expansion.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simula encapsulamento típico do Flutter Web (propriedade [error]).
class _FakeConvertedFutureError implements Exception {
  _FakeConvertedFutureError(this.error);
  final Object error;

  @override
  String toString() =>
      "Error: Dart exception thrown from converted Future. "
      "Use the properties 'error' to fetch the boxed error and 'stack' to recover the stack trace.";
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lojaId = 'loja-diagnostico-venda-20260601';

  group('dart_error_unwrap — converted Future', () {
    test('desembrulha Exception interna para mensagem legível', () {
      const inner = 'Estoque insuficiente para "Pingente". Disponível: 0, solicitado: 2.';
      final wrapped = _FakeConvertedFutureError(Exception(inner));

      expect(
        formatDartErrorForUser(wrapped),
        contains('Estoque insuficiente'),
      );
      expect(
        formatDartErrorForUser(wrapped),
        isNot(contains('converted Future')),
      );
    });
  });

  group('baixa estoque — produto simples qtd == estoque', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
    });

    tearDown(() {
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      EstoqueTransactionService.debugFirestoreOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = null;
    });

    test('vende quantidade 2 com estoque remoto 2 e zera sem erro', () async {
      const productId = 'pingente-menino-pedra-azul';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .set({
        'nome': 'Pingente Menino Pedra Azul',
        'slug': 'pingente-menino-pedra-azul',
        'quantidade': 2,
      });

      final produto = Produto.vazio()
        ..nome = 'Pingente Menino Pedra Azul'
        ..idFirebase = productId
        ..slug = 'pingente-menino-pedra-azul'
        ..lojaId = lojaId
        ..quantidade = 2;

      final txItems = VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
        itensParaEstoque: [
          VendaItem(
            produtoNome: produto.nome,
            precoUnitario: 62.9,
            quantidade: 2,
          ),
        ],
        produtosEncontrados: [produto],
      );

      final results = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: lojaId,
        itens: txItems,
      );

      expect(results, hasLength(1));
      expect(results.first.quantidadeDebitada, 2);
      expect(results.first.quantidadeTotalAtualizada, 0);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 0);
    });
  });

  group('combo legado pendente na nuvem — teto pós-baixa', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> box;

    setUpAll(() async {
      final dir = await Directory.systemTemp
          .createTemp('hive_venda_combo_pendente_');
      hivePath = dir.path;
      Hive.init(hivePath);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }
    });

    tearDownAll(() async {
      try {
        await Directory(hivePath).delete(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      final boxName = 'produtos_${DateTime.now().microsecondsSinceEpoch}';
      box = await Hive.openBox<Produto>(boxName);
    });

    tearDown(() async {
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      EstoqueTransactionService.debugFirestoreOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = null;
      await box.close();
    });

    test(
      'aplicarTeto direto recalcula combo só-Hive localmente sem lançar',
      () async {
        const idPingente = 'pingente-lanca';
        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(idPingente)
            .set({'nome': 'Pingente', 'quantidade': 5});

        final pingente = Produto.vazio()
          ..nome = 'Pingente'
          ..idFirebase = idPingente
          ..lojaId = lojaId
          ..quantidade = 5;
        final colar = Produto.vazio()
          ..nome = 'Colar Combo'
          ..idFirebase = 'combo-so-hive'
          ..lojaId = lojaId
          ..tipoProduto = 'combo'
          ..quantidade = 5
          ..itensCombo = [
            {'productId': idPingente, 'nome': 'Pingente', 'quantidade': 1},
          ];
        await box.addAll([pingente, colar]);

        await EstoqueTransactionService.baixarEstoqueTransactionBatch(
          lojaId: lojaId,
          itens: [
            {'productId': idPingente, 'nome': 'Pingente', 'quantidade': 4},
          ],
        );
        pingente.quantidade = 1;

        final cap = await ComboKitStockService.aplicarTetoEstoqueComboAposBaixa(
          lojaId: lojaId,
          produtosBox: box,
          produtoIdsDebitadosNaVenda: {idPingente},
        );

        expect(cap, hasLength(1));
        expect(cap.first.ajusteCapComboSomenteHive, isTrue);
        expect(colar.quantidade, 1);
      },
    );

    test(
      'SemAbortarVenda aplica teto local quando combo só está no Hive',
      () async {
        const idPingente = 'pingente-sem-abort';
        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(idPingente)
            .set({'nome': 'Pingente Menino Pedra Azul', 'quantidade': 5});

        final pingente = Produto.vazio()
          ..nome = 'Pingente Menino Pedra Azul'
          ..idFirebase = idPingente
          ..lojaId = lojaId
          ..quantidade = 5;
        final colar = Produto.vazio()
          ..nome = 'Colar São Bento 60cm'
          ..idFirebase = 'combo-local-pendente-sync'
          ..lojaId = lojaId
          ..tipoProduto = 'combo'
          ..quantidade = 5
          ..itensCombo = [
            {
              'productId': idPingente,
              'nome': 'Pingente Menino Pedra Azul',
              'quantidade': 1,
            },
          ];
        await box.addAll([pingente, colar]);

        await EstoqueTransactionService.baixarEstoqueTransactionBatch(
          lojaId: lojaId,
          itens: [
            {
              'productId': idPingente,
              'nome': pingente.nome,
              'quantidade': 4,
            },
          ],
        );
        pingente.quantidade = 1;

        final cap =
            await ComboKitStockService.aplicarTetoEstoqueComboAposBaixaSemAbortarVenda(
          lojaId: lojaId,
          produtosBox: box,
          produtoIdsDebitadosNaVenda: {idPingente},
        );

        expect(cap, hasLength(1));
        expect(colar.quantidade, 1);
      },
    );

    test(
      'após venda do componente, combo só-local recalcula teto no Hive',
      () async {
        const idPingente = 'pingente-sync-ok';
        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(idPingente)
            .set({
          'nome': 'Pingente Menino Pedra Azul',
          'slug': 'pingente-menino-pedra-azul',
          'quantidade': 5,
        });

        final pingente = Produto.vazio()
          ..nome = 'Pingente Menino Pedra Azul'
          ..idFirebase = idPingente
          ..slug = 'pingente-menino-pedra-azul'
          ..lojaId = lojaId
          ..quantidade = 5;

        // Combo legado (sem comboConfig): só Hive, id local inexistente na nuvem.
        // quantidade cadastrada (5) > teto K após venda (1) → força ajuste pós-baixa.
        final colar = Produto.vazio()
          ..nome = 'Colar São Bento 60cm'
          ..idFirebase = 'combo-local-pendente-sync'
          ..slug = 'colar-sao-bento-60cm'
          ..lojaId = lojaId
          ..tipoProduto = 'combo'
          ..quantidade = 5
          ..itensCombo = [
            {
              'productId': idPingente,
              'nome': 'Pingente Menino Pedra Azul',
              'quantidade': 1,
            },
          ];

        await box.addAll([pingente, colar]);

        await EstoqueTransactionService.baixarEstoqueTransactionBatch(
          lojaId: lojaId,
          itens: [
            {
              'productId': idPingente,
              'nome': pingente.nome,
              'quantidade': 4,
            },
          ],
        );
        pingente.quantidade = 1;

        final cap = await ComboKitStockService.aplicarTetoEstoqueComboAposBaixa(
          lojaId: lojaId,
          produtosBox: box,
          produtoIdsDebitadosNaVenda: {idPingente},
        );

        expect(cap, hasLength(1));
        expect(colar.quantidade, 1);
        expect(cap.first.quantidadeTotalAtualizada, 1);
      },
    );

    test('kit por receita (comboConfig) não entra no teto legado após baixa', () async {
      const idFilho = 'filho-kit-receita';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(idFilho)
          .set({
        'nome': 'Componente Kit',
        'quantidade': 10,
      });

      final filho = Produto.vazio()
        ..nome = 'Componente Kit'
        ..idFirebase = idFilho
        ..lojaId = lojaId
        ..quantidade = 10;

      final kitReceita = Produto.vazio()
        ..nome = 'Colar São Bento 60cm'
        ..idFirebase = 'combo-config-local-only'
        ..lojaId = lojaId
        ..tipoProduto = 'combo'
        ..quantidade = 99
        ..itensCombo = [
          {'productId': idFilho, 'nome': 'Componente Kit', 'quantidade': 1},
        ]
        ..comboConfig = {
          'grupos': [
            {
              'id': 'g1',
              'nome': 'Escolha',
              'min': 1,
              'max': 1,
              'itens': [
                {'productId': idFilho, 'nome': 'Componente Kit'},
              ],
            },
          ],
        };

      await box.addAll([filho, kitReceita]);

      await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: lojaId,
        itens: [
          {'productId': idFilho, 'nome': filho.nome, 'quantidade': 1},
        ],
      );

      final extra = await ComboKitStockService.aplicarTetoEstoqueComboAposBaixa(
        lojaId: lojaId,
        produtosBox: box,
        produtoIdsDebitadosNaVenda: {idFilho},
      );

      expect(extra, isEmpty);
    });
  });

  group('expandirCombos — filho ausente no Hive', () {
    late String hivePath;
    late Box<Produto> box;

    setUpAll(() async {
      final dir =
          await Directory.systemTemp.createTemp('hive_venda_combo_filho_');
      hivePath = dir.path;
      Hive.init(hivePath);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }
    });

    tearDownAll(() async {
      try {
        await Directory(hivePath).delete(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      final boxName = 'produtos_${DateTime.now().microsecondsSinceEpoch}';
      box = await Hive.openBox<Produto>(boxName);
    });

    tearDown(() async {
      await box.close();
    });

    test('erro específico quando item da receita não está no estoque local', () {
      final combo = Produto.vazio()
        ..nome = 'Combo Teste'
        ..idFirebase = 'combo-1'
        ..lojaId = lojaId
        ..tipoProduto = 'combo'
        ..precoFinal = 100
        ..itensCombo = [
          {
            'nome': 'Filho Inexistente',
            'productId': 'filho-nao-cadastrado',
            'quantidade': 1,
          },
        ];
      box.add(combo);

      expect(
        () => VendaComboEstoqueExpansion.expandirCombos(
          itens: [
            VendaItem(
              produtoNome: 'Combo Teste',
              quantidade: 1,
              precoUnitario: 100,
              productId: 'combo-1',
            ),
          ],
          produtosBox: box,
          lojaId: lojaId,
        ),
        throwsA(
          predicate(
            (e) =>
                e is Exception &&
                e.toString().contains('Produto do combo não encontrado'),
          ),
        ),
      );
    });
  });

  group('ordem VendasService.registrarVendaMulti', () {
    test('baixa de estoque ocorre antes de vendasBox.add (sem salvar parcial)', () {
      const fonte = '''
    final txResults = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
    await vendasBox.add(venda);
''';
      final idxBaixa = fonte.indexOf('baixarEstoqueTransactionBatch');
      final idxAdd = fonte.indexOf('vendasBox.add');
      expect(idxBaixa >= 0, isTrue);
      expect(idxAdd > idxBaixa, isTrue);
    });

    test('registrarVendaMulti chama teto SemAbortarVenda antes de vendasBox.add', () {
      final src = File(
        'lib/services/vendas_service.dart',
      ).readAsStringSync();
      final iBaixa = src.indexOf('baixarEstoqueTransactionBatch');
      final iTeto = src.indexOf(
        'aplicarTetoEstoqueComboAposBaixaSemAbortarVenda',
      );
      final iAdd = src.indexOf('await vendasBox.add(venda)');
      expect(iBaixa, greaterThan(-1));
      expect(iTeto, greaterThan(iBaixa));
      expect(iAdd, greaterThan(iTeto));
    });
  });

  group('VendasService.registrarVendaMulti — teto combo não aborta venda', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir =
          await Directory.systemTemp.createTemp('hive_venda_registrar_multi_');
      hivePath = dir.path;
      Hive.init(hivePath);
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(ClienteAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(VendaAdapter());
      }
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }
      if (!Hive.isAdapterRegistered(7)) {
        Hive.registerAdapter(VendaItemAdapter());
      }
    });

    tearDownAll(() async {
      try {
        await Directory(hivePath).delete(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      LojaAtivaResolver.debugResolveOverride =
          ({String origem = 'app'}) async => lojaId;
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      final suffix = DateTime.now().microsecondsSinceEpoch;
      produtosBox = await Hive.openBox<Produto>('produtos_$suffix');
      clientesBox = await Hive.openBox<Cliente>('clientes_$suffix');
      vendasBox = await Hive.openBox<Venda>('vendas_$suffix');
    });

    tearDown(() async {
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      LojaAtivaResolver.debugResolveOverride = null;
      EstoqueTransactionService.debugFirestoreOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = null;
      await produtosBox.close();
      await clientesBox.close();
      await vendasBox.close();
    });

    Future<Cliente> criarClienteTeste() async {
      final c = Cliente(
        nome: 'Cliente Teste',
        telefone: '11999999999',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: lojaId,
      );
      await clientesBox.add(c);
      return c;
    }

    test('produto simples qtd 2 com estoque 2 salva venda e zera estoque remoto', () async {
      const productId = 'pingente-venda-2';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .set({
        'nome': 'Pingente Menino Pedra Azul',
        'quantidade': 2,
      });

      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Pingente Menino Pedra Azul'
          ..idFirebase = productId
          ..lojaId = lojaId
          ..quantidade = 2
          ..precoFinal = 62.9,
      );

      final cliente = await criarClienteTeste();
      final venda = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Pingente Menino Pedra Azul',
            quantidade: 2,
            precoUnitario: 62.9,
            productId: productId,
          ),
        ],
        dinheiro: 125.8,
        lojaId: lojaId,
      );

      expect(vendasBox.length, 1);
      expect(venda.itens?.first.quantidade, 2);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 0);
    });

    test(
      'componente de combo legado só-local: venda salva mesmo se teto do combo falhar',
      () async {
        const idPingente = 'pingente-combo-legado';
        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(idPingente)
            .set({'nome': 'Pingente Menino Pedra Azul', 'quantidade': 5});

        await produtosBox.addAll([
          Produto.vazio()
            ..nome = 'Pingente Menino Pedra Azul'
            ..idFirebase = idPingente
            ..lojaId = lojaId
            ..quantidade = 5
            ..precoFinal = 62.9,
          Produto.vazio()
            ..nome = 'Colar São Bento 60cm'
            ..idFirebase = 'combo-local-only'
            ..lojaId = lojaId
            ..tipoProduto = 'combo'
            ..quantidade = 5
            ..itensCombo = [
              {
                'productId': idPingente,
                'nome': 'Pingente Menino Pedra Azul',
                'quantidade': 1,
              },
            ],
        ]);

        final cliente = await criarClienteTeste();
        final venda = await VendasService.registrarVendaMulti(
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: cliente.nome,
          clienteExistente: cliente,
          itens: [
            VendaItem(
              produtoNome: 'Pingente Menino Pedra Azul',
              quantidade: 2,
              precoUnitario: 62.9,
              productId: idPingente,
            ),
          ],
          dinheiro: 125.8,
          lojaId: lojaId,
        );

        expect(vendasBox.length, 1);
        expect(venda, isNotNull);

        final snap = await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(idPingente)
            .get();
        expect((snap.data()?['quantidade'] as num?)?.toInt(), 3);

        final comboLocal = produtosBox.values.firstWhere(
          (p) => p.idFirebase == 'combo-local-only',
        );
        expect(comboLocal.quantidade, 3);

        final snapCombo = await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc('combo-local-only')
            .get();
        expect(snapCombo.exists, isTrue);
        expect((snapCombo.data()?['quantidade'] as num?)?.toInt(), 3);
      },
    );

    test(
      'produto só Hive: prep sincroniza na nuvem antes da baixa e venda conclui',
      () async {
        await produtosBox.add(
          Produto.vazio()
            ..nome = 'Produto Fantasma'
            ..idFirebase = 'id-so-hive'
            ..lojaId = lojaId
            ..quantidade = 3
            ..precoFinal = 10,
        );

        final cliente = await criarClienteTeste();
        await VendasService.registrarVendaMulti(
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: cliente.nome,
          clienteExistente: cliente,
          itens: [
            VendaItem(
              produtoNome: 'Produto Fantasma',
              quantidade: 1,
              precoUnitario: 10,
              productId: 'id-so-hive',
            ),
          ],
          dinheiro: 10,
          lojaId: lojaId,
        );

        expect(vendasBox.length, 1);
        final snap = await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc('id-so-hive')
            .get();
        expect(snap.exists, isTrue);
      },
    );

    test('estoque insuficiente bloqueia venda', () async {
      const productId = 'prod-estoque-baixo';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .set({'nome': 'Item Escasso', 'quantidade': 1});

      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Item Escasso'
          ..idFirebase = productId
          ..lojaId = lojaId
          ..quantidade = 1
          ..precoFinal = 5,
      );

      final cliente = await criarClienteTeste();
      expect(
        VendasService.registrarVendaMulti(
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: cliente.nome,
          clienteExistente: cliente,
          itens: [
            VendaItem(
              produtoNome: 'Item Escasso',
              quantidade: 3,
              precoUnitario: 5,
              productId: productId,
            ),
          ],
          dinheiro: 15,
          lojaId: lojaId,
        ),
        throwsA(
          predicate(
            (e) =>
                e.toString().toLowerCase().contains('insuficiente') ||
                e.toString().toLowerCase().contains('estoque'),
          ),
        ),
      );
      expect(vendasBox.length, 0);
    });

    test('variação tombstonada sem célula ativa no remoto bloqueia venda', () async {
      const productId = 'anel-tombstone-bloqueio';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.exclusaoProdutoCol)
          .doc(productId)
          .set({
        'p': false,
        'v': {
          ProdutoExclusaoTombstoneService.vKeyCelula('18', 'sem-cor'): true,
        },
      });
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .set({
        'nome': 'Anel Tombstone',
        'quantidade': 0,
        'variacoes': <String, dynamic>{},
      });

      await produtosBox.add(
        Produto(
          nome: 'Anel Tombstone',
          custoReal: 1,
          frete: 0,
          gastosFixos: 0,
          gastosVariaveis: 0,
          precoSugerido: 0,
          precoFinal: 50,
          quantidade: 1,
          precoUnitario: 50,
          categoria: '',
          dataEntrada: DateTime(2026, 6, 1),
          lojaId: lojaId,
          idFirebase: productId,
          variacoes: {
            '18': {
              'sem-cor': 1,
            },
          },
        ),
      );

      final cliente = await criarClienteTeste();
      expect(
        VendasService.registrarVendaMulti(
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: cliente.nome,
          clienteExistente: cliente,
          itens: [
            VendaItem(
              produtoNome: 'Anel Tombstone',
              quantidade: 1,
              precoUnitario: 50,
              tamanho: '18',
              cor: 'sem-cor',
              productId: productId,
            ),
          ],
          dinheiro: 50,
          lojaId: lojaId,
        ),
        throwsA(isA<Exception>()),
      );
      expect(vendasBox.length, 0);
    });
  });

  group('M2.5 — convergência combo só-Hive → Firestore', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir =
          await Directory.systemTemp.createTemp('hive_m25_combo_converge_');
      hivePath = dir.path;
      Hive.init(hivePath);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
      if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
    });

    tearDownAll(() async {
      try {
        await Directory(hivePath).delete(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      ComboKitStockService.debugEnfileirarConvergenciaComboOverride = null;
      LojaAtivaResolver.debugResolveOverride =
          ({String origem = 'app'}) async => lojaId;
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;
      await SyncQueueService.init();
      await SyncQueueService.clearQueue();

      final suffix = DateTime.now().microsecondsSinceEpoch;
      produtosBox = await Hive.openBox<Produto>('m25_prod_$suffix');
      clientesBox = await Hive.openBox<Cliente>('m25_cli_$suffix');
      vendasBox = await Hive.openBox<Venda>('m25_ven_$suffix');
    });

    tearDown(() async {
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      ComboKitStockService.debugEnfileirarConvergenciaComboOverride = null;
      LojaAtivaResolver.debugResolveOverride = null;
      EstoqueTransactionService.debugFirestoreOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = null;
      ProdutoExclusaoTombstoneService.debugFirestoreOverride = null;
      await SyncQueueService.clearQueue();
      await produtosBox.close();
      await clientesBox.close();
      await vendasBox.close();
    });

    Future<Cliente> clienteM25() async {
      final c = Cliente(
        nome: 'Cliente M25',
        telefone: '11',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: lojaId,
      );
      await clientesBox.add(c);
      return c;
    }

    Future<Map<String, dynamic>?> fsComboData(String id) async {
      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .get();
      return snap.exists ? snap.data() : null;
    }

    test('M2.5 — venda componente converge combo Hive e cria Firestore', () async {
      const idComp = 'comp-m25-converge';
      const idCombo = 'combo-m25-converge';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(idComp)
          .set({'nome': 'Comp', 'quantidade': 5});

      await produtosBox.addAll([
        Produto.vazio()
          ..nome = 'Comp'
          ..idFirebase = idComp
          ..lojaId = lojaId
          ..quantidade = 5
          ..precoFinal = 10,
        Produto.vazio()
          ..nome = 'Colar Combo'
          ..idFirebase = idCombo
          ..lojaId = lojaId
          ..tipoProduto = 'combo'
          ..quantidade = 5
          ..precoFinal = 50
          ..itensCombo = [
            {'productId': idComp, 'nome': 'Comp', 'quantidade': 1},
          ],
      ]);

      final c = await clienteM25();
      await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: [
          VendaItem(
            produtoNome: 'Comp',
            quantidade: 2,
            precoUnitario: 10,
            productId: idComp,
          ),
        ],
        dinheiro: 20,
        lojaId: lojaId,
      );

      final comboHive = produtosBox.values.firstWhere(
        (p) => p.idFirebase == idCombo,
      );
      expect(comboHive.quantidade, 3);

      final fsCombo = await fsComboData(idCombo);
      expect(fsCombo, isNotNull);
      expect((fsCombo!['quantidade'] as num?)?.toInt(), 3);
    });

    test('M2.5 — retry idempotente não reduz combo novamente', () async {
      const idComp = 'comp-m25-idem';
      const idCombo = 'combo-m25-idem';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(idComp)
          .set({'nome': 'Comp', 'quantidade': 5});

      final combo = Produto.vazio()
        ..nome = 'Colar'
        ..idFirebase = idCombo
        ..lojaId = lojaId
        ..tipoProduto = 'combo'
        ..quantidade = 5
        ..itensCombo = [
          {'productId': idComp, 'nome': 'Comp', 'quantidade': 1},
        ];
      await produtosBox.addAll([
        Produto.vazio()
          ..nome = 'Comp'
          ..idFirebase = idComp
          ..lojaId = lojaId
          ..quantidade = 3,
        combo,
      ]);

      await ComboKitStockService.aplicarTetoEstoqueComboAposBaixa(
        lojaId: lojaId,
        produtosBox: produtosBox,
        produtoIdsDebitadosNaVenda: {idComp},
      );
      expect(combo.quantidade, 3);

      await ProdutosFirestoreService.syncProdutoComStatus(
        combo,
        lojaId: lojaId,
        bumpHiveTimestamp: false,
      );
      await ProdutosFirestoreService.syncProdutoComStatus(
        combo,
        lojaId: lojaId,
        bumpHiveTimestamp: false,
      );

      expect(combo.quantidade, 3);
      final fs = await fsComboData(idCombo);
      expect((fs?['quantidade'] as num?)?.toInt(), 3);
    });

    test('M2.5 — remoto mais novo não é sobrescrito por local stale', () async {
      const idComp = 'comp-m25-stale';
      const idCombo = 'combo-m25-stale';
      final remotoMaisNovo = DateTime.now().add(const Duration(hours: 2));

      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(idComp)
          .set({'nome': 'Comp', 'quantidade': 3});
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(idCombo)
          .set({
        'nome': 'Colar',
        'quantidade': 10,
        'updatedAt': remotoMaisNovo,
      });

      final combo = Produto.vazio()
        ..nome = 'Colar'
        ..idFirebase = idCombo
        ..lojaId = lojaId
        ..tipoProduto = 'combo'
        ..quantidade = 3
        ..updatedAt = DateTime.now().subtract(const Duration(hours: 1))
        ..itensCombo = [
          {'productId': idComp, 'nome': 'Comp', 'quantidade': 1},
        ];
      await produtosBox.add(combo);

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        combo,
        lojaId: lojaId,
        bumpHiveTimestamp: false,
      );

      expect(status, ProdutoSyncRemotoStatus.semMudancas);
      final fs = await fsComboData(idCombo);
      expect((fs?['quantidade'] as num?)?.toInt(), 10);
    });

    test('M2.5 — tombstone não ressuscita combo remoto', () async {
      const idCombo = 'combo-m25-tomb';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.exclusaoProdutoCol)
          .doc(idCombo)
          .set({'p': true});
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;
      await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);

      final combo = Produto.vazio()
        ..nome = 'Colar Tomb'
        ..idFirebase = idCombo
        ..lojaId = lojaId
        ..tipoProduto = 'combo'
        ..quantidade = 3
        ..itensCombo = [
          {'productId': 'x', 'nome': 'X', 'quantidade': 1},
        ];
      await produtosBox.add(combo);

      final cap = await ComboKitStockService.aplicarTetoEstoqueComboAposBaixa(
        lojaId: lojaId,
        produtosBox: produtosBox,
        produtoIdsDebitadosNaVenda: {'x'},
      );

      expect(cap, isEmpty);
      expect(combo.quantidade, 3);
      expect(await fsComboData(idCombo), isNull);
    });
  });
}
