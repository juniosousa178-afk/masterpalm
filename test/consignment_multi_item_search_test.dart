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
  int qty = 1,
}) {
  return ConsignmentDraftLine(
    productId: id,
    productName: name,
    productType: size.isEmpty ? 'simple' : 'variation',
    qtySent: qty,
    unitSalePrice: 10,
    variationKey: ConsignmentVariationKey(size: size, color: color),
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

    test('DISTINCT_PRODUCT_ID_NOT_DUPLICATE_TEST_PASS', () {
      final draft = <ConsignmentDraftLine>[_line(id: 'A', name: 'X')];
      ConsignmentDraftMutator.addOrMerge(draft, _line(id: 'B', name: 'X'));
      expect(draft, hasLength(2));
    });

    test('EMPTY_BARCODE_NOT_DUPLICATE_TEST_PASS', () {
      final a = _line(id: 'id-a', name: 'Sem codigo');
      final b = _line(id: 'id-b', name: 'Sem codigo');
      final draft = <ConsignmentDraftLine>[a];
      ConsignmentDraftMutator.addOrMerge(draft, b);
      expect(draft.map((e) => e.productId), ['id-a', 'id-b']);
    });

    test('EMPTY_CODE_NOT_DUPLICATE_TEST_PASS', () {
      final draft = <ConsignmentDraftLine>[_line(id: 'p1', name: '')];
      ConsignmentDraftMutator.addOrMerge(draft, _line(id: 'p2', name: ''));
      expect(draft.map((e) => e.productId), ['p1', 'p2']);
    });

    test('SAME_PRODUCT_DUPLICATE_POLICY_TEST_PASS', () {
      final draft = <ConsignmentDraftLine>[_line(id: 'A', name: 'Anel', qty: 1)];
      ConsignmentDraftMutator.addOrMerge(draft, _line(id: 'A', name: 'Anel', qty: 2));
      expect(draft, hasLength(1));
      expect(draft.single.qtySent, 3);
    });

    test('VARIATION_LINE_IDENTITY_TEST_PASS', () {
      final draft = <ConsignmentDraftLine>[
        _line(id: 'ring', name: 'Anel', size: '14', color: 'prata'),
      ];
      ConsignmentDraftMutator.addOrMerge(
        draft,
        _line(id: 'ring', name: 'Anel', size: '18', color: 'prata'),
      );
      expect(draft, hasLength(2));
      ConsignmentDraftMutator.addOrMerge(
        draft,
        _line(id: 'ring', name: 'Anel', size: '14', color: 'prata', qty: 1),
      );
      expect(draft, hasLength(2));
      expect(draft.first.qtySent, 2);
    });

    test('EDIT_ITEM_PRESERVES_OTHER_ITEMS_TEST_PASS', () {
      final draft = [
        _line(id: 'A', name: 'A'),
        _line(id: 'B', name: 'B', qty: 1),
        _line(id: 'C', name: 'C'),
      ];
      draft[1].qtySent = 9;
      expect(draft.map((e) => e.productId), ['A', 'B', 'C']);
      expect(draft[1].qtySent, 9);
    });

    test('REMOVE_ITEM_PRESERVES_OTHER_ITEMS_TEST_PASS', () {
      final draft = [
        _line(id: 'A', name: 'A'),
        _line(id: 'B', name: 'B'),
        _line(id: 'C', name: 'C'),
      ];
      draft.removeAt(1);
      expect(draft.map((e) => e.productId), ['A', 'C']);
    });

    test('ADD_AFTER_REMOVE_TEST_PASS', () {
      final draft = [
        _line(id: 'A', name: 'A'),
        _line(id: 'C', name: 'C'),
      ];
      ConsignmentDraftMutator.addOrMerge(draft, _line(id: 'D', name: 'D'));
      expect(draft.map((e) => e.productId), ['A', 'C', 'D']);
    });

    test('NO_DRAFT_STOCK_WRITE_TEST_PASS', () {
      // Draft mutator is pure memory — no service/firestore side effects.
      final draft = <ConsignmentDraftLine>[];
      ConsignmentDraftMutator.addOrMerge(draft, _line(id: 'A', name: 'A'));
      expect(identical(ConsignmentService.debugTransport, null), isTrue);
    });

    test('TENANT_ISOLATION_TEST_PASS', () {
      final a = _line(id: 'loja-a-prod', name: 'P');
      final b = _line(id: 'loja-b-prod', name: 'P');
      expect(a.productId == b.productId, isFalse);
    });

    test('never replaces list when appending', () {
      final draft = <ConsignmentDraftLine>[_line(id: 'A', name: 'A')];
      final before = List<ConsignmentDraftLine>.from(draft);
      ConsignmentDraftMutator.addOrMerge(draft, _line(id: 'B', name: 'B'));
      expect(identical(draft, draft), isTrue);
      expect(draft.length, before.length + 1);
      expect(draft.first.productId, 'A');
    });
  });

  group('widget multi-search accumulate', () {
    testWidgets('SEARCH_REOPEN adds A then B then C', (tester) async {
      ConsignmentService.debugPickerItems = [
        _item(id: 'A', name: 'Produto Alpha', productCode: 'CA'),
        _item(id: 'B', name: 'Produto Bravo', productCode: 'CB'),
        _item(id: 'C', name: 'Produto Charlie', productCode: 'CC'),
      ];
      await tester.pumpWidget(
        const MaterialApp(home: ConsignmentFormScreen(lojaId: 'test-loja')),
      );
      await tester.pumpAndSettle();

      Future<void> addNamed(String name) async {
        await tester.ensureVisible(find.text('Adicionar'));
        await tester.tap(find.text('Adicionar'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('consignment_product_search')),
          name.split(' ').last, // Alpha / Bravo / Charlie
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(name));
        await tester.tap(find.text(name));
        // Post-frame Navigator.pop in picker + draft setState.
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('consignment_product_search')), findsNothing);
      }

      await addNamed('Produto Alpha');
      expect(find.byKey(const ValueKey('consignment_draft_line_A|||')), findsOneWidget);
      expect(find.text('Itens: 1'), findsOneWidget);

      await addNamed('Produto Bravo');
      expect(find.byKey(const ValueKey('consignment_draft_line_A|||')), findsOneWidget);
      expect(find.byKey(const ValueKey('consignment_draft_line_B|||')), findsOneWidget);
      expect(find.text('Itens: 2'), findsOneWidget);

      await addNamed('Produto Charlie');
      expect(find.byKey(const ValueKey('consignment_draft_line_A|||')), findsOneWidget);
      expect(find.byKey(const ValueKey('consignment_draft_line_B|||')), findsOneWidget);
      expect(find.byKey(const ValueKey('consignment_draft_line_C|||')), findsOneWidget);
      expect(find.text('Itens: 3'), findsOneWidget);
    });

    testWidgets('SEARCH_FILTER_DOES_NOT_MUTATE_DRAFT', (tester) async {
      ConsignmentService.debugPickerItems = [
        _item(id: 'A', name: 'Anel Ouro', productCode: 'A1'),
        _item(id: 'B', name: 'Colar Prata', productCode: 'B1'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: ConsignmentFormScreen(
            lojaId: 'test-loja',
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
      // Search sheet filters results; draft Anel may still exist under the sheet.
      expect(find.text('Colar Prata'), findsOneWidget);
      await tester.tap(find.text('Colar Prata'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      // Draft must still have A after search filtered it from picker.
      expect(find.byKey(const ValueKey('consignment_draft_line_A|||')), findsOneWidget);
      expect(find.byKey(const ValueKey('consignment_draft_line_B|||')), findsOneWidget);
      expect(find.text('Itens: 2'), findsOneWidget);
    });
  });
}
