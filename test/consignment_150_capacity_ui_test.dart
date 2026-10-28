import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_models.dart';
import 'package:master_palm/features/consignments/consignment_service.dart';
import 'package:master_palm/features/consignments/consignment_validation.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_data.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_pdf.dart';
import 'package:master_palm/features/consignments/screens/consignment_details_screen.dart';
import 'package:master_palm/features/consignments/screens/consignment_return_items_screen.dart';
import 'package:master_palm/features/consignments/screens/consignment_settle_screen.dart';

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

const _n = kConsignmentMaxProducts;
String _name(int i) => 'Produto ${i.toString().padLeft(3, '0')}';

Map<String, dynamic> _line(int i, int qty, {int withdrawn = 0, int sold = 0, int returned = 0, String? size}) {
  final vk = {'size': size ?? '', 'color': size == null ? '' : 'Rubelita', 'extra': ''};
  final id = 'p$i';
  return {
    'lineId': '$id::${vk['size']}\u001e${vk['color']}\u001e${vk['extra']}',
    'productId': id,
    'productNameSnapshot': _name(i),
    'productCodeSnapshot': 'C-$i',
    'productType': size == null ? 'simple' : 'grade',
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

Map<String, dynamic> _docMap(String id, String status, List<Map<String, dynamic>> lines,
        {List<Map<String, dynamic>> withdrawals = const []}) =>
    {
      'id': id,
      'storeId': 'loja',
      'resellerId': 'maria',
      'resellerSnapshot': {'resellerId': 'maria', 'displayName': 'Maria'},
      'status': status,
      'lines': lines,
      'additions': [
        {
          'additionId': 'issue_$id',
          'kind': 'INITIAL',
          'lines': lines.map((l) => {'productNameSnapshot': l['productNameSnapshot'], 'qtyAdded': l['qtySent']}).toList(),
        },
      ],
      'withdrawals': withdrawals,
      'totalItemsSent': lines.fold<int>(0, (s, l) => s + (l['qtySent'] as int)),
      'totalItemsSold': lines.fold<int>(0, (s, l) => s + (l['qtySold'] as int)),
      'totalItemsReturned': lines.fold<int>(0, (s, l) => s + (l['qtyReturned'] as int)),
      'potentialGrossAmount': lines.fold<double>(0, (s, l) => s + (l['potentialGrossAmount'] as double)),
      'grossSoldAmount': lines.fold<double>(0, (s, l) => s + (l['lineGrossAmount'] as double)),
      'commissionAmount': lines.fold<double>(0, (s, l) => s + (l['lineCommissionAmount'] as double)),
      'netAmount': lines.fold<double>(0, (s, l) => s + (l['lineNetAmount'] as double)),
      'revision': 3,
      'issuedAt': DateTime(2026, 10, 1, 10),
      'createdAt': DateTime(2026, 10, 1, 9),
    };

List<Map<String, dynamic>> _issuedLines() => [for (var i = 1; i <= _n; i++) _line(i, 2)];

void _expectAllProducts(String text) {
  for (var i = 1; i <= _n; i++) {
    expect(text, contains(_name(i)), reason: 'missing ${_name(i)}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('150-product reports', () {
    test('single order PDF lists all 150 products (300 variation lines) across pages', () async {
      final lines = [
        for (var i = 1; i <= _n; i++) ...[_line(i, 1, size: '20'), _line(i, 1, size: '22')],
      ];
      final doc = ConsignmentDoc.fromMap('c150', _docMap('c150', 'ISSUED', lines));
      final pdf = ConsignmentPdfText.parse(await ConsignmentReportPdfBuilder.buildOrderPdf(
        store: _store, doc: doc, lines: ConsignmentReportAggregator.linesOf(doc),
      ));
      _expectAllProducts(pdf.text);
      expect(pdf.text, contains('TOTAL DE PEÇAS: ${2 * _n}'));
      expect(pdf.pageCount, greaterThan(1));
    });

    test('settlement PDF with 150 settled lines and withdrawals', () async {
      final lines = [
        for (var i = 1; i <= _n; i++)
          i <= 50 ? _line(i, 2, withdrawn: 1, sold: 1) : _line(i, 2, sold: 1, returned: 1),
      ];
      final withdrawals = [
        {
          'withdrawalId': 'consignment_return_c150_x',
          'kind': 'WITHDRAWAL',
          'reason': 'MERCHANT_RETRIEVAL_BEFORE_SETTLEMENT',
          'createdAt': DateTime(2026, 10, 5, 15),
          'createdBy': 'owner',
          'lines': [for (final l in lines.take(50)) {...l, 'qtyWithdrawn': 1}],
        },
      ];
      final doc = ConsignmentDoc.fromMap('c150', _docMap('c150', 'SETTLED', lines, withdrawals: withdrawals));
      final pdf = ConsignmentPdfText.parse(await ConsignmentReportPdfBuilder.buildSettlementPdf(
        store: _store, doc: doc, lines: ConsignmentReportAggregator.consignedLinesOf(doc),
      ));
      _expectAllProducts(pdf.text);
      expect(pdf.text.toLowerCase(), isNot(contains('retirad')));
      expect(pdf.text, contains('Peças enviadas: 250'));
      expect(pdf.text, contains('Peças pendentes: 0'));
      expect(pdf.pageCount, greaterThan(1));
    });

    test('combined PDF with three 150-product consignments', () async {
      final docs = [
        for (final id in ['ca', 'cb', 'cc']) ConsignmentDoc.fromMap(id, _docMap(id, 'ISSUED', _issuedLines())),
      ];
      final sections = [
        for (final d in ConsignmentCombinedReportPlanner.order(docs))
          ConsignmentCombinedSection(doc: d, lines: ConsignmentReportAggregator.linesOf(d)),
      ];
      final pdf = ConsignmentPdfText.parse(await ConsignmentReportPdfBuilder.buildCombinedPdf(
        store: _store, sections: sections, generatedAt: DateTime(2026, 10, 8, 10, 30),
      ));
      _expectAllProducts(pdf.text);
      expect(pdf.count(_name(_n)), greaterThanOrEqualTo(3));
      expect(pdf.pageCount, greaterThan(3));
    });
  });

  group('150-product screens', () {
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

    Future<void> open(WidgetTester tester, Map<String, dynamic> data, WidgetBuilder screen) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await fake.collection('lojas').doc('loja').collection('consignments').doc(data['id'] as String).set(data);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: screen)),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('details screen renders 150 products and the full total', (tester) async {
      await open(tester, _docMap('c150', 'ISSUED', _issuedLines()),
          (_) => const ConsignmentDetailsScreen(lojaId: 'loja', consignmentId: 'c150'));
      expect(tester.takeException(), isNull);
      final scrollable = find.byType(Scrollable).first;
      final lastLine = find.widgetWithText(ListTile, _name(_n));
      await tester.scrollUntilVisible(lastLine, 400, scrollable: scrollable);
      expect(lastLine, findsOneWidget);
      final total = find.text('Total de peças enviadas: ${2 * _n}');
      await tester.scrollUntilVisible(total, 400, scrollable: scrollable);
      expect(total, findsOneWidget);
    });

    testWidgets('settlement screen sends all 150 lines in one command', (tester) async {
      await open(tester, _docMap('c150', 'ISSUED', _issuedLines()),
          (_) => const ConsignmentSettleScreen(lojaId: 'loja', consignmentId: 'c150'));
      expect(tester.takeException(), isNull);
      final confirm = find.widgetWithText(FilledButton, 'Confirmar acerto');
      await tester.scrollUntilVisible(confirm, 600, scrollable: find.byType(Scrollable).first);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar acerto').last);
      await tester.pumpAndSettle();
      final call = calls.singleWhere((c) => c['operation'] == 'settle');
      final sent = (call['payload']['lines'] as List).cast<Map>();
      expect(sent.length, _n);
      for (final l in sent) {
        expect((l['qtySold'] as int) + (l['qtyReturned'] as int), 2);
      }
    });

    testWidgets('withdrawal screen reaches product 150 and sends its exact line', (tester) async {
      final data = _docMap('c150', 'ISSUED', _issuedLines());
      final doc = ConsignmentDoc.fromMap('c150', data);
      await open(tester, data, (_) => ConsignmentReturnItemsScreen(lojaId: 'loja', doc: doc));
      expect(tester.takeException(), isNull);
      final lastInc = find.byKey(const Key('consignment_return_inc_${_n - 1}'));
      await tester.scrollUntilVisible(lastInc, 400, scrollable: find.byType(Scrollable).first);
      await tester.tap(lastInc);
      await tester.pump();
      await tester.tap(find.byKey(const Key('consignment_return_confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('consignment_return_dialog_confirm')));
      await tester.pumpAndSettle();
      final call = calls.singleWhere((c) => c['operation'] == 'returnItems');
      expect(call['payload']['lines'], [
        {
          'lineId': 'p$_n::\u001e\u001e',
          'productId': 'p$_n',
          'variationKey': {'size': '', 'color': '', 'extra': ''},
          'qty': 1,
        },
      ]);
    });
  });
}
