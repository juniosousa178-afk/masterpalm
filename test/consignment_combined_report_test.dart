import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_models.dart';
import 'package:master_palm/features/consignments/consignment_service.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_actions.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_data.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_pdf.dart';
import 'package:master_palm/features/consignments/reports/screens/consignment_report_preview_screen.dart';
import 'package:master_palm/features/consignments/screens/consignment_reseller_history_screen.dart';

import 'support/consignment_pdf_text.dart';

const _store = ConsignmentStoreProfile(
  lojaId: 'mirjoias',
  name: 'Loja Teste',
  cnpj: '',
  phone: '',
  whatsapp: '',
  instagram: '',
  address: '',
  logoUrl: '',
);

Map<String, dynamic> _line(String productId, String name, int qty, {double unit = 100, int sold = 0, int returned = 0}) => {
      'productId': productId,
      'productNameSnapshot': name,
      'qtySent': qty,
      'qtySold': sold,
      'qtyReturned': returned,
      'unitSalePriceSnapshot': unit,
      'commissionType': 'PERCENTUAL',
      'commissionValueSnapshot': 20,
      'variationKey': {'size': '', 'color': '', 'extra': ''},
      'lineGrossAmount': sold * unit,
      'lineCommissionAmount': sold * unit * 0.2,
      'lineNetAmount': sold * unit * 0.8,
      'potentialGrossAmount': qty * unit,
    };

ConsignmentDoc _doc(
  String id, {
  String storeId = 'mirjoias',
  String resellerId = 'r1',
  String resellerName = 'Maria',
  String status = 'ISSUED',
  List<Map<String, dynamic>>? lines,
  DateTime? issuedAt,
  DateTime? createdAt,
  bool isDeleted = false,
  double gross = 0,
  double commission = 0,
  double net = 0,
}) {
  final ls = lines ?? [_line('p-$id', 'Produto $id', 1)];
  int sum(String k) => ls.fold<int>(0, (s, l) => s + ((l[k] as num?)?.toInt() ?? 0));
  return ConsignmentDoc(
    id: id,
    storeId: storeId,
    resellerId: resellerId,
    resellerName: resellerName,
    status: status,
    lines: ls,
    totalItemsSent: sum('qtySent'),
    totalItemsSold: sum('qtySold'),
    totalItemsReturned: sum('qtyReturned'),
    grossSoldAmount: gross,
    commissionAmount: commission,
    netAmount: net,
    potentialGrossAmount: ls.fold<double>(0, (s, l) => s + (l['potentialGrossAmount'] as num).toDouble()),
    issuedAt: issuedAt,
    createdAt: createdAt ?? issuedAt,
    isDeleted: isDeleted,
  );
}

List<ConsignmentCombinedSection> _sections(List<ConsignmentDoc> docs) => [
      for (final d in ConsignmentCombinedReportPlanner.order(docs))
        ConsignmentCombinedSection(
          doc: d,
          lines: ConsignmentReportAggregator.linesOf(
            d,
            meta: {
              for (final l in d.lines)
                '${l['productId']}': ConsignmentProductReportMeta(productCode: 'COD-${l['productId']}'),
            },
          ),
        ),
    ];

Future<ConsignmentPdfText> _combinedPdf(List<ConsignmentDoc> docs) async {
  final bytes = await ConsignmentReportPdfBuilder.buildCombinedPdf(
    store: _store,
    sections: _sections(docs),
    generatedAt: DateTime(2026, 10, 8, 10, 30),
  );
  return ConsignmentPdfText.parse(bytes);
}

/// Firestore content without the empty placeholders the fake leaves behind for plain reads
/// of missing documents; any created, updated or deleted field still shows up.
String _stored(FakeFirebaseFirestore fake) {
  Object? prune(Object? v) {
    if (v is! Map) return v;
    final out = <String, Object?>{};
    for (final e in v.entries) {
      final p = prune(e.value);
      if (p is Map && p.isEmpty) continue;
      out['${e.key}'] = p;
    }
    return out;
  }

  return jsonEncode(prune(jsonDecode(fake.dump())));
}

