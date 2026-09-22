// Nathy P0: restore sourceOperationId must be an applied stock sale operation.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';

const _store = 'nathy-pratas-e-folheados';
const _saleOp = '449fc83e-9a5e-4544-9bee-93348123a2dd';
const _productId = 'nathy-pratas-e-folheados-anel-lacinho-encanto';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore fs;

  setUp(() {
    fs = FakeFirebaseFirestore();
    EstoqueTransactionService.debugClearOverrides();
    EstoqueTransactionService.debugFirestoreOverride = fs;
    StockCatalogBackendService.debugTransport = null;
  });

  tearDown(() {
    EstoqueTransactionService.debugClearOverrides();
    StockCatalogBackendService.debugTransport = null;
  });

  Future<void> seedAppliedSale({
    String opId = _saleOp,
    String kind = 'sale',
    String status = 'applied',
  }) async {
    await fs
        .collection('lojas')
        .doc(_store)
        .collection('stock_catalog_operations')
        .doc(opId)
        .set({
      'kind': kind,
      'status': status,
      'legacyCompat': true,
      'items': [
        {
          'productId': _productId,
          'quantity': 1,
          'size': '15',
          'color': 'sem-cor',
        }
      ],
      'result': {
        'productIds': [_productId]
      },
    });
  }

  group('resolverSourceOperationIdParaRestore', () {
    test('A modern sale: idFirebase == applied stock op', () async {
      await seedAppliedSale();
      final resolved =
          await EstoqueTransactionService.resolverSourceOperationIdParaRestore(
        lojaId: _store,
        idFirebase: _saleOp,
        vendaIdMarcadorCatalogo: '999', // raw hive key must not win
      );
      expect(resolved, _saleOp);
    });

    test('B explicit stockOperationId wins when applied', () async {
      const explicit = 'explicit-applied-sale-op';
      await seedAppliedSale(opId: explicit);
      await seedAppliedSale(); // also seed idFirebase op
      final resolved =
          await EstoqueTransactionService.resolverSourceOperationIdParaRestore(
        lojaId: _store,
        explicitStockOperationId: explicit,
        idFirebase: _saleOp,
        vendaIdMarcadorCatalogo: '12',
      );
      expect(resolved, explicit);
    });

    test('C legacy marker whose operationId points to applied sale', () async {
      await seedAppliedSale();
      await fs
          .collection('lojas')
          .doc(_store)
          .collection('estoque_baixa_pagamento')
          .doc('42')
          .set({
        'baixaAplicada': true,
        'origem': 'pdv',
        'operationId': _saleOp,
        'saleId': _saleOp,
        'lojaId': _store,
      });
      final resolved =
          await EstoqueTransactionService.resolverSourceOperationIdParaRestore(
        lojaId: _store,
        idFirebase: null,
        vendaIdMarcadorCatalogo: '42',
      );
      expect(resolved, _saleOp);
    });

    test('D raw hive key without stock op fails closed', () async {
      await fs
          .collection('lojas')
          .doc(_store)
          .collection('estoque_baixa_pagamento')
          .doc('7')
          .set({
        'baixaAplicada': true,
        'origem': 'pos_pagamento',
        'vendaId': '7',
        'lojaId': _store,
      });
      expect(
        () => EstoqueTransactionService.resolverSourceOperationIdParaRestore(
          lojaId: _store,
          idFirebase: null,
          vendaIdMarcadorCatalogo: '7',
        ),
        throwsA(isA<EstoqueRestoreSourceUnresolvedException>()),
      );
    });

    test('Nathy real sale: hive marker leftover does not override UUID',
        () async {
      await seedAppliedSale();
      await fs
          .collection('lojas')
          .doc(_store)
          .collection('estoque_baixa_pagamento')
          .doc('0')
          .set({
        'baixaAplicada': true,
        'estornoAplicado': true,
        'origem': 'pos_pagamento',
        'vendaId': '0',
        'lojaId': _store,
      });
      final resolved =
          await EstoqueTransactionService.resolverSourceOperationIdParaRestore(
        lojaId: _store,
        idFirebase: _saleOp,
        vendaIdMarcadorCatalogo: '0',
      );
      expect(resolved, _saleOp);
    });

    test('hive_ prefix never accepted as candidate', () async {
      await seedAppliedSale();
      expect(
        () => EstoqueTransactionService.resolverSourceOperationIdParaRestore(
          lojaId: _store,
          idFirebase: 'hive_12',
          vendaIdMarcadorCatalogo: null,
        ),
        throwsA(isA<EstoqueRestoreSourceUnresolvedException>()),
      );
    });

    test('source kind!=sale rejected', () async {
      await seedAppliedSale(kind: 'restore', status: 'applied');
      expect(
        () => EstoqueTransactionService.resolverSourceOperationIdParaRestore(
          lojaId: _store,
          idFirebase: _saleOp,
        ),
        throwsA(isA<EstoqueRestoreSourceUnresolvedException>()),
      );
    });

    test('source status!=applied rejected', () async {
      await seedAppliedSale(status: 'pending');
      expect(
        () => EstoqueTransactionService.resolverSourceOperationIdParaRestore(
          lojaId: _store,
          idFirebase: _saleOp,
        ),
        throwsA(isA<EstoqueRestoreSourceUnresolvedException>()),
      );
    });
  });

  group('restore payload + idempotency', () {
    test('restore uses validated source and deterministic operationId',
        () async {
      await seedAppliedSale();
      final source =
          await EstoqueTransactionService.resolverSourceOperationIdParaRestore(
        lojaId: _store,
        idFirebase: _saleOp,
        vendaIdMarcadorCatalogo: '55',
      );
      expect(source, _saleOp);

      final expectedRestoreId =
          'restore_${sha256.convert(utf8.encode(source))}';
      var callCount = 0;
      StockCatalogBackendService.debugTransport = (name, data) async {
        callCount++;
        expect(name, 'stockCatalogCommand');
        expect(data['kind'], 'restore');
        expect(data['sourceOperationId'], _saleOp);
        expect(data['operationId'], expectedRestoreId);
        expect(data['protocolVersion'], 1);
        expect(data['lojaId'], _store);
        expect(data['items'], isNotEmpty);
        return {
          'alreadyApplied': callCount > 1,
          'operationId': data['operationId'],
          'products': [
            {
              'productId': _productId,
              'quantidade': 2,
              'stockRevision': 10,
              'stockOperationId': data['operationId'],
              'variacoes': {
                '15': {'sem-cor': 1},
                '22': {'sem-cor': 1},
              },
              'estoquePorTamanho': {'15': 1, '22': 1},
              'estoquePorCor': <String, int>{},
            }
          ],
        };
      };

      EstoqueTransactionService.debugFirestoreOverride = null;
      final first =
          await EstoqueTransactionService.devolverEstoqueTransactionBatch(
        lojaId: _store,
        itens: [
          {
            'productId': _productId,
            'quantidade': 1,
            'tamanho': '15',
            'cor': 'sem-cor',
          }
        ],
        vendaIdParaIdempotencia: source,
      );
      expect(first, isNotEmpty);
      expect(first.first.quantidadeTotalAtualizada, 2);
      final c15 = first.first.variacoesAtualizadas?['15'];
      if (c15 is Map) {
        expect(c15['sem-cor'], 1);
      }

      final second =
          await EstoqueTransactionService.devolverEstoqueTransactionBatch(
        lojaId: _store,
        itens: [
          {
            'productId': _productId,
            'quantidade': 1,
            'tamanho': '15',
            'cor': 'sem-cor',
          }
        ],
        vendaIdParaIdempotencia: source,
      );
      expect(callCount, 2);
      expect(second.first.quantidadeTotalAtualizada, 2);
    });

    test('UX maps Applied sale required without leaking raw firebase string',
        () {
      final msg =
          EstoqueTransactionService.mensagemUsuarioFalhaDevolucaoEstoque(
        Exception(
          '[firebase_functions/failed-precondition] Applied sale required',
        ),
      );
      expect(msg.contains('Applied sale required'), isFalse);
      expect(msg.contains('firebase_functions'), isFalse);
      expect(msg, contains('operação original de estoque'));
    });
  });
}
