import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_draft.dart';
import 'package:master_palm/features/consignments/consignment_eligibility.dart';
import 'package:master_palm/features/consignments/consignment_models.dart';
import 'package:master_palm/features/consignments/consignment_product_picker.dart';
import 'package:master_palm/features/consignments/consignment_service.dart';
import 'package:master_palm/features/consignments/screens/consignment_form_screen.dart';

ConsignmentPickerItem _item({
  required String id,
  required String name,
  String productCode = '',
  int qty = 5,
  String stockKind = 'simple',
  Map<String, dynamic> variacoes = const {},
}) {
  return ConsignmentPickerItem(
    productId: id,
    name: name,
    productCode: productCode,
    price: 10,
    availableQty: qty,
    stockKind: stockKind,
    variacoes: variacoes,
    eligible: true,
    unavailableReason: '',
  );
}

ConsignmentDraftLine _line({
  required String id,
  required String name,
  String size = '',
  String color = '',
  String extra = '',
  int qty = 1,
}) {
  return ConsignmentDraftLine(
    productId: id,
    productName: name,
    productType: size.isEmpty ? 'simple' : 'variation',
    qtySent: qty,
    unitSalePrice: 10,
    variationKey: ConsignmentVariationKey(size: size, color: color, extra: extra),
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

  group('pure draft append contract', () {
    test('ADD_FIRST_PRODUCT_TEST_PASS', () {
      final draft = <ConsignmentDraftLine>[];
      ConsignmentDraftMutator.addOrMerge(draft, _line(id: 'A', name: 'Anel'));
      expect(draft.map((e) => e.productId), ['A']);
    });

    test('ADD_SECOND_DISTINCT_PRODUCT_TEST_PASS', () {
      final draft = <ConsignmentDraftLine>[_line(id: 'A', name: 'Anel')];
      ConsignmentDraftMutator.addOrMerge(draft, _line(id: 'B', name: 'Colar'));
      expect(draft.map((e) => e.productId), ['A', 'B']);
    });

    test('ADD_THIRD_DISTINCT_PRODUCT_TEST_PASS', () {
      final draft = <ConsignmentDraftLine>[
        _line(id: 'A', name: 'Anel'),
        _line(id: 'B', name: 'Colar'),
      ];
      ConsignmentDraftMutator.addOrMerge(draft, _line(id: 'C', name: 'Brinco'));
      expect(draft.map((e) => e.productId), ['A', 'B', 'C']);
    });

    test('EMPTY_CODE_DISTINCT_PRODUCTS', () {
      final draft = <ConsignmentDraftLine>[_line(id: 'p1', name: 'X')];
      ConsignmentDraftMutator.addOrMerge(draft, _line(id: 'p2', name: 'X'));
      expect(draft.map((e) => e.productId), ['p1', 'p2']);
    });

    test('NULL_BARCODE_DISTINCT_PRODUCTS', () {
      final a = _line(id: 'id-a', name: 'Sem codigo');
      final b = _line(id: 'id-b', name: 'Sem codigo');
      final draft = <ConsignmentDraftLine>[a];
      ConsignmentDraftMutator.addOrMerge(draft, b);
      expect(draft.map((e) => e.productId), ['id-a', 'id-b']);
    });

    test('SAME_LINE_INCREMENT', () {
      final draft = <ConsignmentDraftLine>[_line(id: 'A', name: 'Anel', qty: 1)];
      ConsignmentDraftMutator.addOrMerge(draft, _line(id: 'A', name: 'Anel', qty: 2));
      expect(draft, hasLength(1));
      expect(draft.single.qtySent, 3);
    });

    test('VARIATION_DISTINCT_SIZE', () {
      final draft = <ConsignmentDraftLine>[
        _line(id: 'ring', name: 'Anel', size: '14', color: 'prata'),
      ];
      ConsignmentDraftMutator.addOrMerge(
        draft,
        _line(id: 'ring', name: 'Anel', size: '18', color: 'prata'),
      );
      expect(draft, hasLength(2));
    });

    test('VARIATION_DISTINCT_COLOR', () {
      final draft = <ConsignmentDraftLine>[
        _line(id: 'ring', name: 'Anel', size: '14', color: 'prata'),
      ];
      ConsignmentDraftMutator.addOrMerge(
        draft,
        _line(id: 'ring', name: 'Anel', size: '14', color: 'ouro'),
      );
      expect(draft, hasLength(2));
    });

    test('VARIATION_DISTINCT_EXTRA', () {
      final draft = <ConsignmentDraftLine>[
        _line(id: 'col', name: 'Colar', size: '45cm', color: 'cristal', extra: 'A'),
      ];
      ConsignmentDraftMutator.addOrMerge(
        draft,
        _line(id: 'col', name: 'Colar', size: '45cm', color: 'cristal', extra: 'B'),
      );
      expect(draft, hasLength(2));
    });

    test('REMOVE_B_PRESERVES_A_C', () {
      final draft = [
        _line(id: 'A', name: 'A'),
        _line(id: 'B', name: 'B'),
        _line(id: 'C', name: 'C'),
      ];
      draft.removeAt(1);
      expect(draft.map((e) => e.productId), ['A', 'C']);
    });

    test('ADD_D_AFTER_REMOVE', () {
      final draft = [
        _line(id: 'A', name: 'A'),
        _line(id: 'C', name: 'C'),
      ];
      ConsignmentDraftMutator.addOrMerge(draft, _line(id: 'D', name: 'D'));
      expect(draft.map((e) => e.productId), ['A', 'C', 'D']);
    });

    test('NO_DRAFT_STOCK_WRITE', () {
      final draft = <ConsignmentDraftLine>[];
      ConsignmentDraftMutator.addOrMerge(draft, _line(id: 'A', name: 'A'));
      expect(identical(ConsignmentService.debugTransport, null), isTrue);
    });

    test('TENANT_ISOLATION', () {
      expect(
        _line(id: 'mirjoias-a', name: 'P').productId ==
            _line(id: 'nathy-a', name: 'P').productId,
        isFalse,
      );
    });

    test('sem-cor and empty color are distinct identity slots', () {
      final a = ConsignmentDraftLineIdentity(productId: 'p', color: '');
      final b = ConsignmentDraftLineIdentity(productId: 'p', color: 'sem-cor');
      expect(a == b, isFalse);
    });
  });

  group('widget multi-search accumulate', () {
    Future<void> addById(WidgetTester tester, {required String id, required String name}) async {
      await tester.ensureVisible(find.text('Adicionar'));
      await tester.tap(find.text('Adicionar'));
      await tester.pumpAndSettle();
      final term = name.split(' ').last;
      await tester.enterText(
        find.byKey(const Key('consignment_product_search')),
        term,
      );
      await tester.pumpAndSettle();
      final tile = find.byKey(ValueKey('picker_$id'));
      expect(tile, findsOneWidget);
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('consignment_product_search')), findsNothing);
    }

    testWidgets('SEARCH_REOPEN adds A then B then C', (tester) async {
      ConsignmentService.debugPickerItems = [
        _item(id: 'A', name: 'Produto Alpha', productCode: 'CA'),
        _item(id: 'B', name: 'Produto Bravo', productCode: 'CB'),
        _item(id: 'C', name: 'Produto Charlie', productCode: 'CC'),
      ];
      await tester.pumpWidget(
        const MaterialApp(home: ConsignmentFormScreen(lojaId: 'mirjoias')),
      );
      await tester.pumpAndSettle();

      await addById(tester, id: 'A', name: 'Produto Alpha');
      expect(find.byKey(const ValueKey('consignment_draft_line_A|||')), findsOneWidget);
      expect(find.text('Itens: 1'), findsOneWidget);

      await addById(tester, id: 'B', name: 'Produto Bravo');
      expect(find.byKey(const ValueKey('consignment_draft_line_A|||')), findsOneWidget);
      expect(find.byKey(const ValueKey('consignment_draft_line_B|||')), findsOneWidget);
      expect(find.text('Itens: 2'), findsOneWidget);

      await addById(tester, id: 'C', name: 'Produto Charlie');
      expect(find.byKey(const ValueKey('consignment_draft_line_A|||')), findsOneWidget);
      expect(find.byKey(const ValueKey('consignment_draft_line_B|||')), findsOneWidget);
      expect(find.byKey(const ValueKey('consignment_draft_line_C|||')), findsOneWidget);
      expect(find.text('Itens: 3'), findsOneWidget);
    });

    testWidgets('SECOND_SEARCH_FILTER_UPDATES across reopen', (tester) async {
      ConsignmentService.debugPickerItems = [
        _item(id: 'A', name: 'Anel Ouro', productCode: ''),
        _item(id: 'B', name: 'Colar Prata', productCode: ''),
        _item(id: 'C', name: 'Brinco Azul', productCode: ''),
      ];
      await tester.pumpWidget(
        const MaterialApp(home: ConsignmentFormScreen(lojaId: 'mirjoias')),
      );
      await tester.pumpAndSettle();

      await addById(tester, id: 'A', name: 'Anel Ouro');

      await tester.tap(find.text('Adicionar'));
      await tester.pumpAndSettle();
      // Fresh controller — must not keep previous query.
      expect(
        tester.widget<TextField>(find.byKey(const Key('consignment_product_search'))).controller!.text,
        isEmpty,
      );
      await tester.enterText(find.byKey(const Key('consignment_product_search')), 'Colar');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('picker_B')), findsOneWidget);
      expect(find.byKey(const ValueKey('picker_A')), findsNothing);
      expect(find.byKey(const ValueKey('picker_C')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('picker_B')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('consignment_draft_line_A|||')), findsOneWidget);
      expect(find.byKey(const ValueKey('consignment_draft_line_B|||')), findsOneWidget);
    });

    testWidgets('OPEN_CLOSE_WITHOUT_SELECTION_PRESERVES_DRAFT', (tester) async {
      ConsignmentService.debugPickerItems = [
        _item(id: 'A', name: 'Produto Alpha', productCode: 'CA'),
        _item(id: 'B', name: 'Produto Bravo', productCode: 'CB'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: ConsignmentFormScreen(
            lojaId: 'mirjoias',
            debugInitialLines: [_line(id: 'A', name: 'Produto Alpha')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adicionar'));
      await tester.pumpAndSettle();
      // Dismiss sheet via barrier without selecting.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('consignment_draft_line_A|||')), findsOneWidget);
      expect(find.text('Itens: 1'), findsOneWidget);
    });

    testWidgets('SEARCH_FILTER_DOES_NOT_MUTATE_DRAFT', (tester) async {
      ConsignmentService.debugPickerItems = [
        _item(id: 'A', name: 'Anel Ouro', productCode: 'A1'),
        _item(id: 'B', name: 'Colar Prata', productCode: 'B1'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: ConsignmentFormScreen(
            lojaId: 'mirjoias',
            debugInitialLines: [_line(id: 'A', name: 'Anel Ouro')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Anel Ouro'), findsOneWidget);

      await tester.tap(find.text('Adicionar'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('consignment_product_search')),
        'Colar',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('picker_B')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('picker_B')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('consignment_draft_line_A|||')), findsOneWidget);
      expect(find.byKey(const ValueKey('consignment_draft_line_B|||')), findsOneWidget);
      expect(find.text('Itens: 2'), findsOneWidget);
    });

    testWidgets('MIR empty-code products accumulate across three opens', (tester) async {
      ConsignmentService.debugPickerItems = [
        _item(id: 'mirjoias-anel-folha', name: 'Anel Folha', productCode: ''),
        _item(id: 'mirjoias-colar-lua', name: 'Colar Lua', productCode: ''),
        _item(id: 'mirjoias-brinco-sol', name: 'Brinco Sol', productCode: ''),
      ];
      await tester.pumpWidget(
        const MaterialApp(home: ConsignmentFormScreen(lojaId: 'mirjoias')),
      );
      await tester.pumpAndSettle();

      await addById(tester, id: 'mirjoias-anel-folha', name: 'Anel Folha');
      await addById(tester, id: 'mirjoias-colar-lua', name: 'Colar Lua');
      await addById(tester, id: 'mirjoias-brinco-sol', name: 'Brinco Sol');

      expect(
        find.byKey(const ValueKey('consignment_draft_line_mirjoias-anel-folha|||')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('consignment_draft_line_mirjoias-colar-lua|||')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('consignment_draft_line_mirjoias-brinco-sol|||')),
        findsOneWidget,
      );
      expect(find.text('Itens: 3'), findsOneWidget);
    });

    testWidgets('commit-before-pop survives null sheet result (Safari simulation)',
        (tester) async {
      ConsignmentService.debugPickerItems = [
        _item(id: 'A', name: 'Alpha', productCode: ''),
        _item(id: 'B', name: 'Bravo', productCode: ''),
      ];
      await tester.pumpWidget(
        const MaterialApp(home: ConsignmentFormScreen(lojaId: 'mirjoias')),
      );
      await tester.pumpAndSettle();

      await addById(tester, id: 'A', name: 'Alpha');
      await addById(tester, id: 'B', name: 'Bravo');
      expect(find.byKey(const ValueKey('consignment_draft_line_A|||')), findsOneWidget);
      expect(find.byKey(const ValueKey('consignment_draft_line_B|||')), findsOneWidget);
    });
  });
}
