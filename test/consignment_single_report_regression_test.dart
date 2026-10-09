import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_models.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_data.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_pdf.dart';

import 'support/consignment_pdf_text.dart';

/// Text and page count of the single consignment reports must stay exactly as released
/// (golden captured from 1.0.130+144). Regenerate only for intentional layout changes:
/// UPDATE_SINGLE_REPORT_GOLDEN=1 flutter test test/consignment_single_report_regression_test.dart
const _golden = 'test/goldens/consignment_single_report_text.json';

const _store = ConsignmentStoreProfile(
  lojaId: 'mirjoias',
  name: 'Loja Teste',
  cnpj: '00.000.000/0001-00',
  phone: '1100000000',
  whatsapp: '1100000001',
  instagram: '@lojateste',
  address: 'Rua Teste, 1',
  logoUrl: '',
);

const _reseller = ConsignmentReseller(resellerId: 'r1', displayName: 'Maria', phone: '1100000002');

Map<String, dynamic> _line(String id, String name, int qty, {int sold = 0, int returned = 0, Map<String, dynamic>? variation}) => {
      'productId': id,
      'productNameSnapshot': name,
      'qtySent': qty,
      'qtySold': sold,
      'qtyReturned': returned,
      'unitSalePriceSnapshot': 100,
      'commissionType': 'PERCENTUAL',
      'commissionValueSnapshot': 20,
      'variationKey': variation ?? {'size': '', 'color': '', 'extra': ''},
      'lineGrossAmount': sold * 100.0,
      'lineCommissionAmount': sold * 20.0,
      'lineNetAmount': sold * 80.0,
      'potentialGrossAmount': qty * 100.0,
    };

ConsignmentDoc _doc(String status) {
  final lines = [
    _line('p1', 'Anel Solitario', 10, sold: status == 'SETTLED' ? 7 : 0, returned: status == 'SETTLED' ? 3 : 0),
    _line('p2', 'Brinco Gota', 5, variation: {'size': '17', 'color': 'Dourado', 'extra': ''}),
  ];
  return ConsignmentDoc(
    id: 'cons-$status',
    storeId: 'mirjoias',
    resellerId: 'r1',
    resellerName: 'Maria',
    status: status,
    lines: lines,
    additions: [
      {'additionId': 'init', 'kind': 'INITIAL', 'lines': [{'productNameSnapshot': 'Anel Solitario', 'qtySent': 10}]},
      {'additionId': 'add1', 'kind': 'ADDITION', 'lines': [{'productNameSnapshot': 'Brinco Gota', 'qtyAdded': 5}]},
    ],
    totalItemsSent: 15,
    totalItemsSold: status == 'SETTLED' ? 7 : 0,
    totalItemsReturned: status == 'SETTLED' ? 3 : 0,
    grossSoldAmount: status == 'SETTLED' ? 700 : 0,
    commissionAmount: status == 'SETTLED' ? 140 : 0,
    netAmount: status == 'SETTLED' ? 560 : 0,
    potentialGrossAmount: 1500,
    notes: 'Entrega na loja',
    issuedAt: DateTime(2026, 9, 1, 9, 15),
    createdAt: DateTime(2026, 9, 1, 9),
    settledAt: status == 'SETTLED' ? DateTime(2026, 9, 30, 18) : null,
  );
}

const _meta = {
  'p1': ConsignmentProductReportMeta(productCode: 'AN32SM'),
  'p2': ConsignmentProductReportMeta(productCode: 'BR10'),
};

Map<String, Object> _summary(ConsignmentPdfText pdf) => {
      'pages': pdf.pageCount,
      'text': pdf.text.replaceAll(RegExp(r'MasterPalm · \S+ \S+ ·'), 'MasterPalm · <now> ·'),
    };

void main() {
  test('single order, settlement and addition reports are unchanged', () async {
    final out = <String, Object>{};
    for (final status in ['DRAFT', 'ISSUED', 'SETTLED']) {
      final doc = _doc(status);
      final lines = ConsignmentReportAggregator.linesOf(doc, meta: _meta);
      out['order_$status'] = _summary(ConsignmentPdfText.parse(
        await ConsignmentReportPdfBuilder.buildOrderPdf(store: _store, doc: doc, lines: lines, reseller: _reseller),
      ));
      if (status == 'SETTLED') {
        out['settlement_$status'] = _summary(ConsignmentPdfText.parse(
          await ConsignmentReportPdfBuilder.buildSettlementPdf(store: _store, doc: doc, lines: lines, reseller: _reseller),
        ));
      }
    }
    final issued = _doc('ISSUED');
    out['addition_ISSUED'] = _summary(ConsignmentPdfText.parse(
      await ConsignmentReportPdfBuilder.buildAdditionPdf(
        store: _store,
        doc: issued,
        additionId: 'add1',
        lines: ConsignmentReportAggregator.additionLinesOf(
          [_line('p2', 'Brinco Gota', 5)],
          meta: _meta,
        ),
        reseller: _reseller,
        createdAt: DateTime(2026, 9, 10, 14),
      ),
    ));
    final json = const JsonEncoder.withIndent('  ').convert(out);
    final file = File(_golden);
    if (Platform.environment['UPDATE_SINGLE_REPORT_GOLDEN'] == '1') {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$json\n');
    }
    expect(json, file.readAsStringSync().trimRight());
    expect(json, contains('RELATÓRIO DE CONSIGNAÇÃO / PEDIDO'));
    expect(json, contains('RESUMO DO ACERTO'));
    expect(json, isNot(contains('CONSOLIDADO')));
  });
}
