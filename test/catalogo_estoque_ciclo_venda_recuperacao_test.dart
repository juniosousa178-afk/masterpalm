// Ciclo estoque → venda → catálogo público → falha de sync → recuperação.
// Hive isolado + Firestore fake. Não acessa produção.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';
import 'package:master_palm/services/catalog_publish_service.dart';
import 'package:master_palm/services/catalogo_sync_service.dart';
import 'package:master_palm/services/catalogo_web_apos_estoque_service.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-ciclo-cat-estoque';
const _pid = 'anel-p-azul';
const _tam = 'P';
const _cor = 'Azul';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late String hivePath;
  late Box<Produto> produtosBox;
  late Box<Cliente> clientesBox;
  late Box<Venda> vendasBox;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_ciclo_cat_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
  });

  tearDownAll(() async {
    LojaAtivaResolver.debugResolveOverride = null;
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  Future<bool> liveExists() async {
    return (await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('produtos')
            .doc(_pid)
            .get())
        .exists;
  }

  Future<int> qtdEstoque() async {
    final snap = await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(_pid)
        .get();
    return (snap.data()?['quantidade'] as num?)?.toInt() ?? -1;
  }

  Future<void> publicarDoHive() async {
    final p = produtosBox.values.firstWhere((e) => e.idFirebase == _pid);
    await CatalogoSyncService.syncProduto(
      p,
      target: SyncTarget.draft,
      lojaIdOverride: _lojaId,
    );
    await CatalogPublishService.promoteOne(_pid, lojaIdOverride: _lojaId);
  }

  Future<void> seedProduto({
    required int qtd,
    required bool publicado,
  }) async {
    final vars = {
      _tam: {_cor: qtd},
    };
    await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(_pid)
        .set({
      'nome': 'Anel P Azul',
      'quantidade': qtd,
      'slug': _pid,
      'variacoes': vars,
      'estoquePorTamanho': {_tam: qtd},
    });
    await produtosBox.add(
      Produto.vazio()
        ..nome = 'Anel P Azul'
        ..idFirebase = _pid
        ..slug = _pid
        ..lojaId = _lojaId
        ..quantidade = qtd
        ..precoFinal = 40
        ..publicadoNoCatalogo = publicado
        ..variacoes = {
          _tam: {_cor: qtd},
        }
        ..estoquePorTamanho = {_tam: qtd},
    );
    if (publicado && qtd > 0) {
      await publicarDoHive();
    }
  }

  Future<Cliente> cliente() async {
    final c = Cliente(
      nome: 'Cliente Ciclo',
      telefone: '11999990001',
      instagram: '',
      cep: '',
      cidade: '',
      lojaId: _lojaId,
    );
    await clientesBox.add(c);
    return c;
  }

  Future<void> reporUmaUnidade({required bool publicado}) async {
    final p = produtosBox.values.firstWhere((e) => e.idFirebase == _pid);
    p.quantidade = 1;
    p.variacoes = {
      _tam: {_cor: 1},
    };
    p.estoquePorTamanho = {_tam: 1};
    p.publicadoNoCatalogo = publicado;
    await p.save();
    await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(_pid)
        .set({
      'nome': p.nome,
      'quantidade': 1,
      'slug': _pid,
      'variacoes': {
        _tam: {_cor: 1},
      },
      'estoquePorTamanho': {_tam: 1},
    }, SetOptions(merge: true));
    await CatalogoWebAposEstoqueService.sincronizarCatalogoWebAposMudancaEstoque(
      lojaId: _lojaId,
      productIdsAfetados: {_pid},
      produtosBox: produtosBox,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LojaAtivaResolver.debugResolveOverride =
        ({String origem = 'app'}) async => _lojaId;
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    firestore = FakeFirebaseFirestore();
    EstoqueTransactionService.debugFirestoreOverride = firestore;
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    CatalogoSyncService.debugFirestoreOverride = firestore;
    CatalogPublishService.debugFirestoreOverride = firestore;
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;
    CatalogoWebAposEstoqueService.debugClearOverrides();
    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBox = await Hive.openBox<Produto>('p_ciclo_$s');
    clientesBox = await Hive.openBox<Cliente>('c_ciclo_$s');
    vendasBox = await Hive.openBox<Venda>('v_ciclo_$s');
    if (Hive.isBoxOpen(HiveBoxNames.config())) {
      await Hive.box(HiveBoxNames.config()).clear();
    }
  });

  tearDown(() async {
    CatalogoWebAposEstoqueService.debugClearOverrides();
    VendasService.debugVendasBoxAddOverride = null;
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    LojaAtivaResolver.debugResolveOverride = null;
    EstoqueTransactionService.debugFirestoreOverride = null;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    CatalogoSyncService.debugFirestoreOverride = null;
    CatalogPublishService.debugFirestoreOverride = null;
    if (Hive.isBoxOpen(HiveBoxNames.config())) {
      await Hive.box(HiveBoxNames.config()).clear();
    }
    await produtosBox.close();
    await clientesBox.close();
    await vendasBox.close();
  });

  test(
    'ciclo: publicar 1 unidade, vender, falha de catálogo, recuperar, repor',
    () async {
      await seedProduto(qtd: 1, publicado: true);
      expect(await liveExists(), isTrue);
      expect(await qtdEstoque(), 1);

      var syncFalhou = 0;
      CatalogoWebAposEstoqueService.debugBeforeProductSync = (_) async {
        syncFalhou++;
        throw StateError('catalogo indisponivel');
      };

      final c = await cliente();
      await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: [
          VendaItem(
            produtoNome: 'Anel P Azul',
            quantidade: 1,
            precoUnitario: 40,
            productId: _pid,
            tamanho: _tam,
            cor: _cor,
          ),
        ],
        dinheiro: 40,
        lojaId: _lojaId,
      );

      expect(vendasBox.length, 1);
      expect(await qtdEstoque(), 0);
      expect(await liveExists(), isFalse);
      expect(produtosBox.values.first.quantidade, 0);
      expect(syncFalhou, 1);
      expect(await CatalogPublishService.catalogoPrecisaAtualizar, isTrue);
      final pendentes = await CatalogPublishService.lerPendenciasSyncAposEstoque();
      expect(pendentes[_lojaId], contains(_pid));

      CatalogoWebAposEstoqueService.debugBeforeProductSync = null;
      await CatalogoWebAposEstoqueService.tentarRecuperarPendencias(
        lojaId: _lojaId,
        produtosBox: produtosBox,
      );

      expect(await qtdEstoque(), 0, reason: 'recuperação não debita de novo');
      expect(produtosBox.values.first.quantidade, 0);
      expect(await liveExists(), isFalse);
      expect(
        (await CatalogPublishService.lerPendenciasSyncAposEstoque())[_lojaId] ??
            const <String>{},
        isEmpty,
      );

      await reporUmaUnidade(publicado: true);
      expect(await qtdEstoque(), 1);
      expect(await liveExists(), isTrue);
      final live = (await firestore
              .collection('lojas')
              .doc(_lojaId)
              .collection('produtos')
              .doc(_pid)
              .get())
          .data();
      expect(
        CatalogEstoqueHelper.processStockFromFirestoreMap(
          Map<String, dynamic>.from(live!),
          isCombo: false,
        ).incluirNoCatalogo,
        isTrue,
      );
    },
  );

  test('reposição com publicadoNoCatalogo=false não volta ao live', () async {
    await seedProduto(qtd: 0, publicado: false);
    expect(await liveExists(), isFalse);

    await reporUmaUnidade(publicado: false);

    expect(await qtdEstoque(), 1);
    expect(produtosBox.values.first.publicadoNoCatalogo, isFalse);
    expect(await liveExists(), isFalse);
  });
}
