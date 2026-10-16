import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_models.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_data.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_pdf.dart';

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

String _name(int i) => 'Anel 2 Folhas T.18 Prata 925 Modelo ${i.toString().padLeft(3, '0')}';

Map<String, dynamic> _line(int i, int qty, {int sold = 0, int returned = 0, int withdrawn = 0}) => {
      'lineId': 'p$i::\u001e\u001e',
      'productId': 'p$i',
      'productNameSnapshot': _name(i),
      'productCodeSnapshot': 'AN$i',
      'productType': 'simple',
      'variationKey': {'size': '', 'color': '', 'extra': ''},
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

Map<String, dynamic> _addition(String id, String kind, List<Map<String, dynamic>> lines) => {
      'additionId': id,
      'kind': kind,
      'createdAt': DateTime(2026, 10, 1, 10),
      'lines': [
        for (final l in lines) {'productNameSnapshot': l['productNameSnapshot'], 'qtyAdded': l['qtySent']},
      ],
    };

ConsignmentDoc _doc(
  String id,
  String status,
  List<Map<String, dynamic>> lines, {
  List<Map<String, dynamic>>? additions,
  List<Map<String, dynamic>> withdrawals = const [],
}) {
  int sum(String k) => lines.fold<int>(0, (s, l) => s + ((l[k] as num?)?.toInt() ?? 0));
  double sumD(String k) => lines.fold<double>(0, (s, l) => s + (l[k] as double));
  return ConsignmentDoc.fromMap(id, {
    'id': id,
    'storeId': 'loja',
    'resellerId': 'maria',
    'resellerSnapshot': {'resellerId': 'maria', 'displayName': 'Maria'},
    'status': status,
    'lines': lines,
    'additions': additions ?? [_addition('issue_$id', 'INITIAL', lines)],
    'withdrawals': withdrawals,
    'totalItemsSent': sum('qtySent'),
    'totalItemsSold': sum('qtySold'),
    'totalItemsReturned': sum('qtyReturned'),
    'potentialGrossAmount': sumD('potentialGrossAmount'),
    'grossSoldAmount': sumD('lineGrossAmount'),
    'commissionAmount': sumD('lineCommissionAmount'),
    'netAmount': sumD('lineNetAmount'),
    'revision': 3,
    'issuedAt': DateTime(2026, 10, 1, 10),
    'createdAt': DateTime(2026, 10, 1, 9),
    if (status == 'SETTLED') 'settledAt': DateTime(2026, 10, 10, 18),
  });
}

/// 77 pieces, one per product, as in the reported real consignment.
ConsignmentDoc _fixtureA() => _doc('cA', 'ISSUED', [for (var i = 1; i <= 77; i++) _line(i, 1)]);

ConsignmentDoc _fixtureB() =>
    _doc('cB', 'SETTLED', [for (var i = 1; i <= 20; i++) _line(i, 1, returned: 1)]);

ConsignmentDoc _fixtureC() => _doc('cC', 'SETTLED', [
      for (var i = 1; i <= 20; i++) _line(i, 2, sold: i.isEven ? 2 : 1, returned: i.isEven ? 0 : 1),
    ]);

ConsignmentDoc _fixtureD() {
  final initial = [for (var i = 1; i <= 30; i++) _line(i, 1)];
  final added = [for (var i = 31; i <= 45; i++) _line(i, 1)];
  return _doc('cD', 'ISSUED', [...initial, ...added], additions: [
    _addition('issue_cD', 'INITIAL', initial),
    _addition('add_cD_1', 'ADDITION', added),
  ]);
}

ConsignmentDoc _fixtureE() {
  final lines = [for (var i = 1; i <= 20; i++) _line(i, 2, withdrawn: i <= 5 ? 1 : 0)];
  return _doc('cE', 'ISSUED', lines, withdrawals: [
    {
      'withdrawalId': 'consignment_return_cE_x',
      'kind': 'WITHDRAWAL',
      'reason': 'MERCHANT_RETRIEVAL_BEFORE_SETTLEMENT',
      'createdAt': DateTime(2026, 10, 5, 15),
      'createdBy': 'owner',
      'lines': [for (final l in lines.take(5)) {...l, 'qtyWithdrawn': 1}],
    },
  ]);
}

final _verboseShipment = RegExp(r'=\d+ ·');

int _verboseCount(ConsignmentPdfText pdf) =>
    'ENTREGAS'.allMatches(pdf.text).length +
    'Envio inicial'.allMatches(pdf.text).length +
    _verboseShipment.allMatches(pdf.text).length;

Future<ConsignmentPdfText> _order(ConsignmentDoc d) async => ConsignmentPdfText.parse(
      await ConsignmentReportPdfBuilder.buildOrderPdf(
        store: _store,
        doc: d,
        lines: ConsignmentReportAggregator.linesOf(d),
      ),
    );

Future<ConsignmentPdfText> _settlement(ConsignmentDoc d) async => ConsignmentPdfText.parse(
      await ConsignmentReportPdfBuilder.buildSettlementPdf(
        store: _store,
        doc: d,
        lines: ConsignmentReportAggregator.linesOf(d),
      ),
    );

Future<ConsignmentPdfText> _combined(List<ConsignmentDoc> docs) async => ConsignmentPdfText.parse(
      await ConsignmentReportPdfBuilder.buildCombinedPdf(
        store: _store,
        sections: [
          for (final d in ConsignmentCombinedReportPlanner.order(docs))
            ConsignmentCombinedSection(doc: d, lines: ConsignmentReportAggregator.linesOf(d)),
        ],
        generatedAt: DateTime(2026, 10, 15, 10),
      ),
    );

void _report(String fixture, ConsignmentPdfText pdf) {
  // ignore: avoid_print
  print('PDF_FIXTURE=$fixture PAGES=${pdf.pageCount} VERBOSE=${_verboseCount(pdf)}');
}

void _expectProducts(ConsignmentPdfText pdf, Iterable<int> ids) {
  for (final i in ids) {
    expect(pdf.text, contains(_name(i)), reason: 'item table lost ${_name(i)}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('A. 77-piece open consignation: table, totals and signatures kept; no delivery dump', () async {
    final pdf = await _order(_fixtureA());
    _report('A', pdf);
    expect(_verboseCount(pdf), 0);
    _expectProducts(pdf, [for (var i = 1; i <= 77; i++) i]);
    for (var i = 1; i <= 77; i++) {
      expect(pdf.count(_name(i)), 1, reason: 'product only in the item table');
    }
    expect(pdf.text, contains('Revendedor: Maria'));
    expect(pdf.text, contains('Nº cA'));
    expect(pdf.text, contains('TOTAL DE PEÇAS: 77'));
    expect(pdf.text, contains('Responsável pela loja'));
  });

  test('B. settled total return: order and settlement PDFs', () async {
    final d = _fixtureB();
    final order = await _order(d);
    final settle = await _settlement(d);
    _report('B-order', order);
    _report('B-settlement', settle);
    expect(_verboseCount(order), 0);
    expect(_verboseCount(settle), 0);
    _expectProducts(order, [for (var i = 1; i <= 20; i++) i]);
    _expectProducts(settle, [for (var i = 1; i <= 20; i++) i]);
    expect(settle.text, contains('RESUMO DO ACERTO'));
    expect(settle.text, contains('Peças vendidas: 0'));
    expect(settle.text, contains('Peças devolvidas: 20'));
  });

  test('C. settled with sales: settlement summary kept', () async {
    final d = _fixtureC();
    final order = await _order(d);
    final settle = await _settlement(d);
    _report('C-order', order);
    _report('C-settlement', settle);
    expect(_verboseCount(order), 0);
    expect(_verboseCount(settle), 0);
    expect(settle.text, contains('Peças vendidas: 30'));
    expect(settle.text, contains('STATUS DO ACERTO: PAGO'));
    _expectProducts(settle, [for (var i = 1; i <= 20; i++) i]);
  });

  test('D. additions: every piece in the table; addition receipt still lists its items', () async {
    final d = _fixtureD();
    final order = await _order(d);
    _report('D-order', order);
    expect(_verboseCount(order), 0);
    _expectProducts(order, [for (var i = 1; i <= 45; i++) i]);
    expect(order.text, contains('TOTAL DE PEÇAS: 45'));
    final added = ConsignmentReportAggregator.linesOf(d)
        .where((l) => int.parse(l.productId.substring(1)) >= 31)
        .toList();
    final receipt = ConsignmentPdfText.parse(await ConsignmentReportPdfBuilder.buildAdditionPdf(
      store: _store,
      doc: d,
      additionId: 'add_cD_1',
      lines: added,
      createdAt: DateTime(2026, 10, 2, 10),
    ));
    _report('D-addition', receipt);
    expect(receipt.text, contains('VALOR DESTE ACR'));
    expect(receipt.text, contains(_name(31)));
  });

  test('E. withdrawals section kept', () async {
    final pdf = await _order(_fixtureE());
    _report('E', pdf);
    expect(_verboseCount(pdf), 0);
    expect(pdf.text, contains('RETIRADAS ANTES DO ACERTO'));
    expect(pdf.text, contains('TOTAL RETIRADO: 5 peças'));
    _expectProducts(pdf, [for (var i = 1; i <= 20; i++) i]);
  });

  test('F. combined 3 consignations: sections keep item tables, no delivery dump', () async {
    final pdf = await _combined([_fixtureA(), _fixtureC(), _fixtureD()]);
    _report('F', pdf);
    expect(_verboseCount(pdf), 0);
    expect(pdf.text, contains('CONSIGNAÇÃO 1 DE 3'));
    expect(pdf.text, contains('CONSIGNAÇÃO 3 DE 3'));
    expect(pdf.text, contains('RESUMO GERAL'));
    expect(pdf.text, contains('RESUMO DO ACERTO'));
    _expectProducts(pdf, [for (var i = 1; i <= 77; i++) i]);
    expect(pdf.count(_name(1)), 3, reason: 'one table row per section, no history dump');
  });
}
