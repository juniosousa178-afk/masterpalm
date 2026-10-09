import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_eligibility.dart';
import 'package:master_palm/features/consignments/consignment_errors.dart';
import 'package:master_palm/features/consignments/consignment_models.dart';
import 'package:master_palm/features/consignments/consignment_service.dart';
import 'package:master_palm/features/consignments/screens/consignment_details_screen.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produto_stock_catalog_cadastro_sync.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';

const _gotaId = 'mirjoias-anel-gota-verde-gua-t-20-semijoia-3';

ConsignmentPickerItem _item(String id, String name, String code) =>
    ConsignmentPickerItem(
      productId: id,
      name: name,
      productCode: code,
      price: 10,
      availableQty: 1,
      stockKind: 'simple',
      variacoes: const {},
      eligible: true,
      unavailableReason: '',
    );

List<ConsignmentPickerItem> _catalog({String gotaCode = 'AN45SM - 103'}) => [
      _item('terco-24', 'Anel Terço Coração T.24 Prata 925', 'AN45PR'),
      _item(_gotaId, 'Anel Gota Verde Água T.20 Semijoia', gotaCode),
      _item('gota-19', 'Anel Gota Verde Água T.19 Semijoia', 'AN45SM - 102'),
      _item('brinco', 'Brinco Argola', 'BR10'),
    ];

List<String> _search(String q, {String gotaCode = 'AN45SM - 103'}) =>
    consignmentPickerVisibleItems(_catalog(gotaCode: gotaCode), query: q)
        .map((e) => e.productId)
        .toList();

