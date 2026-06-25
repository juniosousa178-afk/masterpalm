// Importação em lote: processamento único e escopo de loja.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/firestore_access_guard.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/produto_import_doc_id_helper.dart';
import 'package:master_palm/services/produto_import_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-import-lote';
  late String hivePath;
  late Box<Produto> produtosBox;
  late Box<Venda> vendasBox;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_import_lote_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  Produto linha({required String nome}) => Produto(
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

  setUp(() async {
    FirestoreAccessGuard.resetForTests();
    ProdutosFirestoreService.debugForbidFirestoreAccess = true;
    SyncQueueService.resetProcessRequestCountForTests();

    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId) + '_$s');
    vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId) + '_$s');
    await SyncQueueService.init();
    await SyncQueueService.clearQueue();
  });

  tearDown(() async {
    ProdutosFirestoreService.debugForbidFirestoreAccess = false;
    await SyncQueueService.clearQueue();
    await produtosBox.close();
    await vendasBox.close();
  });

  test('lote offline: 5 linhas, zero Firestore, fila por produto', () async {
    await SyncQueueService.runWithDeferredQueueProcessing(() async {
      for (var i = 1; i <= 5; i++) {
        await ProdutoImportService.processarLinha(
          linha: i,
          produto: linha(nome: 'Prod $i'),
          produtosBox: produtosBox,
          vendasBox: vendasBox,
          lojaId: lojaId,
        );
      }
    });

    expect(FirestoreAccessGuard.accessCount, 0);
    expect(produtosBox.length, 5);
    for (final p in produtosBox.values) {
      expect(ProdutoImportDocIdHelper.isDocIdLocalImportacao(p.slug), isTrue);
    }
    final fila = await SyncQueueService.listDiagnosticEntries();
    expect(fila.length, 5);
    expect(SyncQueueService.debugProcessRequestCount, 0);

    SyncQueueService.requestProcessWhenOnline(lojaId: lojaId);
    expect(SyncQueueService.debugProcessRequestCount, 1);
  });

  test('escopo de loja: processPending ignora outra loja', () async {
    const outra = 'outra-loja';
    final p1 = linha(nome: 'A');
    final boxOutra = await Hive.openBox<Produto>(HiveBoxNames.produtos(outra));
    final p2 = linha(nome: 'B')..lojaId = outra;
    await produtosBox.add(p1);
    await boxOutra.add(p2);

    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertProduto,
      lojaId: lojaId,
      boxName: produtosBox.name,
      entityKey: p1.key as int,
      scheduleProcess: false,
    );
    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertProduto,
      lojaId: outra,
      boxName: boxOutra.name,
      entityKey: p2.key as int,
      scheduleProcess: false,
    );

    ProdutosFirestoreService.debugForbidFirestoreAccess = true;
    await SyncQueueService.processPending(scopeLojaId: lojaId);
    final restantes = await SyncQueueService.listDiagnosticEntries();
    expect(restantes.where((e) => e.lojaId == outra).length, 1);
    expect(restantes.where((e) => e.lojaId == lojaId).length, 1);
    await boxOutra.close();
  });
}
