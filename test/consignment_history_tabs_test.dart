import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_errors.dart';
import 'package:master_palm/features/consignments/consignment_feature_flag.dart';
import 'package:master_palm/features/consignments/consignment_hide_action.dart';
import 'package:master_palm/features/consignments/consignment_models.dart';
import 'package:master_palm/features/consignments/consignment_service.dart';
import 'package:master_palm/features/consignments/screens/consignment_details_screen.dart';
import 'package:master_palm/features/consignments/screens/consignment_list_screen.dart';
import 'package:master_palm/themes/masterpalm_app_theme.dart';

Map<String, dynamic> _line(String id, {int sent = 3, int sold = 0, int returned = 0, int withdrawn = 0}) => {
      'lineId': id,
      'productId': id,
      'productNameSnapshot': 'Peça $id',
      'qtySent': sent,
      'qtySold': sold,
      'qtyReturned': returned,
      if (withdrawn > 0) 'qtyWithdrawn': withdrawn,
      'unitSalePriceSnapshot': 50,
      'commissionType': 'PERCENTUAL',
      'commissionValueSnapshot': 20,
      'variationKey': {'size': '', 'color': '', 'extra': ''},
    };

Map<String, dynamic> _doc(
  String name,
  String status, {
  List<Map<String, dynamic>>? lines,
  List<Map<String, dynamic>> withdrawals = const [],
  int day = 1,
  bool deleted = false,
  bool sold = false,
}) {
  final ls = lines ?? [_line('p1')];
  final returned = ls.fold<int>(0, (s, l) => s + (l['qtyReturned'] as int));
  final soldQty = ls.fold<int>(0, (s, l) => s + (l['qtySold'] as int));
  return {
    'storeId': 'mirjoias',
    'resellerId': 'r_$name',
    'resellerSnapshot': {'displayName': name},
    'status': status,
    'lines': ls,
    if (withdrawals.isNotEmpty) 'withdrawals': withdrawals,
    'totalItemsSent': ls.fold<int>(0, (s, l) => s + (l['qtySent'] as int)),
    'totalItemsSold': soldQty,
    'totalItemsReturned': returned,
    'grossSoldAmount': soldQty * 50,
    'commissionAmount': soldQty * 10,
    'netAmount': soldQty * 40,
    if (status == 'SETTLED') 'settlementOperationId': 'settle_$name',
    if (status == 'SETTLED') 'settledAt': DateTime(2026, 9, day + 1),
    if (status == 'CANCELLED') 'cancelledAt': DateTime(2026, 9, day + 1),
    'saleId': sold ? 'csgn_x' : null,
    'financeId': sold ? 'csgn_fin_x' : null,
    'issuedAt': DateTime(2026, 9, day),
    'createdAt': DateTime(2026, 9, day),
    if (deleted) 'isDeleted': true,
  };
}

final _fixtures = <String, Map<String, dynamic>>{
  'open77': _doc('Aberta77', 'ISSUED', lines: [_line('p1', sent: 77)], day: 1),
  'draft': _doc('Rascunho', 'DRAFT', day: 2),
  'partial': _doc('Parcial', 'ISSUED',
      lines: [_line('p1', sent: 3, withdrawn: 1)],
      withdrawals: [
        {
          'withdrawalId': 'w1',
          'lines': [
            {'lineId': 'p1', 'qtyWithdrawn': 1},
          ],
        },
      ],
      day: 3),
  'totalReturn': _doc('Devolvida', 'SETTLED', lines: [_line('p1', returned: 3)], day: 4),
  'withdrawnReturn': _doc('Retirada', 'SETTLED',
      lines: [_line('p1', sent: 3, withdrawn: 1, returned: 2)],
      withdrawals: [
        {
          'withdrawalId': 'w2',
          'lines': [
            {'lineId': 'p1', 'qtyWithdrawn': 1},
          ],
        },
      ],
      day: 5),
  'sold': _doc('Vendeu', 'SETTLED', lines: [_line('p1', sold: 1, returned: 2)], day: 6, sold: true),
  'cancelled': _doc('Cancelada', 'CANCELLED', day: 7),
  'hidden': _doc('Oculta', 'SETTLED', lines: [_line('p1', returned: 3)], day: 8, deleted: true),
};

const _open = {'open77', 'draft', 'partial'};
const _history = {'totalReturn', 'withdrawnReturn', 'sold', 'cancelled'};

const _sizes = {
  'mobile': Size(360, 740),
  'tablet': Size(800, 1280),
  'desktop': Size(1440, 900),
};

