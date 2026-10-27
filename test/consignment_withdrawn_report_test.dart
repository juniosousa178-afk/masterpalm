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

/// Text before the "RETIRADAS ANTES DO ACERTO" history: the active consignment section.
String _activeSection(ConsignmentPdfText pdf) {
  final i = pdf.text.indexOf('RETIRADAS ANTES DO ACERTO');
  return i < 0 ? pdf.text : pdf.text.substring(0, i);
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

    test('issued 3, withdrawn 1: report quantity is 2', () {
      final doc = _doc('ISSUED', [_line('A', 'Anel', 3, withdrawn: 1)]);
      final l = ConsignmentReportAggregator.consignedLinesOf(doc).single;
      expect(l.qtySent, 3, reason: 'issued history kept');
      expect(l.qtyWithdrawn, 1);
      expect(l.qtyConsigned, 2);
      expect(l.qtyPending, 2);
      expect(l.lineConsignedValue, 200);
    });

    test('issued 1, withdrawn 1: absent from the active lines but kept in history', () {
      final doc = _doc('ISSUED', [_line('A', 'Anel', 1, withdrawn: 1), _line('B', 'Brinco', 1)]);
      expect(ConsignmentReportAggregator.consignedLinesOf(doc).map((l) => l.productId), ['B']);
      expect(ConsignmentReportAggregator.linesOf(doc).map((l) => l.productId), ['A', 'B'],
          reason: 'historical line never deleted');
      expect(doc.lines.length, 2);
      expect(ConsignmentReportAggregator.withdrawalsOf(doc).single.productName, 'Anel');
    });

    test('issued 5, withdrawn 2, sold 1: consigned 3, remaining 2', () {
      final doc = _doc('ISSUED', [_line('A', 'Anel', 5, withdrawn: 2, sold: 1)]);
      final l = ConsignmentReportAggregator.consignedLinesOf(doc).single;
      expect(l.qtyConsigned, 3);
      expect(l.qtySold, 1);
      expect(l.qtyPending, 2);
      expect(consignmentLineOutstanding(doc.lines.single), 3);
    });

    test('variations 15 withdrawn, 16 kept, 17 sold: separate rows with their own price snapshot', () {
      final doc = _doc('ISSUED', [
        _line('R', 'Anel Solitário', 1, withdrawn: 1, size: '15', unit: 84.70),
        _line('R', 'Anel Solitário', 1, size: '16', unit: 90),
        _line('R', 'Anel Solitário', 1, sold: 1, size: '17', unit: 95.50),
      ]);
      final rows = ConsignmentReportAggregator.consignedLinesOf(doc);
      expect(rows.length, 2, reason: 'never merged into one row of 3');
      expect(rows.map((l) => l.variationLabel), ['Tamanho: 16', 'Tamanho: 17']);
      expect(rows.map((l) => l.unitPrice), [90, 95.50]);
      expect(rows.map((l) => l.qtyConsigned), [1, 1]);
      expect(rows.map((l) => l.qtyPending), [1, 0]);
      final history = ConsignmentReportAggregator.withdrawalsOf(doc).single;
      expect(history.variationLabel, 'Tamanho: 15');
      expect(history.unitPrice, 84.70);
      expect(doc.lines.first['variationSnapshot'], {'size': '15'});
      expect(doc.lines.first['gradeKey'], 'T15');
    });

    test('same product with different price snapshots stays in separate rows', () {
      final doc = _doc('ISSUED', [
        _line('A', 'Anel', 2, withdrawn: 1, unit: 100),
        _line('A', 'Anel', 1, unit: 120, lot: '#2'),
      ]);
      final rows = ConsignmentReportAggregator.consignedLinesOf(doc);
      expect(rows.map((l) => l.unitPrice), [100, 120]);
      expect(rows.map((l) => l.qtyConsigned), [1, 1]);
      expect(rows.fold<double>(0, (s, l) => s + l.lineConsignedValue), 220);
    });

    test('totals exclude withdrawn value; rollup exposes the withdrawn pieces', () {
      final issued = _doc('ISSUED', [_line('A', 'Anel', 3, withdrawn: 1), _line('B', 'Brinco', 1, withdrawn: 1)]);
      final settled = _doc('SETTLED', [_line('C', 'Colar', 2, withdrawn: 1, sold: 1, unit: 50)], id: 'c2');
      final rollup = ConsignmentReportAggregator.resellerRollup([issued, settled]);
      expect(rollup['sent'], 6);
      expect(rollup['withdrawn'], 3);
      expect(rollup['consigned'], 250, reason: '(400 - 200) + (100 - 50)');
      expect(rollup['pending'], 2);
      final totals = ConsignmentReportAggregator.generalTotals([rollup, rollup]);
      expect(totals['withdrawn'], 6);
      expect(totals['consigned'], 500);
    });

    test('building every report never mutates the consignment (no stock or line writes)', () async {
      final doc = _doc('ISSUED', [_line('A', 'Anel', 3, withdrawn: 1), _line('B', 'Brinco', 1, withdrawn: 1)]);
      final before = jsonEncode([doc.lines, doc.withdrawals], toEncodable: (o) => '$o');
      await _order(doc);
      await _settlement(doc);
      await ConsignmentReportPdfBuilder.buildCombinedPdf(
        store: _store,
        sections: [ConsignmentCombinedSection(doc: doc, lines: ConsignmentReportAggregator.consignedLinesOf(doc))],
      );
      ConsignmentReportAggregator.resellerRollup([doc]);
      expect(jsonEncode([doc.lines, doc.withdrawals], toEncodable: (o) => '$o'), before);
      expect(doc.lines.map(consignmentLineWithdrawn), [1, 1]);
    });
  });

  group('order PDF', () {
    test('nothing withdrawn: unchanged layout', () async {
      final pdf = await _order(_doc('ISSUED', [_line('A', 'Anel', 3)]));
      expect(pdf.text, contains('TOTAL DE PEÇAS: 3'));
      expect(pdf.text, contains('VALOR TOTAL CONSIGNADO: R\$ 300,00'));
      expect(pdf.text, isNot(contains('RETIRADAS')));
      expect(pdf.text, isNot(contains('Peças enviadas:')));
    });

    test('partial withdrawal: row shows 2 and totals exclude the withdrawn piece', () async {
      final pdf = await _order(_doc('ISSUED', [_line('A', 'Anel', 3, withdrawn: 1)]));
      final active = _activeSection(pdf);
      expect(active, contains('Anel 2 R\$ 100,00 R\$ 200,00'));
      expect(active, contains('TOTAL DE PEÇAS: 2'));
      expect(active, contains('VALOR TOTAL CONSIGNADO: R\$ 200,00'));
      expect(active, contains('Peças enviadas: 3 · retiradas antes do acerto: 1'));
      expect(pdf.text, contains('COM A REVENDEDORA: 2 peças'));
    });

    test('fully withdrawn product: only in the withdrawals history', () async {
      final pdf = await _order(_doc('ISSUED', [_line('A', 'Anel', 1, withdrawn: 1), _line('B', 'Brinco', 2)]));
      final active = _activeSection(pdf);
      expect(active, isNot(contains('Anel')));
      expect(active, contains('TOTAL DE MODELOS: 1'));
      expect(active, contains('TOTAL DE PEÇAS: 2'));
      expect(active, contains('VALOR TOTAL CONSIGNADO: R\$ 200,00'));
      expect(pdf.count('Anel'), 1);
      expect(pdf.text, contains('TOTAL RETIRADO: 1 peça · R\$ 100,00'));
    });

    test('variations: 15 only in history, 16 and 17 listed with their own prices', () async {
      final pdf = await _order(_doc('ISSUED', [
        _line('R', 'Anel Solitário', 1, withdrawn: 1, size: '15', unit: 84.70),
        _line('R', 'Anel Solitário', 1, size: '16', unit: 90),
        _line('R', 'Anel Solitário', 1, sold: 1, size: '17', unit: 95.50),
      ]));
      final active = _activeSection(pdf);
      expect(active, isNot(contains('Tamanho: 15')));
      expect(active, contains('Tamanho: 16 1 R\$ 90,00 R\$ 90,00'));
      expect(active, contains('Tamanho: 17 1 R\$ 95,50 R\$ 95,50'));
      expect(active, contains('TOTAL DE PEÇAS: 2'));
      expect(active, contains('VALOR TOTAL CONSIGNADO: R\$ 185,50'));
      expect(pdf.text, contains('Tamanho: 15 1 R\$ 84,70 R\$ 84,70'));
    });

    test('multiple units withdrawn across lines', () async {
      final pdf = await _order(_doc('ISSUED', [
        _line('A', 'Anel', 10, withdrawn: 4),
        _line('B', 'Brinco', 6, withdrawn: 6),
        _line('C', 'Colar', 3),
      ]));
      final active = _activeSection(pdf);
      expect(active, contains('TOTAL DE PEÇAS: 9'));
      expect(active, contains('VALOR TOTAL CONSIGNADO: R\$ 900,00'));
      expect(active, contains('Peças enviadas: 19 · retiradas antes do acerto: 10'));
      expect(active, isNot(contains('Brinco')));
    });
  });

  group('settlement PDF', () {
    test('ISSUED 5/2/1: Cons. 3, pending 2', () async {
      final pdf = await _settlement(_doc('ISSUED', [_line('A', 'Anel', 5, withdrawn: 2, sold: 1)]));
      final active = _activeSection(pdf);
      expect(active, contains('Cons.'));
      expect(active, contains('Anel 3 1 0 2'));
      expect(pdf.text, contains('Peças pendentes: 2'));
    });

    test('SETTLED: fully withdrawn line absent from the item table', () async {
      final pdf = await _settlement(_doc('SETTLED', [
        _line('A', 'Anel', 1, withdrawn: 1),
        _line('B', 'Brinco', 3, withdrawn: 1, sold: 1, returned: 1),
      ]));
      final active = _activeSection(pdf);
      expect(active, isNot(contains('Anel')));
      expect(active, contains('Brinco 2 1 1 0'));
      expect(pdf.text, contains('Peças enviadas: 4'));
      expect(pdf.text, contains('Peças retiradas antes do acerto: 2'));
      expect(pdf.text, contains('Peças pendentes: 0'));
    });

    test('nothing withdrawn keeps the Env column', () async {
      final pdf = await _settlement(_doc('SETTLED', [_line('A', 'Anel', 2, sold: 1, returned: 1)]));
      expect(pdf.text, contains('Env'));
      expect(pdf.text, isNot(contains('Cons.')));
    });
  });

  group('combined PDF', () {
    test('cover and sections count consigned pieces; summary keeps the issued history', () async {
      final a = _doc('ISSUED', [_line('A', 'Anel', 3, withdrawn: 1), _line('B', 'Brinco', 1, withdrawn: 1)]);
      final b = _doc('SETTLED', [_line('C', 'Colar', 2, sold: 2)], id: 'c2');
      final sections = [
        for (final d in [a, b])
          ConsignmentCombinedSection(doc: d, lines: ConsignmentReportAggregator.consignedLinesOf(d)),
      ];
      final summary = ConsignmentCombinedReportPlanner.summarize(sections);
      expect(summary.piecesSent, 6);
      expect(summary.piecesWithdrawn, 2);
      expect(summary.piecesConsigned, 4);
      expect(summary.consignedValue, 400);
      expect(summary.models, 2);
      final pdf = ConsignmentPdfText.parse(await ConsignmentReportPdfBuilder.buildCombinedPdf(
        store: _store,
        sections: sections,
        generatedAt: DateTime(2026, 10, 10),
      ));
      expect(pdf.text, contains('TOTAL DE PEÇAS: 4'));
      expect(pdf.text, contains('VALOR TOTAL CONSIGNADO: R\$ 400,00'));
      expect(pdf.text, contains('Total de peças enviadas: 6'));
      expect(pdf.text, contains('Peças retiradas antes do acerto: 2'));
      expect(pdf.text, contains('Total de peças consignadas: 4'));
      expect(pdf.count('Brinco'), 1, reason: 'only in the withdrawals history');
    });
  });

  group('general PDF', () {
    test('Ret. column and consigned value net of withdrawals', () async {
      final doc = _doc('ISSUED', [_line('A', 'Anel', 3, withdrawn: 1)]);
      final row = {...ConsignmentReportAggregator.resellerRollup([doc]), 'name': 'Maria'};
      final totals = ConsignmentReportAggregator.generalTotals([row]);
      final pdf = ConsignmentPdfText.parse(await ConsignmentReportPdfBuilder.buildGeneralPdf(
        store: _store,
        range: ConsignmentReportDateRange(DateTime(2026, 10, 1), DateTime(2026, 11, 1)),
        statusFilterLabel: 'Todos',
        resellerRows: [row],
        totals: totals,
      ));
      expect(pdf.text, contains('Ret.'));
      expect(pdf.text, contains('Maria 1 3 0 0 1 2 R\$ 200,00'));
      expect(pdf.text, contains('TOTAL GERAL 1 3 0 0 1 2 R\$ 200,00'));
    });
  });
}
