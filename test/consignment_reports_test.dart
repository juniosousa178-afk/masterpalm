import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_models.dart';
import 'package:master_palm/features/consignments/consignment_validation.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_data.dart';

ConsignmentDoc _doc({
  required String id,
  required String storeId,
  required String resellerId,
  required String resellerName,
  required String status,
  required List<Map<String, dynamic>> lines,
  DateTime? issuedAt,
  DateTime? settledAt,
  double? gross,
  double? commission,
  double? net,
  double? potential,
}) {
  final sent = lines.fold<int>(0, (s, l) => s + ((l['qtySent'] as num?)?.toInt() ?? 0));
  final sold = lines.fold<int>(0, (s, l) => s + ((l['qtySold'] as num?)?.toInt() ?? 0));
  final returned = lines.fold<int>(0, (s, l) => s + ((l['qtyReturned'] as num?)?.toInt() ?? 0));
  return ConsignmentDoc(
    id: id,
    storeId: storeId,
    resellerId: resellerId,
    resellerName: resellerName,
    status: status,
    lines: lines,
    totalItemsSent: sent,
    totalItemsSold: sold,
    totalItemsReturned: returned,
    grossSoldAmount: gross ?? 0,
    commissionAmount: commission ?? 0,
    netAmount: net ?? 0,
    potentialGrossAmount: potential ?? 0,
    issuedAt: issuedAt,
    settledAt: settledAt,
    createdAt: issuedAt,
  );
}

Map<String, dynamic> _line({
  required String productId,
  required String name,
  required int qtySent,
  int qtySold = 0,
  int qtyReturned = 0,
  double unit = 100,
  String commissionType = 'PERCENTUAL',
  double commissionValue = 20,
  Map<String, dynamic>? variationKey,
  double? lineGross,
  double? lineCommission,
  double? lineNet,
}) {
  final amounts = consignmentLineAmounts(
    qty: qtySold,
    unitPrice: unit,
    commissionType: commissionType,
    commissionValue: commissionValue,
  );
  return {
    'productId': productId,
    'productNameSnapshot': name,
    'qtySent': qtySent,
    'qtySold': qtySold,
    'qtyReturned': qtyReturned,
    'unitSalePriceSnapshot': unit,
    'commissionType': commissionType,
    'commissionValueSnapshot': commissionValue,
    'variationKey': variationKey ?? {'size': '', 'color': '', 'extra': ''},
    'lineGrossAmount': lineGross ?? amounts.gross,
    'lineCommissionAmount': lineCommission ?? amounts.commission,
    'lineNetAmount': lineNet ?? amounts.net,
    'potentialGrossAmount': qtySent * unit,
  };
}

