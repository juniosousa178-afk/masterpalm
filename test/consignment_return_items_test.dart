import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_errors.dart';
import 'package:master_palm/features/consignments/consignment_models.dart';
import 'package:master_palm/features/consignments/consignment_service.dart';
import 'package:master_palm/features/consignments/consignment_ui.dart';
import 'package:master_palm/features/consignments/consignment_validation.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_data.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_pdf.dart';
import 'package:master_palm/features/consignments/screens/consignment_details_screen.dart';
import 'package:master_palm/features/consignments/screens/consignment_return_items_screen.dart';

import 'support/consignment_pdf_text.dart';

const _store = ConsignmentStoreProfile(
  lojaId: 'loja',
  name: 'Loja Teste',
  cnpj: '',
  phone: '',
  whatsapp: '',
  instagram: '',
  address: '',
  logoUrl: '',
);

Map<String, dynamic> _line(
  String id,
  int qty, {
  String? name,
  int withdrawn = 0,
  int sold = 0,
  int returned = 0,
  Map<String, dynamic>? variation,
  String? lineId,
}) {
  final vk = variation ?? {'size': '', 'color': '', 'extra': ''};
  return {
    'lineId': lineId ?? '$id::${vk['size']}\u001e${vk['color']}\u001e${vk['extra']}',
    'productId': id,
    'productNameSnapshot': name ?? id,
    'productCodeSnapshot': 'C-$id',
    'productType': variation == null ? 'simple' : 'grade',
    'variationKey': vk,
    'qtySent': qty,
    'qtySold': sold,
    'qtyReturned': returned,
    if (withdrawn > 0) 'qtyWithdrawn': withdrawn,
    'unitSalePriceSnapshot': 100,
    'commissionType': 'PERCENTUAL',
    'commissionValueSnapshot': 10,
    'potentialGrossAmount': qty * 100.0,
    'lineGrossAmount': sold * 100.0,
    'lineCommissionAmount': sold * 10.0,
    'lineNetAmount': sold * 90.0,
  };
}

Map<String, dynamic> _docMap(String status, List<Map<String, dynamic>> lines, {List<Map<String, dynamic>> withdrawals = const []}) => {
      'id': 'c1',
      'storeId': 'loja',
      'resellerId': 'maria',
      'resellerSnapshot': {'resellerId': 'maria', 'displayName': 'Maria'},
      'status': status,
      'lines': lines,
      'additions': [
        {'additionId': 'issue_c1', 'kind': 'INITIAL', 'lines': lines.map((l) => {'productNameSnapshot': l['productNameSnapshot'], 'qtyAdded': l['qtySent']}).toList()},
      ],
      'withdrawals': withdrawals,
      'totalItemsSent': lines.fold<int>(0, (s, l) => s + (l['qtySent'] as int)),
      'totalItemsSold': lines.fold<int>(0, (s, l) => s + (l['qtySold'] as int)),
      'totalItemsReturned': lines.fold<int>(0, (s, l) => s + (l['qtyReturned'] as int)),
      'potentialGrossAmount': lines.fold<double>(0, (s, l) => s + (l['potentialGrossAmount'] as double)),
      'grossSoldAmount': 0,
      'commissionAmount': 0,
      'netAmount': 0,
      'revision': 3,
      'issuedAt': DateTime(2026, 10, 1, 10),
      'createdAt': DateTime(2026, 10, 1, 9),
    };

Map<String, dynamic> _withdrawal(Map<String, dynamic> line, int qty) => {
      'withdrawalId': 'consignment_return_c1_x',
      'kind': 'WITHDRAWAL',
      'reason': 'MERCHANT_RETRIEVAL_BEFORE_SETTLEMENT',
      'createdAt': DateTime(2026, 10, 5, 15),
      'createdBy': 'owner',
      'lines': [
        {
          ...line,
          'qtyWithdrawn': qty,
        },
      ],
    };

