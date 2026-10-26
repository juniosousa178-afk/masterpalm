import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_draft.dart';
import 'package:master_palm/features/consignments/consignment_eligibility.dart';
import 'package:master_palm/features/consignments/consignment_models.dart';
import 'package:master_palm/features/consignments/consignment_product_picker.dart';
import 'package:master_palm/features/consignments/consignment_service.dart';
import 'package:master_palm/features/consignments/consignment_ui.dart';
import 'package:master_palm/features/consignments/consignment_validation.dart';
import 'package:master_palm/features/consignments/consignment_variation_price.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_data.dart';
import 'package:master_palm/features/consignments/reports/consignment_report_pdf.dart';
import 'package:master_palm/features/consignments/screens/consignment_form_screen.dart';

import 'support/consignment_pdf_text.dart';

const _store = ConsignmentStoreProfile(lojaId: 'loja', name: 'Loja Teste');
const _prices = <String, double?>{'15': 25.90, '16': 27.90, '17': 30.90};

ConsignmentPickerItem _anel({
  Map<String, double?>? sizePrices = _prices,
  bool loaded = true,
  double price = 25.90,
}) =>
    ConsignmentPickerItem(
      productId: 'anel',
      name: 'Anel',
      price: price,
      availableQty: 9,
      stockKind: 'variation',
      variacoes: const {
        '15': {'sem-cor': 3},
        '16': {'sem-cor': 3},
        '17': {'sem-cor': 3},
      },
      eligible: true,
      stockRevision: 4,
      sizePrices: sizePrices,
      sizePricesLoaded: loaded,
    );

ConsignmentVariationKey _size(String s) => ConsignmentVariationKey(size: s, color: 'sem-cor');

ConsignmentDraftLine _pick(ConsignmentPickerItem item, String size) =>
    consignmentDraftLineFor(item: item, variation: _size(size))!;

/// Firestore line exactly as the server persists it (snapshot only, no product read).
Map<String, dynamic> _issuedLine(String size, double price, {int qty = 1, int sold = 0, int returned = 0, int withdrawn = 0, String? lot}) {
  final vk = {'size': size, 'color': 'sem-cor', 'extra': ''};
  return {
    'lineId': 'anel::$size${lot == null ? '' : '::$lot'}',
    'productId': 'anel',
    'productNameSnapshot': 'Anel',
    'productType': 'variation',
    'variationKey': vk,
    'qtySent': qty,
    'qtySold': sold,
    'qtyReturned': returned,
    if (withdrawn > 0) 'qtyWithdrawn': withdrawn,
    'unitSalePriceSnapshot': price,
    'commissionType': 'SEM_COMISSAO',
    'commissionValueSnapshot': 0,
    'potentialGrossAmount': (qty * price * 100).round() / 100,
    'lineGrossAmount': (sold * price * 100).round() / 100,
    'lineCommissionAmount': 0,
    'lineNetAmount': (sold * price * 100).round() / 100,
    if (lot != null) 'additionId': lot,
  };
}

ConsignmentDoc _doc(String status, List<Map<String, dynamic>> lines, {double gross = 0}) {
  final potential = lines.fold<int>(0, (s, l) => s + ((l['potentialGrossAmount'] as num) * 100).round()) / 100;
  return ConsignmentDoc.fromMap('c1', {
    'id': 'c1',
    'storeId': 'loja',
    'resellerId': 'maria',
    'resellerSnapshot': {'resellerId': 'maria', 'displayName': 'Maria'},
    'status': status,
    'lines': lines,
    'totalItemsSent': lines.fold<int>(0, (s, l) => s + (l['qtySent'] as int)),
    'totalItemsSold': lines.fold<int>(0, (s, l) => s + (l['qtySold'] as int)),
    'totalItemsReturned': lines.fold<int>(0, (s, l) => s + (l['qtyReturned'] as int)),
    'potentialGrossAmount': potential,
    'grossSoldAmount': gross,
    'commissionAmount': 0,
    'netAmount': gross,
    'revision': 2,
    'issuedAt': DateTime(2026, 10, 1, 10),
    'createdAt': DateTime(2026, 10, 1, 9),
    if (status == 'SETTLED') 'settledAt': DateTime(2026, 10, 2, 10),
    if (status == 'SETTLED') 'settlementOperationId': 'settle_c1',
  });
}