void main() {
  group('model split + total return rule', () {
    final docs = _fixtures.entries.map((e) => ConsignmentDoc.fromMap(e.key, e.value)).toList();

    test('open and history are canonical, mutually exclusive and skip soft-deleted', () {
      expect(kConsignmentOpenStatuses, {'DRAFT', 'ISSUED'});
      expect(kConsignmentClosedStatuses, {'SETTLED', 'CANCELLED'});
      final split = splitConsignmentLists(docs);
      final open = split.open.map((c) => c.id).toSet();
      final history = split.history.map((c) => c.id).toSet();
      expect(open, _open);
      expect(history, _history);
      expect(open.intersection(history), isEmpty);
      expect(split.open.where((c) => kConsignmentClosedStatuses.contains(c.status)), isEmpty);
      debugPrint('MAIN_LIST_CLOSED_COUNT=${split.open.where((c) => !c.isOpen).length}');
    });

    test('isTotalReturn table', () {
      final byId = {for (final d in docs) d.id: d};
      expect(byId['totalReturn']!.isTotalReturn, isTrue);
      expect(byId['withdrawnReturn']!.isTotalReturn, isTrue);
      for (final id in ['open77', 'draft', 'partial', 'sold', 'cancelled']) {
        expect(byId[id]!.isTotalReturn, isFalse, reason: id);
        expect(byId[id]!.canHideFromList, isFalse, reason: id);
      }
      expect(byId['hidden']!.isTotalReturn, isTrue);
      expect(byId['hidden']!.canHideFromList, isFalse);
      // withdrawal recorded on the line but missing from withdrawals[]
      final forged = Map<String, dynamic>.from(_fixtures['withdrawnReturn']!)..remove('withdrawals');
      expect(ConsignmentDoc.fromMap('f', forged).isTotalReturn, isFalse);
      // settled with nothing sold but a piece unaccounted for
      final missing = _doc('X', 'SETTLED', lines: [_line('p1', returned: 2)]);
      expect(ConsignmentDoc.fromMap('m', missing).isTotalReturn, isFalse);
    });
  });

  group('Consignados tabs', () {
    late FakeFirebaseFirestore fake;
    late List<Map<String, dynamic>> calls;
    late Map<String, Object?> stockBefore;

    Future<Map<String, Object?>> stockSnapshot() async {
      final snap = await fake.collection('lojas').doc('mirjoias').collection('estoque_produtos').get();
      return {for (final d in snap.docs) d.id: d.data()};
    }

    setUp(() async {
      fake = FakeFirebaseFirestore();
      calls = [];
      final loja = fake.collection('lojas').doc('mirjoias');
      await loja.collection('consignment_control').doc('state').set({'moduleEnabled': true, 'protocolVersion': 1});
      await loja.collection('estoque_produtos').doc('p1').set({'quantidade': 10});
      for (final e in _fixtures.entries) {
        await loja.collection('consignments').doc(e.key).set(e.value);
      }
      stockBefore = await stockSnapshot();
      ConsignmentFeatureFlag.debugFirestore = fake;
      ConsignmentService.debugFirestore = fake;
      ConsignmentListScreen.debugLojaId = () async => 'mirjoias';
      ConsignmentService.debugTransport = (name, data) async {
        calls.add({'name': name, ...data});
        if (data['operation'] == 'hideTotalReturn') {
          await loja.collection('consignments').doc('${data['consignmentId']}').update({
            'isDeleted': true,
            'deletedReason': 'TOTAL_RETURN',
          });
        }
        return {'consignmentId': data['consignmentId'], 'status': 'SETTLED', 'isDeleted': true};
      };
    });

    tearDown(() {
      ConsignmentFeatureFlag.debugFirestore = null;
      ConsignmentService.debugFirestore = null;
      ConsignmentService.debugTransport = null;
      ConsignmentListScreen.debugLojaId = null;
    });

    Future<void> pumpList(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        theme: masterPalmLightTheme(),
        home: const Scaffold(body: SizedBox()),
      ));
      nav.currentState!.push(MaterialPageRoute(builder: (_) => const ConsignmentListScreen()));
      await tester.pumpAndSettle();
    }

    Set<String> visibleTiles(WidgetTester tester) => tester
        .widgetList(find.byWidgetPredicate(
            (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('consignment_tile_')))
        .map((w) => (w.key as ValueKey<String>).value.substring('consignment_tile_'.length))
        .toSet();

    Future<void> openHistory(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('consignment_tab_history')));
      await tester.pumpAndSettle();
    }

    for (final entry in _sizes.entries) {
      testWidgets('A/B/C/H tabs split open vs history (${entry.key})', (tester) async {
        await pumpList(tester, entry.value);
        expect(find.text('Em aberto'), findsOneWidget);
        expect(find.text('Histórico'), findsOneWidget);
        expect(visibleTiles(tester), _open, reason: 'default tab is Em aberto');
        expect(find.byKey(const Key('consignment_menu_totalReturn')), findsNothing);

        await openHistory(tester);
        expect(visibleTiles(tester), _history);
        expect(find.text('Oculta'), findsNothing);
        expect(find.text('Cancelada'), findsOneWidget);
        expect(find.textContaining('Vendido'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('D/E Excluir da lista only for total return', (tester) async {
      await pumpList(tester, const Size(800, 1280));
      await openHistory(tester);
      expect(find.byKey(const Key('consignment_menu_totalReturn')), findsOneWidget);
      expect(find.byKey(const Key('consignment_menu_withdrawnReturn')), findsOneWidget);
      for (final id in ['sold', 'cancelled']) {
        expect(find.byKey(Key('consignment_menu_$id')), findsNothing, reason: id);
      }
      expect(find.text(consignmentHideTotalReturnLabel), findsNothing);
    });

    testWidgets('F/G hide removes from both tabs, keeps doc, no stock writes', (tester) async {
      await pumpList(tester, const Size(390, 844));
      await openHistory(tester);
      await tester.tap(find.byKey(const Key('consignment_menu_totalReturn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(consignmentHideTotalReturnLabel));
      await tester.pumpAndSettle();
      expect(find.text(consignmentHideTotalReturnMessage), findsOneWidget);
      expect(consignmentHideTotalReturnMessage,
          'Essa consignação foi encerrada com devolução total.\n'
          'Ela será removida das listas, mas o histórico continuará preservado.');
      expect(find.text('Cancelar'), findsOneWidget);

      await tester.tap(find.byKey(const Key('consignment_hide_confirm')));
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      expect(calls.single['name'], 'consignmentCommand');
      expect(calls.single['operation'], 'hideTotalReturn');
      expect(calls.single['operationId'], 'hide_total_return_totalReturn');
      expect(calls.single['payload'], isEmpty);
      expect(find.text(consignmentHiddenMessage), findsOneWidget);

      expect(visibleTiles(tester), _history.difference({'totalReturn'}));
      await tester.tap(find.byKey(const Key('consignment_tab_open')));
      await tester.pumpAndSettle();
      expect(visibleTiles(tester), _open);

      final doc = await fake.collection('lojas').doc('mirjoias').collection('consignments').doc('totalReturn').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['status'], 'SETTLED');
      expect(doc.data()!['lines'], _fixtures['totalReturn']!['lines']);
      expect(await stockSnapshot(), stockBefore);
      final all = await ConsignmentService.watchConsignments('mirjoias', includeDeleted: true).first;
      expect(all.map((c) => c.id), containsAll(['totalReturn', 'hidden']));
    });

    testWidgets('select mode: CANCELLED in Histórico stays unselectable for combined print', (tester) async {
      await pumpList(tester, const Size(800, 1280));
      await tester.tap(find.text('Selecionar'));
      await tester.pumpAndSettle();
      await openHistory(tester);
      Checkbox box(String id) => tester.widget<Checkbox>(find.byKey(Key('consignment_select_$id')));
      expect(box('cancelled').onChanged, isNull);
      for (final id in ['totalReturn', 'withdrawnReturn', 'sold']) {
        expect(box(id).onChanged, isNotNull, reason: 'SETTLED stays selectable: $id');
      }
      await tester.tap(find.text('Cancelada'));
      await tester.pumpAndSettle();
      expect(box('cancelled').value, isFalse);
      expect(find.byKey(const Key('consignment_menu_totalReturn')), findsNothing, reason: 'no hide menu in select mode');
      await tester.tap(find.byKey(const Key('consignment_tab_open')));
      await tester.pumpAndSettle();
      for (final id in _open) {
        expect(box(id).onChanged, isNotNull, reason: 'open stays selectable: $id');
      }
    });

    testWidgets('cancelling the hide confirmation sends nothing', (tester) async {
      await pumpList(tester, const Size(1440, 900));
      await openHistory(tester);
      await tester.tap(find.byKey(const Key('consignment_menu_totalReturn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(consignmentHideTotalReturnLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('consignment_hide_cancel')));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(visibleTiles(tester), _history);
    });

    testWidgets('old server rejection shows a friendly message', (tester) async {
      ConsignmentService.debugTransport = (name, data) async {
        calls.add(data);
        throw ConsignmentException('INVALID_ARGUMENT', 'Unsupported operation');
      };
      await pumpList(tester, const Size(800, 1280));
      await openHistory(tester);
      await tester.tap(find.byKey(const Key('consignment_menu_totalReturn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(consignmentHideTotalReturnLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('consignment_hide_confirm')));
      await tester.pumpAndSettle();
      expect(find.text(consignmentHideUnavailableMessage), findsOneWidget);
      expect(visibleTiles(tester), _history);
    });

    Future<void> pumpDetails(WidgetTester tester, String id) async {
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(ctx,
                  MaterialPageRoute(builder: (_) => ConsignmentDetailsScreen(lojaId: 'mirjoias', consignmentId: id))),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    for (final id in ['open77', 'partial', 'sold', 'cancelled']) {
      testWidgets('details: no Excluir da lista for $id', (tester) async {
        await pumpDetails(tester, id);
        expect(find.byKey(const Key('consignment_hide_total_return')), findsNothing);
      });
    }

    testWidgets('details: total return hides and closes', (tester) async {
      await pumpDetails(tester, 'withdrawnReturn');
      final button = find.byKey(const Key('consignment_hide_total_return'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('consignment_hide_confirm')));
      await tester.pumpAndSettle();
      expect(calls.single['operation'], 'hideTotalReturn');
      expect(find.byType(ConsignmentDetailsScreen), findsNothing);
      expect(await stockSnapshot(), stockBefore);
    });
  });
}
