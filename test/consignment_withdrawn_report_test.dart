import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_models.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_data.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_pdf.dart';

import 'support/consignment_pdf_text.dart';

const _store = ConsignmentStoreProfile(lojaId: 'loja', name: 'Loja Teste');

Map<String, dynamic> _line(
  String productId,
  String name,
  int sent, {
  int withdrawn = 0,
  int sold = 0,
  int returned = 0,
  double unit = 100,
  String size = '',
  String lot = '',
}) {
  final vk = {'size': size, 'color': '', 'extra': ''};
  return {
    'lineId': '$productId::$size$lot',
    'productId': productId,
    'productNameSnapshot': name,
    'productCodeSnapshot': 'C-$productId',
    'productType': size.isEmpty ? 'simple' : 'grade',
    'variationKey': vk,
    if (size.isNotEmpty) 'variationSnapshot': {'size': size},
    if (size.isNotEmpty) 'gradeKey': 'T$size',
    'qtySent': sent,
    'qtySold': sold,
    'qtyReturned': returned,
    if (withdrawn > 0) 'qtyWithdrawn': withdrawn,
    'unitSalePriceSnapshot': unit,
    'commissionType': 'PERCENTUAL',
    'commissionValueSnapshot': 10,
    'potentialGrossAmount': sent * unit,
    'lineGrossAmount': sold * unit,
    'lineCommissionAmount': sold * unit * 0.1,
    'lineNetAmount': sold * unit * 0.9,
  };
}

Map<String, dynamic> _withdrawal(List<Map<String, dynamic>> lines) => {
      'withdrawalId': 'consignment_return_c1_x',
      'kind': 'WITHDRAWAL',
      'reason': 'MERCHANT_RETRIEVAL_BEFORE_SETTLEMENT',
      'createdAt': DateTime(2026, 10, 5, 15),
      'lines': [
        for (final l in lines)
          if (consignmentLineWithdrawn(l) > 0) {...l},
      ],
    };

ConsignmentDoc _doc(String status, List<Map<String, dynamic>> lines, {String id = 'c1'}) {
  int sum(String k) => lines.fold<int>(0, (s, l) => s + ((l[k] as num?)?.toInt() ?? 0));
  double money(String k) => lines.fold<double>(0, (s, l) => s + ((l[k] as num?)?.toDouble() ?? 0));
  final withdrawn = lines.where((l) => consignmentLineWithdrawn(l) > 0).toList();
  return ConsignmentDoc.fromMap(id, {
    'id': id,
    'storeId': 'loja',
    'resellerId': 'maria',
    'resellerSnapshot': {'resellerId': 'maria', 'displayName': 'Maria'},
    'status': status,
    'lines': lines,
    'withdrawals': withdrawn.isEmpty ? <Map<String, dynamic>>[] : [_withdrawal(withdrawn)],
    'totalItemsSent': sum('qtySent'),
    'totalItemsSold': sum('qtySold'),
    'totalItemsReturned': sum('qtyReturned'),
    'potentialGrossAmount': money('potentialGrossAmount'),
    'grossSoldAmount': status == 'SETTLED' ? money('lineGrossAmount') : 0,
    'commissionAmount': status == 'SETTLED' ? money('lineCommissionAmount') : 0,
    'netAmount': status == 'SETTLED' ? money('lineNetAmount') : 0,
    'revision': 3,
    'issuedAt': DateTime(2026, 10, 1, 10),
    'createdAt': DateTime(2026, 10, 1, 9),
    if (status == 'SETTLED') 'settledAt': DateTime(2026, 10, 9, 10),
  });
}

Future<ConsignmentPdfText> _order(ConsignmentDoc doc) async => ConsignmentPdfText.parse(
      await ConsignmentReportPdfBuilder.buildOrderPdf(
        store: _store,
        doc: doc,
        lines: ConsignmentReportAggregator.consignedLinesOf(doc),
      ),
    );

Future<ConsignmentPdfText> _settlement(ConsignmentDoc doc) async => ConsignmentPdfText.parse(
      await ConsignmentReportPdfBuilder.buildSettlementPdf(
        store: _store,
        doc: doc,
        lines: ConsignmentReportAggregator.consignedLinesOf(doc),
      ),
    );