void main() {
  group('model and validation', () {
    test('outstanding = sent - withdrawn; original totals preserved', () {
      final doc = ConsignmentDoc.fromMap('c1', _docMap('ISSUED', [
        _line('A', 2, withdrawn: 1),
        _line('B', 1, withdrawn: 1),
        _line('C', 3),
      ]));
      expect(doc.totalItemsSent, 6);
      expect(doc.totalItemsWithdrawn, 2);
      expect(doc.totalItemsOutstanding, 4);
      expect(doc.outstandingGrossAmount, 400);
      expect(doc.withdrawnGrossAmount, 200);
      expect(doc.potentialGrossAmount, 600);
      expect(doc.canReturnItems, isTrue);
      expect(doc.lines.length, 3, reason: 'fully withdrawn line kept');
    });

    test('canReturnItems only for ISSUED with pieces outstanding', () {
      for (final s in ['DRAFT', 'SETTLED', 'CANCELLED']) {
        expect(ConsignmentDoc.fromMap('c1', _docMap(s, [_line('A', 1)])).canReturnItems, isFalse, reason: s);
      }
      final deleted = _docMap('ISSUED', [_line('A', 1)])..['isDeleted'] = true;
      expect(ConsignmentDoc.fromMap('c1', deleted).canReturnItems, isFalse);
      expect(ConsignmentDoc.fromMap('c1', _docMap('ISSUED', [_line('A', 1, withdrawn: 1)])).canReturnItems, isFalse);
    });

    test('consolidatedLines sums withdrawn across lots', () {
      final doc = ConsignmentDoc.fromMap('c1', _docMap('ISSUED', [
        _line('B', 2, withdrawn: 1),
        _line('B', 3, withdrawn: 2, lineId: 'B::\u001e\u001e::add1'),
      ]));
      final c = doc.consolidatedLines.single;
      expect(c['qtySent'], 5);
      expect(c['qtyWithdrawn'], 3);
    });

    test('settlement input excludes withdrawn pieces', () {
      final input = ConsignmentSettlementLineInput(line: _line('A', 3, withdrawn: 1), qtySold: 1);
      expect(input.qtyToSettle, 2);
      expect(input.qtyReturned, 1);
      expect(input.isValid, isTrue);
      final full = ConsignmentSettlementLineInput(line: _line('B', 1, withdrawn: 1), qtySold: 0);
      expect(full.qtyToSettle, 0);
      expect(full.qtyReturned, 0);
      expect(full.isValid, isTrue);
      final over = ConsignmentSettlementLineInput(line: _line('A', 3, withdrawn: 1), qtySold: 3);
      expect(over.isValid, isFalse);
    });

    test('quantity rules: 0 < qty <= outstanding', () {
      final line = _line('A', 2, withdrawn: 1);
      expect(consignmentReturnQtyError(line, 0), isNotNull);
      expect(consignmentReturnQtyError(line, 2), contains('(1)'));
      expect(consignmentReturnQtyError(line, 1), isNull);
    });

    test('confirmation and success copy (singular and plural)', () {
      expect(
        consignmentReturnConfirmMessage(resellerName: 'Maria', totalPieces: 1),
        'Retirar esta peça do consignado de Maria e devolvê-la ao estoque?\n\n'
        'Ela não entrará no acerto da revendedora e ficará disponível no estoque da loja.',
      );
      expect(consignmentReturnConfirmMessage(resellerName: 'Maria', totalPieces: 3),
          startsWith('Retirar estas 3 peças do consignado de Maria e devolvê-las ao estoque?'));
      expect(consignmentReturnSuccessMessage(1), 'Peça devolvida ao estoque e retirada do consignado.');
      expect(consignmentReturnSuccessMessage(2), 'Peças devolvidas ao estoque e retiradas do consignado.');
      expect(
        ConsignmentException.fromCallable('failed-precondition', 'x', {'consignmentCode': 'RETURN_EXCEEDS_OUTSTANDING'}).message,
        contains('peças com a revendedora'),
      );
    });
  });

  group('service', () {
    late List<Map<String, dynamic>> calls;
    setUp(() {
      calls = [];
      ConsignmentService.debugTransport = (name, data) async {
        calls.add(Map<String, dynamic>.from(data));
        return {'consignmentId': data['consignmentId'], 'status': 'ISSUED', 'revision': 4};
      };
    });
    tearDown(() => ConsignmentService.debugTransport = null);

    test('returnItems sends exact line identity, CAS revision and stable operationId', () async {
      final opId = ConsignmentService.newReturnOperationId('c1');
      expect(opId, startsWith('consignment_return_c1_'));
      final lines = [
        const ConsignmentReturnLine(
          lineId: 'anel::20\u001eRubelita\u001e',
          productId: 'anel',
          variationKey: ConsignmentVariationKey(size: '20', color: 'Rubelita'),
          qty: 1,
        ),
      ];
      for (var i = 0; i < 2; i++) {
        await ConsignmentService.returnItems(
          lojaId: 'loja', consignmentId: 'c1', expectedRevision: 3, lines: lines, operationId: opId,
        );
      }
      expect(calls, hasLength(2));
      for (final c in calls) {
        expect(c['operation'], 'returnItems');
        expect(c['operationId'], opId);
        expect(c['payload']['expectedRevision'], 3);
        expect(c['payload']['reason'], 'MERCHANT_RETRIEVAL_BEFORE_SETTLEMENT');
        expect(c['payload']['lines'], [
          {
            'lineId': 'anel::20\u001eRubelita\u001e',
            'productId': 'anel',
            'variationKey': {'size': '20', 'color': 'Rubelita', 'extra': ''},
            'qty': 1,
          },
        ]);
      }
    });

    test('empty or non-positive selection is rejected before any call', () async {
      await expectLater(
        ConsignmentService.returnItems(lojaId: 'loja', consignmentId: 'c1', expectedRevision: 3, lines: const [], operationId: 'x'),
        throwsA(isA<ConsignmentException>()),
      );
      await expectLater(
        ConsignmentService.returnItems(
          lojaId: 'loja', consignmentId: 'c1', expectedRevision: 3, operationId: 'x',
          lines: const [ConsignmentReturnLine(lineId: 'a', productId: 'A', variationKey: ConsignmentVariationKey(), qty: 0)],
        ),
        throwsA(isA<ConsignmentException>()),
      );
      expect(calls, isEmpty);
    });
  });

  group('reports', () {
    test('pending excludes withdrawn; withdrawal rows come from append-only history', () {
      final b = _line('B', 1, withdrawn: 1);
      final doc = ConsignmentDoc.fromMap('c1', _docMap('SETTLED', [
        _line('A', 1, sold: 1),
        b,
        _line('C', 1, returned: 1),
      ], withdrawals: [_withdrawal(b, 1)]));
      final lines = ConsignmentReportAggregator.linesOf(doc);
      expect(lines.map((l) => l.qtyPending), [0, 0, 0]);
      expect(lines[1].qtyWithdrawn, 1);
      expect(lines[1].qtySent, 1, reason: 'original issued qty stays visible');
      final rows = ConsignmentReportAggregator.withdrawalsOf(doc);
      expect(rows.single.productName, 'B');
      expect(rows.single.productCode, 'C-B');
      expect(rows.single.qty, 1);
      expect(rows.single.total, 100);
      final rollup = ConsignmentReportAggregator.resellerRollup([doc]);
      expect(rollup['pending'], 0);
      expect(rollup['sent'], 3);
    });

    test('order and settlement PDFs show RETIRADAS ANTES DO ACERTO only when present', () async {
      final b = _line('B', 2, withdrawn: 1, variation: {'size': '20', 'color': 'Rubelita', 'extra': ''});
      final issued = ConsignmentDoc.fromMap('c1', _docMap('ISSUED', [_line('A', 1), b], withdrawals: [_withdrawal(b, 1)]));
      final order = ConsignmentPdfText.parse(await ConsignmentReportPdfBuilder.buildOrderPdf(
        store: _store, doc: issued, lines: ConsignmentReportAggregator.linesOf(issued),
      ));
      expect(order.count('RETIRADAS ANTES DO ACERTO'), 1);
      expect(order.text, contains('TOTAL RETIRADO: 1 peça'));
      expect(order.text, contains('COM A REVENDEDORA: 2 peças'));
      expect(order.text, contains('TOTAL DE PEÇAS: 3'), reason: 'original issue lines preserved');
      expect(order.text, contains('Tamanho: 20'));

      final settledB = _line('B', 2, withdrawn: 1, returned: 1);
      final settled = ConsignmentDoc.fromMap('c1', _docMap('SETTLED', [_line('A', 1, sold: 1), settledB],
          withdrawals: [_withdrawal(settledB, 1)]));
      final settlement = ConsignmentPdfText.parse(await ConsignmentReportPdfBuilder.buildSettlementPdf(
        store: _store, doc: settled, lines: ConsignmentReportAggregator.linesOf(settled),
      ));
      expect(settlement.count('RETIRADAS ANTES DO ACERTO'), 1);
      expect(settlement.text, contains('retiradas antes do acerto: 1'));
      expect(settlement.text, contains('Peças pendentes: 0'));

      final plain = ConsignmentDoc.fromMap('c2', _docMap('ISSUED', [_line('A', 1)]));
      final plainPdf = ConsignmentPdfText.parse(await ConsignmentReportPdfBuilder.buildOrderPdf(
        store: _store, doc: plain, lines: ConsignmentReportAggregator.linesOf(plain),
      ));
      expect(plainPdf.text, isNot(contains('RETIRADAS')));
    });
  });

  group('UI', () {
    late FakeFirebaseFirestore fake;
    late List<Map<String, dynamic>> calls;

    setUp(() {
      fake = FakeFirebaseFirestore();
      calls = [];
      ConsignmentService.debugFirestore = fake;
      ConsignmentService.debugConnectivity = () async => const [ConnectivityResult.wifi];
      ConsignmentService.debugTransport = (name, data) async {
        calls.add(Map<String, dynamic>.from(data));
        return {'consignmentId': data['consignmentId'], 'status': 'ISSUED', 'revision': 4};
      };
    });

    tearDown(() {
      ConsignmentService.debugFirestore = null;
      ConsignmentService.debugConnectivity = null;
      ConsignmentService.debugTransport = null;
    });

    Future<void> pumpDetails(WidgetTester tester, Map<String, dynamic> data) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await fake.collection('lojas').doc('loja').collection('consignments').doc('c1').set(data);
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

    for (final s in ['DRAFT', 'SETTLED', 'CANCELLED']) {
      testWidgets('Editar consignado hidden for $s', (tester) async {
        await pumpDetails(tester, _docMap(s, [_line('A', 1)]));
        expect(find.byKey(const Key('consignment_edit')), findsNothing);
      });
    }

    testWidgets('ISSUED: Editar consignado -> Retirar peças -> confirm -> command + success', (tester) async {
      final grade = _line('anel', 2, variation: {'size': '20', 'color': 'Rubelita', 'extra': ''});
      await pumpDetails(tester, _docMap('ISSUED', [grade, _line('B', 1)]));
      await tester.tap(find.byKey(const Key('consignment_edit')));
      await tester.pumpAndSettle();
      expect(find.text('Adicionar peças'), findsOneWidget);
      await tester.tap(find.byKey(const Key('consignment_edit_return')));
      await tester.pumpAndSettle();
      expect(find.byType(ConsignmentReturnItemsScreen), findsOneWidget);
      expect(find.text('Com Maria: 2 · ${consignmentMoney.format(100)}'), findsOneWidget);
      expect(find.text('Tamanho: 20 · Cor: Rubelita'), findsOneWidget);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('consignment_return_inc_0')));
        await tester.pump();
      }
      final qty = tester.widget<Text>(find.byKey(const Key('consignment_return_qty_0')));
      expect(qty.data, '2', reason: 'capped at outstanding');

      await tester.tap(find.byKey(const Key('consignment_return_confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Retirar estas 2 peças do consignado de Maria'), findsOneWidget);
      expect(find.text('2 × anel (Tamanho: 20 · Cor: Rubelita)'), findsOneWidget);
      expect(calls, isEmpty, reason: 'nothing sent before confirmation');

      await tester.tap(find.byKey(const Key('consignment_return_dialog_confirm')));
      await tester.pumpAndSettle();
      final call = calls.single;
      expect(call['operation'], 'returnItems');
      expect(call['consignmentId'], 'c1');
      expect('${call['operationId']}', startsWith('consignment_return_c1_'));
      expect(call['payload']['expectedRevision'], 3);
      expect(call['payload']['lines'], [
        {
          'lineId': grade['lineId'],
          'productId': 'anel',
          'variationKey': {'size': '20', 'color': 'Rubelita', 'extra': ''},
          'qty': 2,
        },
      ]);
      expect(find.text('Peças devolvidas ao estoque e retiradas do consignado.'), findsOneWidget);
      expect(find.byType(ConsignmentReturnItemsScreen), findsNothing);
    });

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      await pumpDetails(tester, _docMap('ISSUED', [_line('A', 1)]));
      await tester.tap(find.byKey(const Key('consignment_edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('consignment_edit_return')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('consignment_return_inc_0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('consignment_return_confirm')));
      await tester.pumpAndSettle();
      expect(find.text(consignmentReturnConfirmMessage(resellerName: 'Maria', totalPieces: 1)), findsOneWidget);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    });

    testWidgets('details show withdrawal history and outstanding total', (tester) async {
      final b = _line('B', 2, withdrawn: 1);
      await pumpDetails(tester, _docMap('ISSUED', [_line('A', 1), b], withdrawals: [_withdrawal(b, 1)]));
      expect(find.text('Retiradas antes do acerto'), findsOneWidget);
      expect(find.text('B -1'), findsOneWidget);
      expect(find.text('Com a revendedora: 2 peças · ${consignmentMoney.format(200)}'), findsOneWidget);
      expect(find.text('Total de peças enviadas: 3'), findsOneWidget);
    });
  });
}