void main() {
  group('order report', () {
    test('1 single product totals', () {
      final doc = _doc(
        id: 'c1',
        storeId: 'mirjoias',
        resellerId: 'r1',
        resellerName: 'Maria',
        status: 'ISSUED',
        lines: [_line(productId: 'p1', name: 'Anel', qtySent: 2, unit: 50)],
        potential: 100,
        issuedAt: DateTime(2026, 9, 20),
      );
      final lines = ConsignmentReportAggregator.linesOf(doc);
      expect(lines, hasLength(1));
      expect(lines.single.lineConsignedValue, 100);
      expect(lines.single.qtySent, 2);
    });

    test('2 fifty-plus products', () {
      final lines = [
        for (var i = 0; i < 55; i++)
          _line(productId: 'p$i', name: 'Produto $i', qtySent: 1, unit: 10),
      ];
      final doc = _doc(
        id: 'big',
        storeId: 'mirjoias',
        resellerId: 'r1',
        resellerName: 'Maria',
        status: 'ISSUED',
        lines: lines,
        potential: 550,
        issuedAt: DateTime(2026, 9, 1),
      );
      final views = ConsignmentReportAggregator.linesOf(doc);
      expect(views, hasLength(55));
      expect(views.fold<double>(0, (s, l) => s + l.lineConsignedValue), 550);
    });

    test('3-5 simple, variation, no photo meta', () {
      final doc = _doc(
        id: 'c2',
        storeId: 'mirjoias',
        resellerId: 'r1',
        resellerName: 'Maria',
        status: 'ISSUED',
        lines: [
          _line(productId: 'simple', name: 'Simples', qtySent: 1),
          _line(
            productId: 'var',
            name: 'Anel Solitário',
            qtySent: 1,
            variationKey: {'size': '17', 'color': '', 'extra': ''},
          ),
        ],
        issuedAt: DateTime(2026, 9, 20),
      );
      final views = ConsignmentReportAggregator.linesOf(
        doc,
        meta: {
          'simple': const ConsignmentProductReportMeta(productCode: 'AN01'),
          'var': const ConsignmentProductReportMeta(productCode: 'AN59'),
        },
      );
      expect(views[0].productCode, 'AN01');
      expect(views[0].imageUrl, isEmpty);
      expect(views[1].variationLabel, 'Tamanho: 17');
    });

    test('8 historical unit price not live price', () {
      final doc = _doc(
        id: 'c3',
        storeId: 'mirjoias',
        resellerId: 'r1',
        resellerName: 'Maria',
        status: 'ISSUED',
        lines: [_line(productId: 'p1', name: 'Peça', qtySent: 1, unit: 100)],
        issuedAt: DateTime(2026, 1, 1),
      );
      final views = ConsignmentReportAggregator.linesOf(
        doc,
        meta: const {'p1': ConsignmentProductReportMeta(productCode: 'X')},
      );
      expect(views.single.unitPrice, 100);
      expect(views.single.lineConsignedValue, 100);
    });

    test('9-10 reseller + cross-store isolation', () {
      final mine = _doc(
        id: 'a',
        storeId: 'mirjoias',
        resellerId: 'r1',
        resellerName: 'Maria',
        status: 'ISSUED',
        lines: [_line(productId: 'p', name: 'P', qtySent: 1)],
        issuedAt: DateTime(2026, 9, 15),
      );
      final other = _doc(
        id: 'b',
        storeId: 'nathy',
        resellerId: 'r9',
        resellerName: 'Outra',
        status: 'ISSUED',
        lines: [_line(productId: 'p', name: 'P', qtySent: 9)],
        issuedAt: DateTime(2026, 9, 15),
      );
      final range = ConsignmentReportDateRange(
        DateTime(2026, 9, 1),
        DateTime(2026, 10, 1),
      );
      expect(
        ConsignmentReportAggregator.matchesFilters(
          doc: mine,
          lojaId: 'mirjoias',
          range: range,
        ),
        isTrue,
      );
      expect(
        ConsignmentReportAggregator.matchesFilters(
          doc: other,
          lojaId: 'mirjoias',
          range: range,
        ),
        isFalse,
      );
      expect(
        ConsignmentReportAggregator.matchesFilters(
          doc: mine,
          lojaId: 'mirjoias',
          resellerId: 'r2',
          range: range,
        ),
        isFalse,
      );
    });
  });

  group('settlement report', () {
    test('11-16 sold returned pending commission', () {
      final doc = _doc(
        id: 's1',
        storeId: 'mirjoias',
        resellerId: 'r1',
        resellerName: 'Maria',
        status: 'SETTLED',
        lines: [
          _line(productId: 'p1', name: 'A', qtySent: 10, qtySold: 7, qtyReturned: 3, unit: 100),
        ],
        gross: 700,
        commission: 140,
        net: 560,
        settledAt: DateTime(2026, 9, 30),
        issuedAt: DateTime(2026, 9, 1),
      );
      final lines = ConsignmentReportAggregator.linesOf(doc);
      expect(lines.single.qtySold, 7);
      expect(lines.single.qtyReturned, 3);
      expect(lines.single.qtyPending, 0);
      expect(lines.single.lineGrossSold, 700);
      expect(lines.single.lineCommission, 140);
      expect(lines.single.lineNet, 560);
    });

    test('15 pending while issued', () {
      final doc = _doc(
        id: 's2',
        storeId: 'mirjoias',
        resellerId: 'r1',
        resellerName: 'Maria',
        status: 'ISSUED',
        lines: [_line(productId: 'p1', name: 'A', qtySent: 5)],
        issuedAt: DateTime(2026, 9, 1),
      );
      expect(ConsignmentReportAggregator.linesOf(doc).single.qtyPending, 5);
    });

    test('17-19 settled payment model is full paid', () {
      expect(consignmentReportCommissionLabel('PERCENTUAL', 20), contains('20%'));
      final amounts = consignmentLineAmounts(
        qty: 10,
        unitPrice: 185,
        commissionType: 'PERCENTUAL',
        commissionValue: 20,
      );
      expect(amounts.gross, 1850);
      expect(amounts.commission, 370);
      expect(amounts.net, 1480);
    });
  });

  group('general report', () {
    test('21-26 multi reseller totals match row sum', () {
      final docs = [
        _doc(
          id: '1',
          storeId: 'mirjoias',
          resellerId: 'r1',
          resellerName: 'Maria',
          status: 'SETTLED',
          lines: [_line(productId: 'a', name: 'A', qtySent: 2, qtySold: 2, unit: 50)],
          gross: 100,
          commission: 20,
          net: 80,
          potential: 100,
          issuedAt: DateTime(2026, 9, 5),
          settledAt: DateTime(2026, 9, 10),
        ),
        _doc(
          id: '2',
          storeId: 'mirjoias',
          resellerId: 'r2',
          resellerName: 'Ana',
          status: 'ISSUED',
          lines: [_line(productId: 'b', name: 'B', qtySent: 3, unit: 40)],
          potential: 120,
          issuedAt: DateTime(2026, 9, 8),
        ),
      ];
      final by = <String, List<ConsignmentDoc>>{};
      for (final d in docs) {
        by.putIfAbsent(d.resellerId, () => []).add(d);
      }
      final rows = by.entries.map((e) {
        final roll = ConsignmentReportAggregator.resellerRollup(e.value);
        return {...roll, 'name': e.value.first.resellerName};
      }).toList();
      final totals = ConsignmentReportAggregator.generalTotals(rows);
      expect(totals['sent'], rows.fold<int>(0, (s, r) => s + (r['sent'] as int)));
      expect(totals['sold'], rows.fold<int>(0, (s, r) => s + (r['sold'] as int)));
      expect(totals['gross'], rows.fold<double>(0, (s, r) => s + (r['gross'] as double)));
      expect(totals['commission'], rows.fold<double>(0, (s, r) => s + (r['commission'] as double)));
      expect(totals['net'], rows.fold<double>(0, (s, r) => s + (r['net'] as double)));
    });

    test('22-23 period and status filters', () {
      final doc = _doc(
        id: '1',
        storeId: 'mirjoias',
        resellerId: 'r1',
        resellerName: 'Maria',
        status: 'SETTLED',
        lines: [_line(productId: 'a', name: 'A', qtySent: 1, qtySold: 1)],
        issuedAt: DateTime(2026, 8, 15),
        settledAt: DateTime(2026, 8, 20),
      );
      final september = ConsignmentReportDateRange(DateTime(2026, 9, 1), DateTime(2026, 10, 1));
      expect(
        ConsignmentReportAggregator.matchesFilters(
          doc: doc,
          lojaId: 'mirjoias',
          range: september,
        ),
        isFalse,
      );
      expect(
        ConsignmentReportAggregator.matchesFilters(
          doc: doc,
          lojaId: 'mirjoias',
          status: 'ISSUED',
          range: ConsignmentReportDateRange(DateTime(2026, 8, 1), DateTime(2026, 9, 1)),
        ),
        isFalse,
      );
      expect(
        ConsignmentReportAggregator.matchesFilters(
          doc: doc,
          lojaId: 'mirjoias',
          status: 'SETTLED',
          range: ConsignmentReportDateRange(DateTime(2026, 8, 1), DateTime(2026, 9, 1)),
        ),
        isTrue,
      );
    });

    test('27 empty list totals zero', () {
      final totals = ConsignmentReportAggregator.generalTotals(const []);
      expect(totals['sent'], 0);
      expect(totals['gross'], 0);
    });

    test('28 cross store leak zero', () {
      final foreign = _doc(
        id: 'x',
        storeId: 'nathy',
        resellerId: 'r',
        resellerName: 'X',
        status: 'ISSUED',
        lines: [_line(productId: 'p', name: 'P', qtySent: 1)],
        issuedAt: DateTime(2026, 9, 1),
      );
      expect(
        ConsignmentReportAggregator.matchesFilters(
          doc: foreign,
          lojaId: 'mirjoias',
          range: ConsignmentReportDateRange(DateTime(2026, 9, 1), DateTime(2026, 10, 1)),
        ),
        isFalse,
      );
    });
  });

  test('file name sanitization', () {
    final doc = _doc(
      id: 'c',
      storeId: 'mirjoias',
      resellerId: 'r',
      resellerName: 'Maria Silva/Teste?',
      status: 'ISSUED',
      lines: [_line(productId: 'p', name: 'P', qtySent: 1)],
      issuedAt: DateTime(2026, 9, 20),
    );
    final name = ConsignmentReportDataService.orderFileName(doc, now: DateTime(2026, 9, 20));
    expect(name, isNot(contains('/')));
    expect(name, isNot(contains('?')));
    expect(name, startsWith('Pedido_Consignacao_'));
    expect(name, endsWith('.pdf'));
  });

  test('period presets', () {
    final now = DateTime(2026, 9, 20, 15);
    final today = ConsignmentReportDateRange.fromPreset(
      ConsignmentReportPeriodPreset.today,
      now: now,
    );
    expect(today.start, DateTime(2026, 9, 20));
    expect(today.end, DateTime(2026, 9, 21));
    final month = ConsignmentReportDateRange.fromPreset(
      ConsignmentReportPeriodPreset.thisMonth,
      now: now,
    );
    expect(month.start, DateTime(2026, 9, 1));
    expect(month.end, DateTime(2026, 10, 1));
  });
}