Map<String, dynamic> _consignment(String status, {bool deleted = false}) => {
      'storeId': 'loja',
      'status': status,
      'resellerId': 'r1',
      'lines': const [],
      'additions': const [],
      if (deleted) 'isDeleted': true,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('product code search (search-only normalization)', () {
    test('normalized key ignores case, spaces and separators', () {
      for (final v in ['AN45SM-103', 'AN45SM 103', 'AN45SM - 103', 'an45sm-103', 'AN45SM103']) {
        expect(consignmentPickerNormalizeCode(v), 'an45sm103', reason: v);
      }
    });

    test('SEARCH_NEW_CODE_TEST_PASS: every spelling of the new code finds the edited product first', () {
      for (final q in ['AN45SM - 103', 'AN45SM-103', 'AN45SM 103', 'an45sm-103', 'AN45SM103']) {
        final res = _search(q);
        expect(res.first, _gotaId, reason: q);
        expect(res, isNot(contains('terco-24')), reason: q);
      }
    });

    test('SEARCH_OLD_CODE_TEST_PASS: old code no longer matches after edit', () {
      expect(_search('AN32SM', gotaCode: 'AN32SM'), [_gotaId]);
      expect(_search('AN32SM'), isEmpty);
    });

    test('SEARCH_PREFIX_TEST_PASS: prefix lists every related product, exact match first', () {
      final prefix = _search('an45');
      expect(prefix.toSet(), {'terco-24', _gotaId, 'gota-19'});
      expect(_search('AN45SM').toSet(), {_gotaId, 'gota-19'});
      expect(_search('an45pr').first, 'terco-24');
    });

    test('results are bound to canonical productId, not to the name', () {
      final res = consignmentPickerVisibleItems(_catalog(), query: 'an45sm - 102');
      expect(res.first.productId, 'gota-19');
      expect(res.first.productCode, 'AN45SM - 102', reason: 'stored code is shown unchanged');
      expect(_search(_gotaId).first, _gotaId);
    });
  });

  group('cadastro save sends the product code to the authoritative command', () {
    tearDown(() => StockCatalogBackendService.debugTransport = null);

    test('editorial payload carries trimmed codigoBarras and omits empty code', () {
      final produto = Produto.vazio()
        ..nome = 'Anel Gota'
        ..codigoBarras = '  AN45SM - 103 '
        ..publicadoNoCatalogo = true;
      expect(ProdutoStockCatalogCadastroSync.buildEditorial(produto)['codigoBarras'], 'AN45SM - 103');
      produto.codigoBarras = '   ';
      expect(ProdutoStockCatalogCadastroSync.buildEditorial(produto).containsKey('codigoBarras'), isFalse);
    });

    test('old server rejecting identity field: resend without code, same operationId', () async {
      final calls = <Map<String, dynamic>>[];
      StockCatalogBackendService.debugTransport = (name, data) async {
        calls.add(Map<String, dynamic>.from(data));
        if ((data['editorial'] as Map).containsKey('codigoBarras')) {
          throw FirebaseFunctionsException(code: 'invalid-argument', message: 'Protected or unknown editorial field');
        }
        return {'operationId': data['operationId'], 'alreadyApplied': false, 'products': const []};
      };
      await ProdutoStockCatalogCadastroSync.sendIntent(
        lojaId: 'loja',
        intent: ProdutoStockCatalogCadastroIntent(
          operationId: 'op-code',
          kind: 'editorial',
          items: const [{'productId': 'p'}],
          editorial: const {'nome': 'X', 'codigoBarras': 'AN45SM - 103'},
        ),
      );
      expect(calls, hasLength(2));
      expect(calls[1]['operationId'], 'op-code');
      expect((calls[1]['editorial'] as Map).containsKey('codigoBarras'), isFalse);
      expect((calls[1]['editorial'] as Map)['nome'], 'X');
    });

    test('other errors are not retried', () async {
      var count = 0;
      StockCatalogBackendService.debugTransport = (name, data) async {
        count++;
        throw FirebaseFunctionsException(code: 'aborted', message: 'Stock revision conflict');
      };
      await expectLater(
        ProdutoStockCatalogCadastroSync.sendIntent(
          lojaId: 'loja',
          intent: ProdutoStockCatalogCadastroIntent(
            operationId: 'op-x',
            kind: 'editorial',
            items: const [{'productId': 'p'}],
            editorial: const {'codigoBarras': 'AN45SM'},
          ),
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      expect(count, 1);
    });
  });

  group('delete cancelled consignment (soft delete)', () {
    late FakeFirebaseFirestore fake;
    late List<Map<String, dynamic>> calls;

    setUp(() {
      fake = FakeFirebaseFirestore();
      calls = [];
      ConsignmentService.debugFirestore = fake;
      ConsignmentService.debugTransport = (name, data) async {
        calls.add(Map<String, dynamic>.from(data));
        return {'consignmentId': data['consignmentId'], 'status': 'CANCELLED', 'isDeleted': true};
      };
    });

    tearDown(() {
      ConsignmentService.debugFirestore = null;
      ConsignmentService.debugTransport = null;
    });

    test('only non-deleted CANCELLED consignments can be deleted', () {
      expect(ConsignmentDoc.fromMap('a', _consignment('CANCELLED')).canDelete, isTrue);
      expect(ConsignmentDoc.fromMap('a', _consignment('CANCELLED', deleted: true)).canDelete, isFalse);
      for (final s in ['DRAFT', 'ISSUED', 'SETTLED']) {
        expect(ConsignmentDoc.fromMap('a', _consignment(s)).canDelete, isFalse, reason: s);
      }
    });

    test('lists hide deleted records; reports still see them', () async {
      final col = fake.collection('lojas').doc('loja').collection('consignments');
      await col.doc('keep').set(_consignment('CANCELLED'));
      await col.doc('gone').set(_consignment('CANCELLED', deleted: true));
      await col.doc('live').set(_consignment('ISSUED'));
      final list = await ConsignmentService.watchConsignments('loja').first;
      expect(list.map((c) => c.id).toSet(), {'keep', 'live'});
      final all = await ConsignmentService.watchConsignments('loja', includeDeleted: true).first;
      expect(all.map((c) => c.id).toSet(), {'keep', 'gone', 'live'});
    });

    test('deleteCancelled uses a stable operationId (retry is idempotent server-side)', () async {
      await ConsignmentService.deleteCancelled(lojaId: 'loja', consignmentId: 'c1');
      await ConsignmentService.deleteCancelled(lojaId: 'loja', consignmentId: 'c1');
      expect(calls, hasLength(2));
      for (final c in calls) {
        expect(c['operation'], 'deleteCancelled');
        expect(c['operationId'], 'delete_c1');
        expect(c['consignmentId'], 'c1');
        expect(c['payload'], isEmpty);
      }
    });

    test('server refusal maps to a clear message', () {
      final e = ConsignmentException.fromCallable(
          'failed-precondition', 'x', {'consignmentCode': 'CONSIGNMENT_DELETE_NOT_ALLOWED'});
      expect(e.message, 'Só consignações canceladas podem ser excluídas da lista.');
    });

    Future<void> pumpDetails(WidgetTester tester, String status) async {
      await fake.collection('lojas').doc('loja').collection('consignments').doc('c1').set(_consignment(status));
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(ctx,
                  MaterialPageRoute(builder: (_) => const ConsignmentDetailsScreen(lojaId: 'loja', consignmentId: 'c1'))),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    for (final s in ['DRAFT', 'ISSUED', 'SETTLED']) {
      testWidgets('Excluir hidden for $s consignment', (tester) async {
        await pumpDetails(tester, s);
        expect(find.byType(ConsignmentDetailsScreen), findsOneWidget);
        expect(find.byKey(const Key('consignment_delete_cancelled')), findsNothing);
      });
    }

    testWidgets('Excluir on cancelled: confirmation copy, command, success message', (tester) async {
      await pumpDetails(tester, 'CANCELLED');
      final button = find.byKey(const Key('consignment_delete_cancelled'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text(consignmentDeleteConfirmMessage), findsOneWidget);
      expect(consignmentDeleteConfirmMessage,
          'Excluir esta consignação cancelada da lista?\nO histórico da operação será preservado.');
      expect(consignmentDeleteConfirmMessage.toLowerCase(), isNot(contains('estoque')));

      await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
      await tester.pumpAndSettle();
      expect(calls.single['operation'], 'deleteCancelled');
      expect(find.text('Consignação excluída da lista.'), findsOneWidget);
      expect(find.byType(ConsignmentDetailsScreen), findsNothing);
    });

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      await pumpDetails(tester, 'CANCELLED');
      final button = find.byKey(const Key('consignment_delete_cancelled'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.byType(ConsignmentDetailsScreen), findsOneWidget);
    });
  });
}