String _brl(num v) {
  final fixed = v.toStringAsFixed(2).split('.');
  final intPart = fixed[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return 'R\$ $intPart,${fixed[1]}';
}

List<ConsignmentDoc> _series(int n, {int bigIndex = -1, int bigLines = 0}) => [
      for (var i = 0; i < n; i++)
        _doc(
          'cons${i.toString().padLeft(2, '0')}',
          issuedAt: DateTime(2026, 9, 1 + i),
          lines: [
            _line('shared', 'Anel Compartilhado', 1),
            if (i == bigIndex)
              for (var j = 0; j < bigLines; j++)
                _line('big$j', 'Grande ${j.toString().padLeft(3, '0')}', 1, unit: 10)
            else
              _line('own$i', 'Exclusivo ${i.toString().padLeft(2, '0')}', 2, unit: 50),
          ],
        ),
    ];

void _expectCombinedPdf(ConsignmentPdfText pdf, List<ConsignmentDoc> docs, {required bool exactPages}) {
  final n = docs.length;
  final sections = _sections(docs);
  final summary = ConsignmentCombinedReportPlanner.summarize(sections);
  expect(pdf.count('RELATÓRIO CONSOLIDADO DE CONSIGNAÇÕES'), 1);
  expect(pdf.count('RESUMO GERAL'), 1);
  for (var i = 1; i <= n; i++) {
    expect(pdf.count('CONSIGNAÇÃO $i DE $n'), 1, reason: 'section $i once');
  }
  expect(pdf.count('CONSIGNAÇÃO ${n + 1} DE $n'), 0);
  for (final s in sections) {
    expect(pdf.count('Nº ${s.doc.id}'), 1, reason: 'section header ${s.doc.id}');
    expect(pdf.count(s.doc.id), 2, reason: 'cover index + section ${s.doc.id}');
    for (final l in s.lines) {
      if (l.productId == 'shared') continue;
      expect(pdf.count(l.productName), 1, reason: 'row ${l.productName}');
    }
    expect(pdf.count('TOTAL DE PEÇAS: ${s.pieces}') >= 1, isTrue);
  }
  expect(pdf.count('Anel Compartilhado'), n, reason: 'same product kept in each consignment');
  expect(pdf.count('CONSIGNAÇÕES SELECIONADAS: $n'), 1);
  expect(pdf.count('TOTAL DE PEÇAS: ${summary.piecesSent}'), greaterThanOrEqualTo(1));
  expect(pdf.text, contains('VALOR TOTAL CONSIGNADO: ${_brl(summary.consignedValue)}'));
  expect(pdf.text, contains('Total de peças enviadas: ${summary.piecesSent}'));
  expect(pdf.text, contains('Valor total consignado: ${_brl(summary.consignedValue)}'));
  final pages = pdf.pageTexts;
  final footers = pages.length - 1;
  expect(footers, pdf.pageCount, reason: 'one footer per page');
  final footerPrefix = RegExp(r'Loja Teste · MasterPalm · \S+ \S+ ·');
  expect(pages.first.replaceAll(footerPrefix, '').trim(), isEmpty, reason: 'footer is painted first');
  for (var p = 1; p <= footers; p++) {
    final body = pages[p].replaceAll(footerPrefix, '').trim();
    expect(body.split(' ').length, greaterThan(5), reason: 'page $p has content');
  }
  if (exactPages) expect(pdf.pageCount, n + 2);
}

void main() {
  group('selection rules', () {
    test('A 10 pcs / R\$1000 + B 5 pcs / R\$500 = 2 consignments, 15 pcs, R\$1500', () async {
      final a = _doc('A', issuedAt: DateTime(2026, 9, 1), lines: [_line('pa', 'Colar A', 10)]);
      final b = _doc('B', issuedAt: DateTime(2026, 9, 2), lines: [_line('pb', 'Brinco B', 5)]);
      expect(ConsignmentCombinedReportPlanner.validateSelection(lojaId: 'mirjoias', docs: [a, b]), isNull);
      final summary = ConsignmentCombinedReportPlanner.summarize(_sections([b, a]));
      expect(summary.consignments, 2);
      expect(summary.piecesSent, 15);
      expect(summary.consignedValue, 1500);
      final pdf = await _combinedPdf([b, a]);
      expect(pdf.text, contains('CONSIGNAÇÕES SELECIONADAS: 2'));
      expect(pdf.text, contains('TOTAL DE PEÇAS: 15'));
      expect(pdf.text, contains('VALOR TOTAL CONSIGNADO: R\$ 1.500,00'));
      expect(pdf.text, contains('TOTAL DE PEÇAS: 10'));
      expect(pdf.text, contains('TOTAL DE PEÇAS: 5'));
    });

    test('different customer is blocked even with the same display name', () async {
      final a = _doc('A', resellerId: 'r1', resellerName: 'Maria', issuedAt: DateTime(2026, 9, 1));
      final b = _doc('B', resellerId: 'r2', resellerName: 'Maria', issuedAt: DateTime(2026, 9, 2));
      expect(
        ConsignmentCombinedReportPlanner.validateSelection(lojaId: 'mirjoias', docs: [a, b]),
        consignmentCombinedSameCustomerMessage,
      );
      expect(consignmentCombinedSameCustomerMessage, 'Selecione consignações da mesma cliente para imprimir juntas.');
      final fake = FakeFirebaseFirestore();
      ConsignmentReportDataService.debugFirestore = fake;
      addTearDown(() => ConsignmentReportDataService.debugFirestore = null);
      await expectLater(
        ConsignmentReportActions.buildCombinedBytes(lojaId: 'mirjoias', docs: [a, b]),
        throwsA(isA<ConsignmentCombinedSelectionException>()
            .having((e) => e.message, 'message', consignmentCombinedSameCustomerMessage)),
      );
    });

    test('empty reseller id is never treated as the same customer', () {
      final a = _doc('A', resellerId: '');
      final b = _doc('B', resellerId: '');
      expect(
        ConsignmentCombinedReportPlanner.validateSelection(lojaId: 'mirjoias', docs: [a, b]),
        consignmentCombinedSameCustomerMessage,
      );
    });

    test('other store, cancelled, deleted and single selection are blocked', () {
      final a = _doc('A');
      expect(
        ConsignmentCombinedReportPlanner.validateSelection(lojaId: 'mirjoias', docs: [a, _doc('X', storeId: 'nathy')]),
        consignmentCombinedSameStoreMessage,
      );
      expect(
        ConsignmentCombinedReportPlanner.validateSelection(lojaId: 'mirjoias', docs: [a, _doc('C', status: 'CANCELLED')]),
        consignmentCombinedUnsupportedStatusMessage,
      );
      expect(
        ConsignmentCombinedReportPlanner.validateSelection(
          lojaId: 'mirjoias',
          docs: [a, _doc('D', status: 'CANCELLED', isDeleted: true)],
        ),
        consignmentCombinedUnsupportedStatusMessage,
      );
      expect(
        ConsignmentCombinedReportPlanner.validateSelection(lojaId: 'mirjoias', docs: [a]),
        consignmentCombinedMinSelectionMessage,
      );
      expect(
        ConsignmentCombinedReportPlanner.validateSelection(lojaId: 'mirjoias', docs: [a, a]),
        consignmentCombinedMinSelectionMessage,
      );
    });

    test('supported statuses match the single order report', () {
      expect(ConsignmentCombinedReportPlanner.supportedStatuses, {'DRAFT', 'ISSUED', 'SETTLED'});
      for (final s in ['DRAFT', 'ISSUED', 'SETTLED']) {
        expect(ConsignmentCombinedReportPlanner.canSelect(_doc('x', status: s)), isTrue, reason: s);
      }
      expect(ConsignmentCombinedReportPlanner.canSelect(_doc('x', status: 'CANCELLED')), isFalse);
      expect(ConsignmentCombinedReportPlanner.canSelect(_doc('x', isDeleted: true)), isFalse);
    });

    test('order is oldest first by issue/creation date, ties by id, undated last', () {
      final docs = [
        _doc('z-undated'),
        _doc('b', issuedAt: DateTime(2026, 9, 5)),
        _doc('a', issuedAt: DateTime(2026, 9, 5)),
        _doc('draft', createdAt: DateTime(2026, 9, 3)),
        _doc('old', issuedAt: DateTime(2026, 8, 1)),
        _doc('a-undated'),
      ];
      const expected = ['old', 'draft', 'a', 'b', 'a-undated', 'z-undated'];
      expect(ConsignmentCombinedReportPlanner.order(docs).map((d) => d.id), expected);
      expect(ConsignmentCombinedReportPlanner.order(docs.reversed).map((d) => d.id), expected);
      expect(ConsignmentCombinedReportPlanner.order([...docs, ...docs]).map((d) => d.id), expected);
    });

    test('settled totals come from the persisted consignment totals', () {
      final settled = _doc(
        'S',
        status: 'SETTLED',
        issuedAt: DateTime(2026, 9, 1),
        lines: [_line('p1', 'Anel', 10, sold: 7, returned: 3)],
        gross: 700,
        commission: 140,
        net: 560,
      );
      final open = _doc('O', issuedAt: DateTime(2026, 9, 2), lines: [_line('p1', 'Anel', 4)]);
      final s = ConsignmentCombinedReportPlanner.summarize(_sections([settled, open]));
      expect(s.piecesSent, 14);
      expect(s.piecesSold, 7);
      expect(s.piecesReturned, 3);
      expect(s.piecesPending, 4);
      expect(s.settledCount, 1);
      expect(s.grossSold, 700);
      expect(s.commission, 140);
      expect(s.net, 560);
      expect(s.byStatus, {'SETTLED': 1, 'ISSUED': 1});
    });

    test('file name is sanitized and carries only customer name and date', () {
      final name = ConsignmentReportDataService.combinedFileName(
        'Maria/Silva? (11) 98888-7777',
        now: DateTime(2026, 10, 8),
      );
      expect(name, startsWith('consignacoes_'));
      expect(name, endsWith('_2026-10-08.pdf'));
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains('?')));
      expect(name, isNot(contains(' ')));
    });
  });

  group('combined pdf', () {
    test('2 consignments', () async {
      final docs = _series(2);
      _expectCombinedPdf(await _combinedPdf(docs), docs, exactPages: true);
    });

    test('5 consignments', () async {
      final docs = _series(5);
      _expectCombinedPdf(await _combinedPdf(docs), docs, exactPages: true);
    });

    test('10 consignments, one with 120 items spanning pages', () async {
      final docs = _series(10, bigIndex: 3, bigLines: 120);
      final pdf = await _combinedPdf(docs);
      _expectCombinedPdf(pdf, docs, exactPages: false);
      expect(pdf.pageCount, greaterThan(12));
      for (var j = 0; j < 120; j++) {
        expect(pdf.count('Grande ${j.toString().padLeft(3, '0')}'), 1);
      }
      expect(pdf.text, contains('TOTAL DE PEÇAS: 121'));
      expect(pdf.text, contains('VALOR TOTAL CONSIGNADO: ${_brl(1300)}'));
    });

    test('settled section shows its own settlement summary', () async {
      final docs = [
        _doc(
          'S1',
          status: 'SETTLED',
          issuedAt: DateTime(2026, 9, 1),
          lines: [_line('p1', 'Anel', 10, sold: 7, returned: 3)],
          gross: 700,
          commission: 140,
          net: 560,
        ),
        _doc('I1', issuedAt: DateTime(2026, 9, 2)),
      ];
      final pdf = await _combinedPdf(docs);
      expect(pdf.count('RESUMO DO ACERTO'), 1);
      expect(pdf.text, contains('Comissão: R\$ 140,00'));
      expect(pdf.text, contains('Peças vendidas: 7'));
      expect(pdf.text, contains('Peças devolvidas: 3'));
    });
  });

  group('read only', () {
    late FakeFirebaseFirestore fake;
    late List<String> calls;

    setUp(() async {
      fake = FakeFirebaseFirestore();
      calls = [];
      ConsignmentReportDataService.debugFirestore = fake;
      ConsignmentService.debugFirestore = fake;
      ConsignmentService.debugTransport = (name, data) async {
        calls.add(name);
        return <String, dynamic>{};
      };
      await fake.collection('lojas').doc('mirjoias').set({'nome': 'Loja Teste'});
      await fake
          .collection('lojas')
          .doc('mirjoias')
          .collection('estoque_produtos')
          .doc('pa')
          .set({'codigo': 'AN32SM', 'quantidade': 0});
    });

    tearDown(() {
      ConsignmentReportDataService.debugFirestore = null;
      ConsignmentService.debugFirestore = null;
      ConsignmentService.debugTransport = null;
    });

    test('generating the combined report writes nothing', () async {
      final before = _stored(fake);
      final bytes = await ConsignmentReportActions.buildCombinedBytes(
        lojaId: 'mirjoias',
        docs: [
          _doc('A', issuedAt: DateTime(2026, 9, 1), lines: [_line('pa', 'Colar A', 10)]),
          _doc('B', issuedAt: DateTime(2026, 9, 2), lines: [_line('pa', 'Colar A', 5)]),
        ],
      );
      expect(_stored(fake), before);
      expect(calls, isEmpty);
      final pdf = ConsignmentPdfText.parse(bytes);
      expect(pdf.count('AN32SM'), 2);
      expect(pdf.count('Colar A'), 2);
      expect(pdf.pageCount, 4);
    });

    testWidgets('select mode prints only same-customer selections', (tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('net.nfet.printing'),
        (call) async => call.method == 'printingInfo' ? <String, dynamic>{} : null,
      );
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('net.nfet.printing'), null));
      final col = fake.collection('lojas').doc('mirjoias').collection('consignments');
      Map<String, dynamic> raw(String reseller, String status, int day, {bool deleted = false}) => {
            'storeId': 'mirjoias',
            'resellerId': reseller,
            'resellerSnapshot': {'displayName': 'Maria'},
            'status': status,
            'lines': [_line('pa', 'Colar A', 2)],
            'totalItemsSent': 2,
            'issuedAt': DateTime(2026, 9, day),
            'createdAt': DateTime(2026, 9, day),
            if (deleted) 'isDeleted': true,
          };
      await col.doc('m1').set(raw('r1', 'ISSUED', 1));
      await col.doc('m2').set(raw('r1', 'SETTLED', 2));
      await col.doc('m3').set(raw('r1', 'CANCELLED', 3));
      await col.doc('m4').set(raw('r1', 'CANCELLED', 4, deleted: true));
      await col.doc('o1').set(raw('r2', 'ISSUED', 5));
      final before = _stored(fake);

      await tester.pumpWidget(const MaterialApp(home: ConsignmentResellerHistoryScreen(lojaId: 'mirjoias')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('consignment_select_mode')));
      await tester.pumpAndSettle();
      for (final tile in find.byType(ExpansionTile).evaluate().toList()) {
        await tester.tap(find.byWidget(tile.widget));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('consignment_select_m4')), findsNothing, reason: 'soft-deleted hidden');
      final cancelled = tester.widget<Checkbox>(find.byKey(const Key('consignment_select_m3')));
      expect(cancelled.onChanged, isNull, reason: 'cancelled not selectable');
      FilledButton printButton() =>
          tester.widget<FilledButton>(find.byKey(const Key('consignment_print_selected')));
      await tester.tap(find.byKey(const Key('consignment_select_m1')));
      await tester.pumpAndSettle();
      expect(printButton().onPressed, isNull, reason: 'needs 2+');

      await tester.tap(find.byKey(const Key('consignment_select_o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('consignment_print_selected')));
      await tester.pumpAndSettle();
      expect(find.text(consignmentCombinedSameCustomerMessage), findsOneWidget);
      expect(find.byType(ConsignmentReportPreviewScreen), findsNothing);

      await tester.tap(find.byKey(const Key('consignment_select_o1')));
      await tester.tap(find.byKey(const Key('consignment_select_m2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('consignment_print_selected')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ConsignmentReportPreviewScreen), findsOneWidget);
      expect(find.text('Relatório consolidado'), findsOneWidget);
      final preview = tester.widget<ConsignmentReportPreviewScreen>(find.byType(ConsignmentReportPreviewScreen));
      expect(preview.fileName, startsWith('consignacoes_Maria_'));
      final bytes = await tester.runAsync(() => preview.bytesFuture);
      final pdf = ConsignmentPdfText.parse(bytes!);
      expect(pdf.count('Nº m1'), 1);
      expect(pdf.count('Nº m2'), 1);
      expect(pdf.count('o1'), 0);
      expect(_stored(fake), before);
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