Future<ConsignmentPdfText> _combined(List<ConsignmentDoc> docs) async => ConsignmentPdfText.parse(
      await ConsignmentReportPdfBuilder.buildCombinedPdf(
        store: _store,
        sections: [
          for (final d in docs)
            ConsignmentCombinedSection(doc: d, lines: ConsignmentReportAggregator.consignedLinesOf(d)),
        ],
        generatedAt: DateTime(2026, 10, 10),
      ),
    );

Future<ConsignmentPdfText> _general(List<ConsignmentDoc> docs) async {
  final row = {...ConsignmentReportAggregator.resellerRollup(docs), 'name': 'Maria'};
  return ConsignmentPdfText.parse(await ConsignmentReportPdfBuilder.buildGeneralPdf(
    store: _store,
    range: ConsignmentReportDateRange(DateTime(2026, 10, 1), DateTime(2026, 11, 1)),
    statusFilterLabel: 'Todos',
    resellerRows: [row],
    totals: ConsignmentReportAggregator.generalTotals([row]),
  ));
}

Future<List<ConsignmentPdfText>> _allPdfs(ConsignmentDoc doc) async =>
    [await _order(doc), await _settlement(doc), await _combined([doc]), await _general([doc])];

void _expectNoWithdrawalTrace(ConsignmentPdfText pdf) {
  expect(pdf.text, isNot(contains('RETIRAD')));
  expect(pdf.text, isNot(contains('Retirad')));
  expect(pdf.text, isNot(contains('retirad')));
  expect(pdf.text, isNot(contains('COM A REVENDEDORA')));
  expect(pdf.text, isNot(contains('Ret.')));
}

