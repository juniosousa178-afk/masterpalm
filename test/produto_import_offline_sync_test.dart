// Importação offline: zero Firestore, docId local, fila pendente.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/firestore_access_guard.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/produto_firestore_doc_id_validator.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/produto_import_doc_id_helper.dart';
import 'package:master_palm/services/produto_import_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/sync_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-import-offline';
  late String hivePath;
  late Box<Produto> produtosBox;
  late Box<Venda> vendasBox;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_import_offline_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(VendaAdapter());
    }
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FirestoreAccessGuard.resetForTests();
    ProdutosFirestoreService.debugForbidFirestoreAccess = true;
    ProdutosFirestoreService.debugFirestoreOverride = null;

    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBox = await Hive.openBox<Produto>('p_off_$s');
    vendasBox = await Hive.openBox<Venda>('v_off_$s');
    await SyncQueueService.init();
    await SyncQueueService.clearQueue();
  });

  tearDown(() async {
    ProdutosFirestoreService.debugForbidFirestoreAccess = false;
    FirestoreAccessGuard.resetForTests();
    await SyncQueueService.clearQueue();
    await produtosBox.close();
    await vendasBox.close();
  });

  Produto linha({required String nome}) {
    return Produto(
      nome: nome,
      custoReal: 5,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 25,
      quantidade: 2,
      precoUnitario: 25,
      categoria: 'Cat',
      dataEntrada: DateTime.now(),
      lojaId: lojaId,
    );
  }

  test('importação offline: 0 Firestore, docId import-*, fila pendente', () async {
    const skuInseguro = 'ABC/123';
    const codigoUrl = 'https://cdn.example.com/barcode.jpg';
    final acessosAntes = ProdutosFirestoreService.debugFirestoreAccessCount;

    final rSku = await ProdutoImportService.processarLinha(
      linha: 1,
      produto: linha(nome: 'Produto SKU Barra Offline'),
      lojaId: lojaId,
      produtosBox: produtosBox,
      vendasBox: vendasBox,
      sku: skuInseguro,
    );

    final rCodigo = await ProdutoImportService.processarLinha(
      linha: 2,
      produto: linha(nome: 'Produto Codigo URL Offline'),
      lojaId: lojaId,
      produtosBox: produtosBox,
      vendasBox: vendasBox,
      codigoBarras: codigoUrl,
    );

    expect(ProdutosFirestoreService.debugFirestoreAccessCount, acessosAntes);

    for (final r in [rSku, rCodigo]) {
      expect(r.status, ProdutoImportLinhaStatus.pendenteSincronizacao);
      final p = r.produto!;
      expect(ProdutoImportDocIdHelper.isDocIdLocalImportacao(p.slug), isTrue);
      expect(ProdutoFirestoreDocIdValidator.isProdutoIdSeguro(p.slug), isTrue);
      expect(p.slug.contains('/'), isFalse);
      expect(p.slug.contains('://'), isFalse);
      expect(p.idFirebase, isEmpty);
    }

    expect(rSku.produto!.sku, skuInseguro);
    expect(rCodigo.produto!.codigoBarras, codigoUrl);
    expect(produtosBox.length, 2);
    expect(await SyncQueueService.activePendingCount(), 2);
  });
}
