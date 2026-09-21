// Reprodução: pendência de estoque obsoleta vs consignado com qty remota canônica.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/features/consignments/consignment_eligibility.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/venda_estoque_remoto_prep_service.dart';

import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late String hivePath;
  late Box<Produto> box;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_pending_sale_');
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
    firestore = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    VendaEstoqueRemotoPrepService.debugPendingSaleBlockHook = null;
    box = await Hive.openBox<Produto>(
      'p_${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDown(() async {
    VendaEstoqueRemotoPrepService.debugPendingSaleBlockHook = null;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    await box.close();
  });

  group('TESTE A — venda / pending sync', () {
    test('pendência REAL (remoto ainda na base) continua bloqueando', () async {
      const lojaId = 'mirjoias';
      const docId = 'mirjoias-anel-an44sm';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId)
          .set({
        'quantidade': 0,
        'stockRevision': 2,
        'stockOperationId': 'remote-old',
        'nome': 'Anel Solitário Liso 6 Pontas T.22 Semijoia',
        'codigoBarras': 'AN44SM',
      });

      final p = Produto.vazio()
        ..nome = 'Anel Solitário Liso 6 Pontas T.22 Semijoia'
        ..codigoBarras = 'AN44SM'
        ..idFirebase = docId
        ..lojaId = lojaId
        ..quantidade = 1
        ..stockRevision = 2
        ..pendingStockOperationId = 'local-pending-unsynced'
        ..pendingStockBaseRevision = 2;
      await box.add(p);

      final diags = <Map<String, Object?>>[];
      VendaEstoqueRemotoPrepService.debugPendingSaleBlockHook = diags.add;

      final cleared =
          await VendaEstoqueRemotoPrepService.reconcilePendingStockMutationForSale(
        lojaId: lojaId,
        produto: p,
      );
      expect(cleared, isFalse);
      expect(hasPendingStockMutation(p), isTrue);
      expect(diags, isNotEmpty);
      expect(diags.first['codigo'], 'AN44SM');
      expect(diags.first['estoqueLocal'], 1);
      expect(diags.first['estoqueRemotoConhecido'], 0);
      expect(diags.first['pendingSync'], isTrue);
    });

    test(
        'pendência OBSOLETA (remoto avançou com outro op) é reconciliada e libera',
        () async {
      const lojaId = 'mirjoias';
      const docId = 'mirjoias-anel-an43sm';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId)
          .set({
        'quantidade': 1,
        'stockRevision': 3,
        'stockOperationId': 'repair_remote_op',
        'nome': 'Anel reparado',
        'codigoBarras': 'AN43SM',
      });

      final p = Produto.vazio()
        ..nome = 'Anel reparado'
        ..codigoBarras = 'AN43SM'
        ..idFirebase = docId
        ..lojaId = lojaId
        ..quantidade = 1
        ..stockRevision = 2
        ..pendingStockOperationId = 'stale-local-op'
        ..pendingStockBaseRevision = 2;
      await box.add(p);

      final cleared =
          await VendaEstoqueRemotoPrepService.reconcilePendingStockMutationForSale(
        lojaId: lojaId,
        produto: p,
      );
      expect(cleared, isTrue);
      expect(hasPendingStockMutation(p), isFalse);
      expect(p.quantidade, 1);
      expect(p.stockRevision, 3);
      expect(p.confirmedStockOperationId, 'repair_remote_op');
    });

    test('mesmo operationId confirmado no remoto limpa pendência', () async {
      const lojaId = 'mirjoias';
      const docId = 'p-same-op';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId)
          .set({
        'quantidade': 2,
        'stockRevision': 5,
        'stockOperationId': 'op-same',
      });

      final p = Produto.vazio()
        ..nome = 'X'
        ..idFirebase = docId
        ..lojaId = lojaId
        ..quantidade = 2
        ..stockRevision = 4
        ..pendingStockOperationId = 'op-same'
        ..pendingStockBaseRevision = 4;
      await box.add(p);

      final cleared =
          await VendaEstoqueRemotoPrepService.reconcilePendingStockMutationForSale(
        lojaId: lojaId,
        produto: p,
      );
      expect(cleared, isTrue);
      expect(hasPendingStockMutation(p), isFalse);
    });
  });

  group('TESTE B/D — consignado disponibilidade canônica', () {
    test('AN44SM com quantidade remota 0 → 0 disponíveis (não é bug de fórmula)',
        () {
      final item = evaluateConsignmentPickerItem(
        productId: 'mirjoias-anel-solit-rio-liso-6-pontas-t-22-semijoia',
        lojaId: 'mirjoias',
        stock: {
          'stockKind': 'simple',
          'stockRevision': 2,
          'quantidade': 0,
          'codigoBarras': 'AN44SM',
          'variacoes': {},
        },
        draft: {
          'nome': 'Anel Solitário Liso 6 Pontas T.22 Semijoia',
          'preco': 69,
          'codigoBarras': 'AN44SM',
        },
        dependency: {'comboIds': []},
      );
      expect(item.eligible, isFalse);
      expect(item.availableQty, 0);
      expect(item.unavailableReason, '0 disponíveis para consignação');
    });

    test('AN44SM com quantidade remota > 0 fica disponível', () {
      final item = evaluateConsignmentPickerItem(
        productId: 'mirjoias-anel-solit-rio-liso-6-pontas-t-22-semijoia',
        lojaId: 'mirjoias',
        stock: {
          'stockKind': 'simple',
          'stockRevision': 3,
          'quantidade': 2,
          'codigoBarras': 'AN44SM',
          'variacoes': {},
        },
        draft: {
          'nome': 'Anel Solitário Liso 6 Pontas T.22 Semijoia',
          'preco': 69,
          'codigoBarras': 'AN44SM',
        },
        dependency: {'comboIds': []},
      );
      expect(item.eligible, isTrue);
      expect(item.availableQty, 2);
    });
  });

  group('TESTE C — variação', () {
    test('picker usa soma de células da variação corretamente', () {
      final item = evaluateConsignmentPickerItem(
        productId: 'anel-var',
        lojaId: 'mirjoias',
        stock: {
          'stockKind': 'variation',
          'stockRevision': 1,
          'quantidade': 5,
          'variacoes': {
            '21': {'sem-cor': 2},
            '22': {'sem-cor': 3},
          },
        },
        draft: {'nome': 'Anel var', 'preco': 10},
        dependency: {'comboIds': []},
      );
      expect(item.eligible, isTrue);
      expect(item.availableQty, 5);
    });
  });
}