void main() {
  group('price resolution', () {
    test('1 product without variation keeps its normal price', () {
      final simple = ConsignmentPickerItem(
        productId: 'brinco', name: 'Brinco', price: 49.90, availableQty: 2,
        stockKind: 'simple', variacoes: const {}, eligible: true, stockRevision: 1,
      );
      final line = consignmentDraftLineFor(item: simple, variation: const ConsignmentVariationKey())!;
      expect(line.unitSalePrice, 49.90);
      expect(line.toPayload().containsKey('variationKey'), isFalse);
    });

    test('2 + 19 Anel 15/16/17 = 25,90 + 27,90 + 30,90 = 84,70', () {
      final lines = <ConsignmentDraftLine>[];
      for (final s in ['15', '16', '17']) {
        ConsignmentDraftMutator.addOrMerge(lines, _pick(_anel(), s));
      }
      expect(lines.map((l) => l.unitSalePrice), [25.90, 27.90, 30.90]);
      expect(consignmentDraftPotential(lines).gross, 84.70);
      expect(lines.map(consignmentDraftLineTitle), ['Anel — Tam. 15', 'Anel — Tam. 16', 'Anel — Tam. 17']);
      expect(consignmentDraftLineSummary(lines[0]), '1 × ${consignmentMoney.format(25.90)} = ${consignmentMoney.format(25.90)}');
      expect(lines.any((l) => consignmentDraftLineSummary(l).startsWith('3 ×')), isFalse);
    });

    test('3 qty > 1 multiplies the same variation price (2 × 30,90 = 61,80)', () {
      final lines = <ConsignmentDraftLine>[];
      ConsignmentDraftMutator.addOrMerge(lines, _pick(_anel(), '17'));
      ConsignmentDraftMutator.addOrMerge(lines, _pick(_anel(), '17'));
      expect(lines.single.qtySent, 2);
      expect(lines.single.lineSubtotal, 61.80);
      expect(consignmentDraftPotential(lines).gross, 61.80);
    });

    test('4 two variations with the same price stay separate lines', () {
      final item = _anel(sizePrices: const {'15': 27.90, '16': 27.90, '17': 30.90});
      final lines = <ConsignmentDraftLine>[];
      ConsignmentDraftMutator.addOrMerge(lines, _pick(item, '15'));
      ConsignmentDraftMutator.addOrMerge(lines, _pick(item, '16'));
      expect(lines.length, 2);
      expect(lines.map((l) => l.variationKey.size), ['15', '16']);
      expect(lines.map((l) => (l.toPayload()['variationKey'] as Map)['size']), ['15', '16']);
    });

    test('14 variation without own price: documented inheritance or fail closed', () {
      ConsignmentDraftLine? line(ConsignmentPickerItem i, String s) =>
          consignmentDraftLineFor(item: i, variation: _size(s));
      expect(line(_anel(sizePrices: const {'15': 25.90}), '16')!.unitSalePrice, 25.90,
          reason: 'size without entry inherits product price (Produto.precoParaVariacao)');
      expect(line(_anel(sizePrices: null), '16')!.unitSalePrice, 25.90, reason: 'no table at all');
      expect(line(_anel(sizePrices: const {'15': null}), '15'), isNull, reason: 'invalid stored price');
      expect(line(_anel(sizePrices: const {'15': 25.90}, price: 0), '16'), isNull, reason: 'nothing to inherit');
      expect(line(_anel(loaded: false), '15'), isNull, reason: 'table could not be read');
      expect(line(_anel(sizePrices: const {'p ': 10, ' p': 11}), 'P'), isNull, reason: 'ambiguous');
      expect(line(_anel(sizePrices: const {'Tam 1': 10}), 'tam1')!.unitSalePrice, 10);
      expect(consignmentVariationPriceUnavailableMessage, 'Não foi possível identificar o preço desta variação.');
    });

    test('picker label shows the size price range, never only the minimum', () {
      expect(consignmentPickerPriceLabel(_anel()),
          '${consignmentMoney.format(25.90)} a ${consignmentMoney.format(30.90)}');
    });

    test('manual price edit is kept apart from the variation price', () {
      final line = _pick(_anel(), '16');
      expect(line.hasManualPrice, isFalse);
      line.unitSalePrice = 24.00;
      expect(line.hasManualPrice, isTrue);
      expect(line.listUnitPrice, 27.90);
      expect(line.toPayload()['unitSalePrice'], 24.00);
    });
  });

  group('snapshot after creation', () {
    final issued = _doc('ISSUED', [_issuedLine('15', 25.90), _issuedLine('16', 27.90), _issuedLine('17', 30.90)]);

    test('5 + 6 + 16 product/variation price changes never alter the stored consignment', () {
      expect(issued.potentialGrossAmount, 84.70);
      expect(issued.outstandingGrossAmount, 84.70);
      expect(issued.lines.map(consignmentLineUnitPrice), [25.90, 27.90, 30.90]);
      final legacy = _doc('ISSUED', [for (final s in ['15', '16', '17']) _issuedLine(s, 25.90)]);
      expect(legacy.outstandingGrossAmount, 77.70, reason: 'old records are shown as stored, never recalculated');
    });

    test('details consolidation never merges lots with different prices', () {
      final doc = _doc('ISSUED', [
        _issuedLine('16', 27.90),
        _issuedLine('16', 29.90, lot: 'add_1'),
        _issuedLine('16', 27.90, lot: 'add_2'),
      ]);
      final merged = doc.consolidatedLines;
      expect(merged.length, 2);
      expect(merged.map((l) => [l['qtySent'], consignmentLineUnitPrice(l)]), [
        [2, 27.90],
        [1, 29.90],
      ]);
      expect(merged.map(consignmentLineSentAmount), [55.80, 29.90]);
    });

    test('7 return uses the original line, variation and snapshot price', () {
      final l17 = issued.lines[2];
      final ret = ConsignmentReturnLine(
        lineId: l17['lineId'] as String,
        productId: 'anel',
        variationKey: ConsignmentVariationKey.fromMap(l17['variationKey']),
        qty: 1,
      ).toPayload();
      expect(ret['lineId'], 'anel::17');
      expect((ret['variationKey'] as Map)['size'], '17');
      final after = _doc('ISSUED', [_issuedLine('15', 25.90), _issuedLine('16', 27.90), _issuedLine('17', 30.90, withdrawn: 1)]);
      expect(after.withdrawnGrossAmount, 30.90);
      expect(after.outstandingGrossAmount, 53.80);
    });

    test('8 + 9 settle / sale amounts come from each line snapshot', () {
      final inputs = [
        for (final l in issued.lines)
          ConsignmentSettlementLineInput(line: l, qtySold: (l['variationKey'] as Map)['size'] == '17' ? 0 : 1),
      ];
      final gross = inputs.fold<double>(
        0,
        (s, i) => s + consignmentLineAmounts(
          qty: i.qtySold,
          unitPrice: consignmentLineUnitPrice(i.line),
          commissionType: 'SEM_COMISSAO',
          commissionValue: 0,
        ).gross,
      );
      expect((gross * 100).round(), 5380);
      expect(inputs.map((i) => i.qtyReturned), [0, 0, 1]);
    });

    test('10 PDF lists each variation with its own price and the exact total', () async {
      final pdf = ConsignmentPdfText.parse(await ConsignmentReportPdfBuilder.buildOrderPdf(
        store: _store, doc: issued, lines: ConsignmentReportAggregator.linesOf(issued),
      ));
      for (final s in ['15', '16', '17']) {
        expect(pdf.text, contains('Tamanho: $s'));
      }
      for (final p in ['25,90', '27,90', '30,90', '84,70']) {
        expect(pdf.text, contains(p));
      }
    });

    test('11 report rows and rollups keep per-variation values', () {
      final rows = ConsignmentReportAggregator.linesOf(issued);
      expect(rows.map((r) => r.unitPrice), [25.90, 27.90, 30.90]);
      expect(rows.map((r) => r.variationLabel), ['Tamanho: 15 · Cor: sem-cor', 'Tamanho: 16 · Cor: sem-cor', 'Tamanho: 17 · Cor: sem-cor']);
      final section = ConsignmentCombinedSection(doc: issued, lines: rows);
      expect(section.consignedValue, 84.70);
      expect(ConsignmentReportAggregator.resellerRollup([issued])['consigned'], 84.70);
    });
  });

  testWidgets('21 form shows one line per variation with its own price and the exact total', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ConsignmentService.debugFirestore = FakeFirebaseFirestore();
    addTearDown(() => ConsignmentService.debugFirestore = null);
    await tester.pumpWidget(MaterialApp(
      home: ConsignmentFormScreen(
        lojaId: 'loja',
        debugInitialLines: [for (final s in ['15', '16', '17']) _pick(_anel(), s)],
      ),
    ));
    await tester.pumpAndSettle();
    for (final s in ['15', '16', '17']) {
      expect(find.text('Anel — Tam. $s'), findsOneWidget);
    }
    String money(double v) => consignmentMoney.format(v);
    expect(find.text('1 × ${money(25.90)} = ${money(25.90)}'), findsOneWidget);
    expect(find.text('1 × ${money(27.90)} = ${money(27.90)}'), findsOneWidget);
    expect(find.text('1 × ${money(30.90)} = ${money(30.90)}'), findsOneWidget);
    expect(find.text('Total potencial: ${money(84.70)}'), findsOneWidget);
    expect(find.textContaining('3 × ${money(25.90)}'), findsNothing);
  });

  group('stock, tenant and retry', () {
    test('12 each variation line targets its own stock cell', () {
      final payload = [for (final s in ['15', '16', '17']) _pick(_anel(), s).toPayload()];
      expect(payload.map((p) => (p['variationKey'] as Map)['size']), ['15', '16', '17']);
      expect(payload.every((p) => p['expectedStockRevision'] == 4), isTrue);
      expect(payload.every((p) => p['qtySent'] == 1), isTrue);
    });

    test('13 another store\'s product never supplies prices', () async {
      final denied = evaluateConsignmentPickerItem(
        productId: 'anel',
        lojaId: 'B',
        stock: {'lojaId': 'A', 'stockKind': 'variation', 'stockRevision': 1, 'quantidade': 3, 'variacoes': {'15': {'sem-cor': 3}}},
        draft: {'precoPorTamanho': {'15': 25.90}},
        dependency: {'comboIds': []},
      );
      expect(denied.eligible, isFalse);
      expect(denied.sizePrices, isNull);

      final fake = FakeFirebaseFirestore();
      await fake.doc('lojas/B/draft_produtos/anel').set({'lojaId': 'A', 'precoPorTamanho': {'15': 99}});
      await fake.doc('lojas/B/estoque_produtos/anel').set({'lojaId': 'A'});
      ConsignmentService.debugFirestore = fake;
      addTearDown(() => ConsignmentService.debugFirestore = null);
      final out = await ConsignmentService.enrichPickerSizePrices('B', [_anel(sizePrices: null, loaded: false)]);
      expect(out.single.sizePricesLoaded, isFalse);
      expect(consignmentDraftLineFor(item: out.single, variation: _size('15')), isNull);
    });

    test('older server response: prices read from this store only', () async {
      final fake = FakeFirebaseFirestore();
      await fake.doc('lojas/A/draft_produtos/anel').set({'lojaId': 'A', 'preco': 25.90, 'precoPorTamanho': {'15': 25.90, '16': 27.90, '17': 30.90}});
      await fake.doc('lojas/A/estoque_produtos/anel').set({'lojaId': 'A'});
      ConsignmentService.debugFirestore = fake;
      addTearDown(() => ConsignmentService.debugFirestore = null);
      final out = await ConsignmentService.enrichPickerSizePrices('A', [_anel(sizePrices: null, loaded: false)]);
      expect(out.single.sizePricesLoaded, isTrue);
      expect([for (final s in ['15', '16', '17']) _pick(out.single, s).unitSalePrice], [25.90, 27.90, 30.90]);
    });

    test('15 retry resends the identical payload (no client-only keys)', () async {
      final calls = <Map<String, dynamic>>[];
      ConsignmentService.debugTransport = (name, data) async {
        calls.add(data);
        return {'ok': true};
      };
      addTearDown(() => ConsignmentService.debugTransport = null);
      final lines = [for (final s in ['15', '16', '17']) _pick(_anel(), s)];
      for (var i = 0; i < 2; i++) {
        await ConsignmentService.createDraft(lojaId: 'A', consignmentId: 'c1', resellerId: 'maria', lines: lines);
      }
      expect(calls[0], calls[1]);
      expect(calls[0]['operationId'], 'draft_c1');
      final sent = (calls[0]['payload'] as Map)['lines'] as List;
      expect(sent.map((l) => (l as Map)['unitSalePrice']), [25.90, 27.90, 30.90]);
      expect(sent.every((l) => !(l as Map).containsKey('listUnitPrice')), isTrue);
    });
  });
}