void main() {
  group('projection', () {
    test('nothing withdrawn: consigned lines equal the issued lines', () {
      final doc = _doc('ISSUED', [_line('A', 'Anel', 2), _line('B', 'Brinco', 1)]);
      final all = ConsignmentReportAggregator.linesOf(doc);
      final consigned = ConsignmentReportAggregator.consignedLinesOf(doc);
      expect(consigned.map((l) => l.productId), all.map((l) => l.productId));
      expect(consigned.map((l) => l.qtyConsigned), [2, 1]);
      expect(consigned.map((l) => l.lineConsignedValue), [200, 100]);
    });

    test('issued 5, withdrawn 2: report quantity is 3', () {
      final doc = _doc('ISSUED', [_line('A', 'Anel', 5, withdrawn: 2)]);
      final l = ConsignmentReportAggregator.consignedLinesOf(doc).single;
      expect(l.qtyConsigned, 3);
      expect(l.qtyPending, 3);
      expect(l.lineConsignedValue, 300);
    });

    test('issued 1, withdrawn 1: line hidden from the report rows', () {
      final doc = _doc('ISSUED', [_line('A', 'Anel', 1, withdrawn: 1), _line('B', 'Brinco', 1)]);
      expect(ConsignmentReportAggregator.consignedLinesOf(doc).map((l) => l.productId), ['B']);
    });

    test('issued 5, withdrawn 2, sold 1: consigned 3, sold 1, remaining 2', () {
      final doc = _doc('ISSUED', [_line('A', 'Anel', 5, withdrawn: 2, sold: 1)]);
      final l = ConsignmentReportAggregator.consignedLinesOf(doc).single;
      expect(l.qtyConsigned, 3);
      expect(l.qtySold, 1);
      expect(l.qtyPending, 2);
    });

    test('variations: only the fully withdrawn one is hidden; price snapshots kept per line', () {
      final doc = _doc('ISSUED', [
        _line('R', 'Anel Solitário', 1, withdrawn: 1, size: '15', unit: 84.70),
        _line('R', 'Anel Solitário', 1, size: '16', unit: 90),
        _line('R', 'Anel Solitário', 1, sold: 1, size: '17', unit: 95.50),
      ]);
      final rows = ConsignmentReportAggregator.consignedLinesOf(doc);
      expect(rows.length, 2, reason: 'never merged into one row');
      expect(rows.map((l) => l.variationLabel), ['Tamanho: 16', 'Tamanho: 17']);
      expect(rows.map((l) => l.unitPrice), [90, 95.50]);
      expect(rows.map((l) => l.qtyPending), [1, 0]);
    });

    test('same product with different price snapshots stays in separate rows', () {
      final doc = _doc('ISSUED', [
        _line('A', 'Anel', 2, withdrawn: 1, unit: 100),
        _line('A', 'Anel', 1, unit: 120, lot: '#2'),
      ]);
      final rows = ConsignmentReportAggregator.consignedLinesOf(doc);
      expect(rows.map((l) => l.unitPrice), [100, 120]);
      expect(rows.map((l) => l.qtyConsigned), [1, 1]);
    });

    test('rollup and general totals: withdrawn pieces contribute zero', () {
      final issued = _doc('ISSUED', [_line('A', 'Anel', 3, withdrawn: 1), _line('B', 'Brinco', 1, withdrawn: 1)]);
      final settled = _doc('SETTLED', [_line('C', 'Colar', 2, withdrawn: 1, sold: 1, unit: 50)], id: 'c2');
      final rollup = ConsignmentReportAggregator.resellerRollup([issued, settled]);
      expect(rollup['sent'], 3);
      expect(rollup.containsKey('withdrawn'), isFalse);
      expect(rollup['consigned'], 250, reason: '(400 - 200) + (100 - 50)');
      expect(rollup['pending'], 2);
      final totals = ConsignmentReportAggregator.generalTotals([rollup, rollup]);
      expect(totals['sent'], 6);
      expect(totals['consigned'], 500);
    });

    test('generating every PDF keeps qtyWithdrawn and withdrawals[] intact', () async {
      final doc = _doc('ISSUED', [_line('A', 'Anel', 3, withdrawn: 1), _line('B', 'Brinco', 1, withdrawn: 1)]);
      String snapshot() => jsonEncode([doc.lines, doc.withdrawals], toEncodable: (o) => '$o');
      final before = snapshot();
      await _allPdfs(doc);
      expect(snapshot(), before);
      expect(doc.lines.map(consignmentLineWithdrawn), [1, 1]);
      expect(doc.withdrawals.length, 1);
      expect((doc.withdrawals.single['lines'] as List).length, 2);
      expect(doc.lines.length, 2, reason: 'historical line never deleted');
    });
  });

  group('PDFs', () {
    test('nothing withdrawn: unchanged order and settlement layout', () async {
      final doc = _doc('ISSUED', [_line('A', 'Anel', 3)]);
      final order = await _order(doc);
      expect(order.text, contains('Anel 3 R\$ 100,00 R\$ 300,00'));
      expect(order.text, contains('TOTAL DE PEÇAS: 3'));
      final settlement = await _settlement(doc);
      expect(settlement.text, contains('Peças enviadas: 3'));
    });

    test('fully withdrawn product: absent from every PDF', () async {
      final doc = _doc('ISSUED', [_line('A', 'Anel Retirado X', 1, withdrawn: 1), _line('B', 'Brinco', 2)]);
      for (final pdf in await _allPdfs(doc)) {
        expect(pdf.text, isNot(contains('Anel Retirado X')));
        _expectNoWithdrawalTrace(pdf);
      }
      final order = await _order(doc);
      expect(order.text, contains('TOTAL DE MODELOS: 1'));
      expect(order.text, contains('TOTAL DE PEÇAS: 2'));
      expect(order.text, contains('VALOR TOTAL CONSIGNADO: R\$ 200,00'));
    });

    test('5 sent, 2 withdrawn: every PDF shows 3 and no withdrawn row', () async {
      final doc = _doc('ISSUED', [_line('A', 'Anel', 5, withdrawn: 2)]);
      final pdfs = await _allPdfs(doc);
      for (final pdf in pdfs) {
        _expectNoWithdrawalTrace(pdf);
      }
      final [order, settlement, combined, general] = pdfs;
      expect(order.text, contains('Anel 3 R\$ 100,00 R\$ 300,00'));
      expect(order.count('Anel'), 1);
      expect(order.text, contains('TOTAL DE PEÇAS: 3'));
      expect(order.text, contains('VALOR TOTAL CONSIGNADO: R\$ 300,00'));
      expect(settlement.text, contains('Anel 3 0 0 3'));
      expect(settlement.text, contains('Peças enviadas: 3'));
      expect(combined.text, contains('TOTAL DE PEÇAS: 3'));
      expect(combined.text, contains('Total de peças enviadas: 3'));
      expect(combined.text, contains('VALOR TOTAL CONSIGNADO: R\$ 300,00'));
      expect(general.text, contains('Maria 1 3 0 0 3 R\$ 300,00'));
      expect(general.text, contains('TOTAL GERAL 1 3 0 0 3 R\$ 300,00'));
    });

    test('5 sent, 2 withdrawn, 1 sold: only consigned, sold and remaining', () async {
      final doc = _doc('ISSUED', [_line('A', 'Anel', 5, withdrawn: 2, sold: 1)]);
      for (final pdf in await _allPdfs(doc)) {
        _expectNoWithdrawalTrace(pdf);
      }
      final settlement = await _settlement(doc);
      expect(settlement.text, contains('Anel 3 1 0 2'));
      expect(settlement.text, contains('Peças enviadas: 3'));
      expect(settlement.text, contains('Peças vendidas: 1'));
      expect(settlement.text, contains('Peças pendentes: 2'));
    });

    test('variations: 15 hidden everywhere, 16 and 17 listed with their own prices', () async {
      final doc = _doc('ISSUED', [
        _line('R', 'Anel Solitário', 1, withdrawn: 1, size: '15', unit: 84.70),
        _line('R', 'Anel Solitário', 1, size: '16', unit: 90),
        _line('R', 'Anel Solitário', 1, sold: 1, size: '17', unit: 95.50),
      ]);
      for (final pdf in await _allPdfs(doc)) {
        expect(pdf.text, isNot(contains('Tamanho: 15')));
        expect(pdf.text, isNot(contains('84,70')));
        _expectNoWithdrawalTrace(pdf);
      }
      final order = await _order(doc);
      expect(order.text, contains('Tamanho: 16 1 R\$ 90,00 R\$ 90,00'));
      expect(order.text, contains('Tamanho: 17 1 R\$ 95,50 R\$ 95,50'));
      expect(order.text, contains('VALOR TOTAL CONSIGNADO: R\$ 185,50'));
    });

    test('SETTLED with withdrawals: settlement shows only consigned pieces', () async {
      final doc = _doc('SETTLED', [
        _line('A', 'Anel', 1, withdrawn: 1),
        _line('B', 'Brinco', 3, withdrawn: 1, sold: 1, returned: 1),
      ]);
      for (final pdf in await _allPdfs(doc)) {
        expect(pdf.text, isNot(contains('Anel')));
        _expectNoWithdrawalTrace(pdf);
      }
      final settlement = await _settlement(doc);
      expect(settlement.text, contains('Brinco 2 1 1 0'));
      expect(settlement.text, contains('Peças enviadas: 2'));
      expect(settlement.text, contains('Peças pendentes: 0'));
    });

    test('combined: withdrawn pieces out of cover, sections and summary', () async {
      final a = _doc('ISSUED', [_line('A', 'Anel', 3, withdrawn: 1), _line('B', 'Brinco', 1, withdrawn: 1)]);
      final b = _doc('SETTLED', [_line('C', 'Colar', 2, sold: 2)], id: 'c2');
      final summary = ConsignmentCombinedReportPlanner.summarize([
        for (final d in [a, b])
          ConsignmentCombinedSection(doc: d, lines: ConsignmentReportAggregator.consignedLinesOf(d)),
      ]);
      expect(summary.piecesSent, 4);
      expect(summary.consignedValue, 400);
      expect(summary.models, 2);
      final pdf = await _combined([a, b]);
      _expectNoWithdrawalTrace(pdf);
      expect(pdf.text, isNot(contains('Brinco')));
      expect(pdf.text, contains('TOTAL DE PEÇAS: 4'));
      expect(pdf.text, contains('Total de peças enviadas: 4'));
      expect(pdf.text, contains('VALOR TOTAL CONSIGNADO: R\$ 400,00'));
    });
  });
}
