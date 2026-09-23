import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_eligibility.dart';
import 'package:master_palm/features/consignments/consignment_product_picker.dart';
import 'package:master_palm/features/consignments/consignment_service.dart';
import 'package:master_palm/features/consignments/screens/consignment_form_screen.dart';

ConsignmentPickerItem _item({
  required String id,
  required String name,
  String productCode = '',
  int qty = 1,
  bool eligible = true,
  String stockKind = 'simple',
  Map<String, dynamic> variacoes = const {},
  String unavailableReason = '',
}) {
  return ConsignmentPickerItem(
    productId: id,
    name: name,
    productCode: productCode,
    price: 10,
    availableQty: qty,
    stockKind: stockKind,
    variacoes: variacoes,
    eligible: eligible,
    unavailableReason: unavailableReason.isEmpty
        ? (eligible ? '' : consignmentProductUnavailableReason)
        : unavailableReason,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fake;

  setUp(() {
    fake = FakeFirebaseFirestore();
    ConsignmentService.debugFirestore = fake;
    ConsignmentService.debugPickerItems = null;
    ConsignmentService.debugTransport = null;
  });

  tearDown(() {
    ConsignmentService.debugPickerItems = null;
    ConsignmentService.debugTransport = null;
    ConsignmentService.debugFirestore = null;
  });

  group('consignmentPickerVisibleItems listing', () {
    test('1 loads all eligible products above former pageSize 80', () {
      final all = List.generate(
        120,
        (i) => _item(
          id: 'p$i',
          name: 'Produto ${i.toString().padLeft(3, '0')}',
          productCode: 'C${i.toString().padLeft(3, '0')}',
        ),
      );
      final visible = consignmentPickerVisibleItems(all);
      expect(visible, hasLength(120));
      expect(visible.map((e) => e.productId).contains('p119'), isTrue);
    });

    test('1b empty query hides zero-stock / blockers', () {
      final all = [
        _item(id: 'ok', name: 'Ok'),
        _item(id: 'z', name: 'Zerado', eligible: false, unavailableReason: '0 disponíveis para consignação'),
        _item(id: 'b', name: 'Bloqueado', eligible: false),
      ];
      expect(consignmentPickerVisibleItems(all).map((e) => e.productId), ['ok']);
    });

    test('2 ZERO_STOCK not addable but searchable', () {
      final zero = _item(
        id: 'z',
        name: 'Zerado',
        qty: 0,
        eligible: false,
        unavailableReason: '0 disponíveis para consignação',
      );
      final visible = consignmentPickerVisibleItems([zero], query: 'Zerado');
      expect(visible.single.eligible, isFalse);
      expect(visible.single.unavailableReason, '0 disponíveis para consignação');
    });

    test('3 real blocker not addable', () {
      final blocked = _item(
        id: 'b',
        name: 'Bloqueado',
        eligible: false,
      );
      expect(
        consignmentPickerVisibleItems([blocked], query: 'Bloqueado').single.eligible,
        isFalse,
      );
    });
  });

  group('name search', () {
    final catalog = [
      _item(id: 'a', name: 'Solitário Cravejado Prata 925', productCode: 'AN59PR'),
      _item(id: 'b', name: 'Colar Nylon Coração Cristal', productCode: 'CL01PR'),
      _item(
        id: 'c',
        name: 'Anel Simples',
        productCode: 'AN05PR',
        eligible: false,
        unavailableReason: '0 disponíveis para consignação',
      ),
    ];

    test('4 full name', () {
      final v = consignmentPickerVisibleItems(catalog, query: 'Solitário Cravejado Prata 925');
      expect(v.map((e) => e.productId), ['a']);
    });

    test('5 partial name', () {
      final v = consignmentPickerVisibleItems(catalog, query: 'nylon');
      expect(v.map((e) => e.productId), ['b']);
    });

    test('6 case insensitive', () {
      final v = consignmentPickerVisibleItems(catalog, query: 'SOLITÁRIO CRAVEJADO');
      expect(v.map((e) => e.productId), ['a']);
    });

    test('7 accents', () {
      final v = consignmentPickerVisibleItems(catalog, query: 'solitario cravejado');
      expect(v.map((e) => e.productId), ['a']);
    });
  });

  group('code search', () {
    final catalog = [
      _item(id: 'a', name: 'Anel A', productCode: 'AN05PR'),
      _item(id: 'b', name: 'Anel B', productCode: '00125'),
      _item(id: 'c', name: 'Anel C', productCode: 'AN32SM'),
      _item(id: 'd', name: 'Anel D', productCode: 'AN32SM'),
    ];

    test('8 exact code', () {
      final v = consignmentPickerVisibleItems(catalog, query: 'AN05PR');
      expect(v.first.productId, 'a');
      expect(v.first.productCode, 'AN05PR');
    });

    test('9 alphanumeric case insensitive', () {
      final v = consignmentPickerVisibleItems(catalog, query: 'an05pr');
      expect(v.map((e) => e.productId), ['a']);
    });

    test('10 leading zeros preserved', () {
      final v = consignmentPickerVisibleItems(catalog, query: '00125');
      expect(v.single.productId, 'b');
      expect(v.single.productCode, '00125');
      expect(
        consignmentPickerVisibleItems(catalog, query: '125').map((e) => e.productId),
        isNot(contains('b')),
      );
    });

    test('11 missing code yields empty', () {
      expect(consignmentPickerVisibleItems(catalog, query: 'ZZ99XX'), isEmpty);
    });

    test('12 duplicate codes surface all matches safely', () {
      final v = consignmentPickerVisibleItems(catalog, query: 'AN32SM');
      expect(v.map((e) => e.productId).toSet(), {'c', 'd'});
    });
  });

  group('selection identity', () {
    test('15 filtered index must not map to original list index', () {
      final all = [
        _item(id: 'first', name: 'Alpha', productCode: 'A1'),
        _item(id: 'target', name: 'Bravo Target', productCode: 'B2'),
        _item(id: 'third', name: 'Charlie', productCode: 'C3'),
      ];
      final filtered = consignmentPickerVisibleItems(all, query: 'Bravo');
      expect(filtered, hasLength(1));
      expect(filtered[0].productId, isNot(all[0].productId));
      expect(filtered[0].productId, 'target');
    });

    test('16 code search selects correct product id', () {
      final all = [
        _item(id: 'x', name: 'Outro', productCode: 'XX'),
        _item(id: 'mirjoias-anel-2-folhas', name: 'Anel 2 Folhas', productCode: 'AN22PR'),
      ];
      final hit = consignmentPickerVisibleItems(all, query: 'AN22PR').single;
      expect(hit.productId, 'mirjoias-anel-2-folhas');
    });

    test('17 variation identity preserved on picker item', () {
      final v = _item(
        id: 'var1',
        name: 'Anel Var',
        productCode: 'AN51PR',
        stockKind: 'variation',
        variacoes: {
          'P': {'sem-cor': 1},
          'M': {'sem-cor': 1},
        },
      );
      final hit = consignmentPickerVisibleItems([v], query: 'AN51PR').single;
      expect(hit.productId, 'var1');
      expect(hit.stockKind, 'variation');
      expect(hit.variacoes.keys.toSet(), {'P', 'M'});
    });

    test('18 resolveConsignmentPickerSelection uses productId not filtered index', () {
      final all = [
        _item(id: 'first', name: 'Alpha', productCode: 'A1'),
        _item(id: 'target', name: 'Bravo Target', productCode: 'B2', stockKind: 'variation', variacoes: {
          'P': {'sem-cor': 2},
        }),
        _item(id: 'third', name: 'Charlie', productCode: 'C3'),
      ];
      final filtered = consignmentPickerVisibleItems(all, query: 'Bravo');
      final resolved = resolveConsignmentPickerSelection(
        catalog: all,
        selected: filtered.single,
      );
      expect(resolved.productId, 'target');
      expect(identical(resolved, all[1]), isTrue);
      expect(resolved.stockKind, 'variation');
      expect(resolved.variacoes.containsKey('P'), isTrue);
    });
  });

  testWidgets('13-14 tap filtered result adds correct productId to draft', (tester) async {
    ConsignmentService.debugPickerItems = [
      _item(id: 'keep', name: 'Alpha Keep', productCode: 'K1'),
      _item(id: 'want', name: 'Solitário Cravejado', productCode: 'AN59PR'),
      _item(id: 'other', name: 'Omega Other', productCode: 'O9'),
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: ConsignmentFormScreen(lojaId: 'mirjoias'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('consignment_product_search')), 'solitario');
    await tester.pumpAndSettle();
    expect(find.text('Solitário Cravejado'), findsOneWidget);
    expect(find.text('Alpha Keep'), findsNothing);
    await tester.tap(find.text('Solitário Cravejado'));
    await tester.pumpAndSettle();
    expect(find.text('Solitário Cravejado'), findsOneWidget);
    expect(find.text('Alpha Keep'), findsNothing);
  });

  testWidgets('13 tap unfiltered list item adds correct product', (tester) async {
    ConsignmentService.debugPickerItems = [
      _item(id: 'a', name: 'Produto Lista A', productCode: 'LA'),
      _item(id: 'b', name: 'Produto Lista B', productCode: 'LB'),
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: ConsignmentFormScreen(lojaId: 'mirjoias'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Produto Lista B'));
    await tester.pumpAndSettle();
    expect(find.text('Produto Lista B'), findsOneWidget);
    expect(find.text('Produto Lista A'), findsNothing);
  });

  test('authoritative code field is codigoBarras', () {
    expect(consignmentAuthoritativeProductCodeField, 'codigoBarras');
    expect(
      consignmentProductCodeFromMaps(
        {'codigoBarras': 'DRAFT'},
        {'codigoBarras': 'AN05PR', 'sku': 'SKU1'},
      ),
      'AN05PR',
    );
    expect(
      consignmentProductCodeFromMaps(null, {'codigoBarras': '00125'}),
      '00125',
    );
  });
}
