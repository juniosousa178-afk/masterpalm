// Auto-sync de pendência de estoque antes da venda + mensagens amigáveis.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:master_palm/core/dart_error_unwrap.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/features/consignments/consignment_eligibility.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/venda_estoque_remoto_prep_service.dart';

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
    SharedPreferences.setMockInitialValues({});
    firestore = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    VendaEstoqueRemotoPrepService.debugPendingSaleBlockHook = null;
    VendaEstoqueRemotoPrepService.flushPendingStockMutationImpl = null;
    box = await Hive.openBox<Produto>(
      'p_${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDown(() async {
    VendaEstoqueRemotoPrepService.debugPendingSaleBlockHook = null;
    VendaEstoqueRemotoPrepService.flushPendingStockMutationImpl = null;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    await box.close();
  });

  Future<void> seedRemote({
    required String lojaId,
    required String docId,
    required int qty,
    required int revision,
    required String opId,
    String nome = 'Anel',
    String codigo = 'AN44SM',
  }) async {
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(docId)
        .set({
      'quantidade': qty,
      'stockRevision': revision,
      'stockOperationId': opId,
      'nome': nome,
      'codigoBarras': codigo,
    });
  }

  Produto localPending({
    required String lojaId,
    required String docId,
    required int qty,
    required int baseRev,
    required String pendingOp,
    String nome = 'Anel Solitário Liso 6 Pontas T.22 Semijoia',
    String codigo = 'AN44SM',
  }) {
    return Produto.vazio()
      ..nome = nome
      ..codigoBarras = codigo
      ..idFirebase = docId
      ..lojaId = lojaId
      ..quantidade = qty
      ..stockRevision = baseRev
      ..pendingStockOperationId = pendingOp
      ..pendingStockBaseRevision = baseRev;
  }

  group('TESTE A — venda / pending sync', () {
    test('1. NO_PENDING → venda segue', () async {
      const lojaId = 'mirjoias';
      const docId = 'p-ok';
      await seedRemote(
        lojaId: lojaId,
        docId: docId,
        qty: 2,
        revision: 1,
        opId: 'op1',
      );
      final p = Produto.vazio()
        ..nome = 'OK'
        ..codigoBarras = 'OK1'
        ..idFirebase = docId
        ..lojaId = lojaId
        ..quantidade = 2
        ..stockRevision = 1;
      await box.add(p);

      await expectLater(
        VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
          lojaId: lojaId,
          produtos: [p],
        ),
        completes,
      );
      expect(hasPendingStockMutation(p), isFalse);
    });

    test('pendência REAL (remoto ainda na base) continua bloqueando sem flush',
        () async {
      const lojaId = 'mirjoias';
      const docId = 'mirjoias-anel-an44sm';
      await seedRemote(
        lojaId: lojaId,
        docId: docId,
        qty: 0,
        revision: 2,
        opId: 'remote-old',
      );

      final p = localPending(
        lojaId: lojaId,
        docId: docId,
        qty: 1,
        baseRev: 2,
        pendingOp: 'local-pending-unsynced',
      );
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
        '2. STALE_PENDING remoto avançou → pending abandonado → venda segue',
        () async {
      const lojaId = 'mirjoias';
      const docId = 'mirjoias-anel-an43sm';
      await seedRemote(
        lojaId: lojaId,
        docId: docId,
        qty: 1,
        revision: 3,
        opId: 'repair_remote_op',
        nome: 'Anel reparado',
        codigo: 'AN43SM',
      );

      final p = localPending(
        lojaId: lojaId,
        docId: docId,
        qty: 1,
        baseRev: 2,
        pendingOp: 'stale-local-op',
        nome: 'Anel reparado',
        codigo: 'AN43SM',
      );
      await box.add(p);

      await expectLater(
        VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
          lojaId: lojaId,
          produtos: [p],
        ),
        completes,
      );
      expect(hasPendingStockMutation(p), isFalse);
      expect(p.quantidade, 1);
      expect(p.stockRevision, 3);
      expect(p.confirmedStockOperationId, 'repair_remote_op');
    });

    test('mesmo operationId confirmado no remoto limpa pendência', () async {
      const lojaId = 'mirjoias';
      const docId = 'p-same-op';
      await seedRemote(
        lojaId: lojaId,
        docId: docId,
        qty: 2,
        revision: 5,
        opId: 'op-same',
      );

      final p = localPending(
        lojaId: lojaId,
        docId: docId,
        qty: 2,
        baseRev: 4,
        pendingOp: 'op-same',
        nome: 'X',
        codigo: 'X1',
      );
      await box.add(p);

      final cleared =
          await VendaEstoqueRemotoPrepService.reconcilePendingStockMutationForSale(
        lojaId: lojaId,
        produto: p,
      );
      expect(cleared, isTrue);
      expect(hasPendingStockMutation(p), isFalse);
    });

    test('3. REAL_PENDING online → auto-sync → limpa → venda segue', () async {
      const lojaId = 'mirjoias';
      const docId = 'p-flush-ok';
      await seedRemote(
        lojaId: lojaId,
        docId: docId,
        qty: 0,
        revision: 2,
        opId: 'remote-old',
      );
      final p = localPending(
        lojaId: lojaId,
        docId: docId,
        qty: 1,
        baseRev: 2,
        pendingOp: 'local-op-flush',
      );
      await box.add(p);

      var flushCalls = 0;
      VendaEstoqueRemotoPrepService.flushPendingStockMutationImpl =
          (li, produto) async {
        flushCalls++;
        expect(produto.idFirebase, docId);
        await firestore
            .collection('lojas')
            .doc(li)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(docId)
            .set({
          'quantidade': produto.quantidade,
          'stockRevision': 3,
          'stockOperationId': produto.pendingStockOperationId,
          'nome': produto.nome,
          'codigoBarras': produto.codigoBarras,
        });
        final remote = (await firestore
                .collection('lojas')
                .doc(li)
                .collection(FSPaths.estoqueProdutosCol)
                .doc(docId)
                .get())
            .data()!;
        expect(tryConfirmStockFromRemote(produto, remote), isTrue);
        await produto.save();
        return true;
      };

      await expectLater(
        VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
          lojaId: lojaId,
          produtos: [p],
        ),
        completes,
      );
      expect(flushCalls, 1);
      expect(hasPendingStockMutation(p), isFalse);
      expect(p.stockRevision, 3);
    });

    test('4. REAL_PENDING offline → auto-sync falha → bloqueia amigável',
        () async {
      const lojaId = 'mirjoias';
      const docId = 'p-offline';
      await seedRemote(
        lojaId: lojaId,
        docId: docId,
        qty: 0,
        revision: 2,
        opId: 'remote-old',
      );
      final p = localPending(
        lojaId: lojaId,
        docId: docId,
        qty: 1,
        baseRev: 2,
        pendingOp: 'local-offline',
        nome: 'Anel X',
        codigo: 'ABC123',
      );
      await box.add(p);

      VendaEstoqueRemotoPrepService.flushPendingStockMutationImpl =
          (li, produto) async => false;

      Object? caught;
      try {
        await VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
          lojaId: lojaId,
          produtos: [p],
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<PendingStockSyncRequiredException>());
      final msg = caught.toString();
      expect(msg, isNot(contains('Bad state')));
      expect(msg, contains('Anel X'));
      expect(msg, contains('ABC123'));
      expect(hasPendingStockMutation(p), isTrue);
    });

    test(
        '5. REAL_PENDING failed-precondition + remoto avançou → reconcile → segue',
        () async {
      const lojaId = 'mirjoias';
      const docId = 'p-cas-stale';
      await seedRemote(
        lojaId: lojaId,
        docId: docId,
        qty: 4,
        revision: 9,
        opId: 'other-device-op',
      );
      final p = localPending(
        lojaId: lojaId,
        docId: docId,
        qty: 1,
        baseRev: 2,
        pendingOp: 'local-lost',
      );
      await box.add(p);

      VendaEstoqueRemotoPrepService.flushPendingStockMutationImpl =
          (li, produto) async => false; // simula failed-precondition

      await expectLater(
        VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
          lojaId: lojaId,
          produtos: [p],
        ),
        completes,
      );
      expect(hasPendingStockMutation(p), isFalse);
      expect(p.quantidade, 4);
      expect(p.stockRevision, 9);
    });

    test(
        '6. REAL_PENDING failed-precondition + remoto não avançou → bloqueia',
        () async {
      const lojaId = 'mirjoias';
      const docId = 'p-cas-stuck';
      await seedRemote(
        lojaId: lojaId,
        docId: docId,
        qty: 0,
        revision: 2,
        opId: 'remote-old',
      );
      final p = localPending(
        lojaId: lojaId,
        docId: docId,
        qty: 1,
        baseRev: 2,
        pendingOp: 'local-stuck',
      );
      await box.add(p);

      VendaEstoqueRemotoPrepService.flushPendingStockMutationImpl =
          (li, produto) async => false;

      await expectLater(
        VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
          lojaId: lojaId,
          produtos: [p],
        ),
        throwsA(isA<PendingStockSyncRequiredException>()),
      );
      expect(hasPendingStockMutation(p), isTrue);
    });

    test('7. retry da mesma operation → idempotente (mesmo opId)', () async {
      const lojaId = 'mirjoias';
      const docId = 'p-idem';
      await seedRemote(
        lojaId: lojaId,
        docId: docId,
        qty: 0,
        revision: 1,
        opId: 'old',
      );
      final p = localPending(
        lojaId: lojaId,
        docId: docId,
        qty: 2,
        baseRev: 1,
        pendingOp: 'same-op-retry',
      );
      await box.add(p);

      final seenOps = <String>[];
      VendaEstoqueRemotoPrepService.flushPendingStockMutationImpl =
          (li, produto) async {
        seenOps.add(produto.pendingStockOperationId!);
        await firestore
            .collection('lojas')
            .doc(li)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(docId)
            .set({
          'quantidade': 2,
          'stockRevision': 2,
          'stockOperationId': 'same-op-retry',
        });
        final remote = (await firestore
                .collection('lojas')
                .doc(li)
                .collection(FSPaths.estoqueProdutosCol)
                .doc(docId)
                .get())
            .data()!;
        tryConfirmStockFromRemote(produto, remote);
        await produto.save();
        return true;
      };

      await VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
        lojaId: lojaId,
        produtos: [p],
      );
      // Segunda chamada sem pending não reenvia.
      await VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
        lojaId: lojaId,
        produtos: [p],
      );
      expect(seenOps, ['same-op-retry']);
      expect(hasPendingStockMutation(p), isFalse);
    });

    test('8. 2 produtos, só 1 pending → sincroniza somente esse', () async {
      const lojaId = 'mirjoias';
      await seedRemote(
        lojaId: lojaId,
        docId: 'p-a',
        qty: 1,
        revision: 1,
        opId: 'a',
      );
      await seedRemote(
        lojaId: lojaId,
        docId: 'p-b',
        qty: 0,
        revision: 1,
        opId: 'b-old',
      );
      final a = Produto.vazio()
        ..nome = 'A'
        ..codigoBarras = 'A1'
        ..idFirebase = 'p-a'
        ..lojaId = lojaId
        ..quantidade = 1
        ..stockRevision = 1;
      final b = localPending(
        lojaId: lojaId,
        docId: 'p-b',
        qty: 1,
        baseRev: 1,
        pendingOp: 'b-pending',
        nome: 'B',
        codigo: 'B1',
      );
      await box.add(a);
      await box.add(b);

      final flushedIds = <String>[];
      VendaEstoqueRemotoPrepService.flushPendingStockMutationImpl =
          (li, produto) async {
        flushedIds.add(produto.idFirebase);
        await firestore
            .collection('lojas')
            .doc(li)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(produto.idFirebase)
            .set({
          'quantidade': produto.quantidade,
          'stockRevision': 2,
          'stockOperationId': produto.pendingStockOperationId,
        });
        final remote = (await firestore
                .collection('lojas')
                .doc(li)
                .collection(FSPaths.estoqueProdutosCol)
                .doc(produto.idFirebase)
                .get())
            .data()!;
        tryConfirmStockFromRemote(produto, remote);
        await produto.save();
        return true;
      };

      await VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
        lojaId: lojaId,
        produtos: [a, b],
      );
      expect(flushedIds, ['p-b']);
      expect(hasPendingStockMutation(a), isFalse);
      expect(hasPendingStockMutation(b), isFalse);
    });

    test('9. vários pending → todos precisam confirmar', () async {
      const lojaId = 'mirjoias';
      await seedRemote(
        lojaId: lojaId,
        docId: 'p1',
        qty: 0,
        revision: 1,
        opId: 'o1',
      );
      await seedRemote(
        lojaId: lojaId,
        docId: 'p2',
        qty: 0,
        revision: 1,
        opId: 'o2',
      );
      final p1 = localPending(
        lojaId: lojaId,
        docId: 'p1',
        qty: 1,
        baseRev: 1,
        pendingOp: 'pend1',
        nome: 'P1',
        codigo: 'C1',
      );
      final p2 = localPending(
        lojaId: lojaId,
        docId: 'p2',
        qty: 1,
        baseRev: 1,
        pendingOp: 'pend2',
        nome: 'P2',
        codigo: 'C2',
      );
      await box.add(p1);
      await box.add(p2);

      VendaEstoqueRemotoPrepService.flushPendingStockMutationImpl =
          (li, produto) async {
        if (produto.idFirebase == 'p2') return false;
        await firestore
            .collection('lojas')
            .doc(li)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(produto.idFirebase)
            .set({
          'quantidade': 1,
          'stockRevision': 2,
          'stockOperationId': produto.pendingStockOperationId,
        });
        final remote = (await firestore
                .collection('lojas')
                .doc(li)
                .collection(FSPaths.estoqueProdutosCol)
                .doc(produto.idFirebase)
                .get())
            .data()!;
        tryConfirmStockFromRemote(produto, remote);
        await produto.save();
        return true;
      };

      Object? caught;
      try {
        await VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
          lojaId: lojaId,
          produtos: [p1, p2],
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<PendingStockSyncRequiredException>());
      final ex = caught as PendingStockSyncRequiredException;
      expect(ex.produtos.map((e) => e.idFirebase), ['p2']);
      expect(hasPendingStockMutation(p1), isFalse);
      expect(hasPendingStockMutation(p2), isTrue);
    });

    test('10/11. variation/grade pending → célula no payload local preservada',
        () async {
      const lojaId = 'mirjoias';
      const docId = 'p-var';
      await seedRemote(
        lojaId: lojaId,
        docId: docId,
        qty: 0,
        revision: 1,
        opId: 'old',
      );
      final p = localPending(
        lojaId: lojaId,
        docId: docId,
        qty: 2,
        baseRev: 1,
        pendingOp: 'var-op',
        nome: 'Anel Var',
        codigo: 'VAR1',
      )
        ..variacoes = {
          'M': {'Azul': 2},
        };
      await box.add(p);

      Map<String, dynamic>? flushedVariacoes;
      VendaEstoqueRemotoPrepService.flushPendingStockMutationImpl =
          (li, produto) async {
        flushedVariacoes = produto.variacoes == null
            ? null
            : Map<String, dynamic>.from(produto.variacoes!);
        await firestore
            .collection('lojas')
            .doc(li)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(docId)
            .set({
          'quantidade': 2,
          'stockRevision': 2,
          'stockOperationId': 'var-op',
          'variacoes': produto.variacoes,
        });
        final remote = (await firestore
                .collection('lojas')
                .doc(li)
                .collection(FSPaths.estoqueProdutosCol)
                .doc(docId)
                .get())
            .data()!;
        tryConfirmStockFromRemote(produto, remote);
        await produto.save();
        return true;
      };

      await VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
        lojaId: lojaId,
        produtos: [p],
      );
      expect(flushedVariacoes, isNotNull);
      expect((flushedVariacoes!['M'] as Map)['Azul'], 2);
      expect(hasPendingStockMutation(p), isFalse);
    });

    test('12/13. UI nunca Bad state + informa produto/código', () {
      final p = Produto.vazio()
        ..nome = 'Anel X'
        ..codigoBarras = 'ABC123';
      final ex = PendingStockSyncRequiredException([p]);
      final msg = formatSalvarVendaErrorForUser(ex);
      expect(msg.toLowerCase(), isNot(contains('bad state')));
      expect(msg, contains('Anel X'));
      expect(msg, contains('ABC123'));

      final legacy = formatSalvarVendaErrorForUser(
        StateError(VendaEstoqueRemotoPrepMessages.alteracaoPendente),
      );
      expect(legacy.toLowerCase(), isNot(contains('bad state')));
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
        productId: 'var-prod',
        lojaId: 'mirjoias',
        stock: {
          'stockKind': 'variation',
          'stockRevision': 1,
          'quantidade': 3,
          'codigoBarras': 'V1',
          'variacoes': {
            'M': {'Azul': 2, 'Vermelho': 1},
          },
        },
        draft: {'nome': 'Var', 'preco': 10, 'codigoBarras': 'V1'},
        dependency: {'comboIds': []},
      );
      expect(item.availableQty, 3);
    });
  });
}
