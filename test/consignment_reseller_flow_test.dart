import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_eligibility.dart';
import 'package:master_palm/features/consignments/consignment_errors.dart';
import 'package:master_palm/features/consignments/consignment_models.dart';
import 'package:master_palm/features/consignments/consignment_service.dart';
import 'package:master_palm/features/consignments/screens/consignment_form_screen.dart';
import 'package:master_palm/features/consignments/screens/consignment_list_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fake;
  late List<Map<String, dynamic>> calls;

  setUp(() {
    fake = FakeFirebaseFirestore();
    calls = [];
    ConsignmentService.debugFirestore = fake;
    ConsignmentService.debugTransport = (name, data) async {
      calls.add({'name': name, ...Map<String, dynamic>.from(data)});
      if (data['operation'] == 'listEligibleProducts') {
        return {'products': <Map<String, dynamic>>[]};
      }
      final payload = Map<String, dynamic>.from(data['payload'] as Map);
      final id = payload['resellerId'].toString();
      await fake
          .collection('lojas')
          .doc('master')
          .collection('consignment_resellers')
          .doc(id)
          .set({
        'storeId': 'master',
        'resellerId': id,
        'displayName': payload['displayName'],
        'active': true,
        'notes': payload['notes'] ?? '',
        'phone': payload['phone'] ?? '',
      });
      return {
        'resellerId': id,
        'displayName': payload['displayName'],
      };
    };
  });

  tearDown(() {
    ConsignmentService.debugFirestore = null;
    ConsignmentService.debugTransport = null;
    ConsignmentService.debugPickerItems = null;
    ConsignmentService.debugConnectivity = null;
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    List<ConsignmentDraftLine>? lines,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: ConsignmentFormScreen(
        lojaId: 'master',
        debugInitialLines: lines,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, String name) async {
    await tester.scrollUntilVisible(
      find.text(name),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(name), findsOneWidget);
  }

  List<ConsignmentDraftLine> threeLines() => [
        ConsignmentDraftLine(
          productId: 'p1',
          productName: 'Produto A',
          productType: 'simple',
          qtySent: 2,
          unitSalePrice: 10,
          commissionType: 'PERCENTUAL',
          commissionValue: 5,
        ),
        ConsignmentDraftLine(
          productId: 'p2',
          productName: 'Produto B',
          productType: 'simple',
          qtySent: 1,
          unitSalePrice: 20,
          commissionType: 'VALOR_FIXO_POR_UNIDADE',
          commissionValue: 2,
        ),
        ConsignmentDraftLine(
          productId: 'p3',
          productName: 'Produto C',
          productType: 'simple',
          qtySent: 3,
          unitSalePrice: 15,
        ),
      ];

  testWidgets('1 open reseller form', (tester) async {
    await pumpForm(tester);
    expect(find.text('Cadastrar revendedor'), findsOneWidget);
    expect(find.text('Nenhum revendedor cadastrado'), findsOneWidget);
    await tester.tap(find.text('Cadastrar revendedor'));
    await tester.pumpAndSettle();
    expect(find.text('Nome *'), findsOneWidget);
    expect(find.text('Telefone'), findsOneWidget);
    expect(find.text('Observação'), findsOneWidget);
  });

  testWidgets('2 empty name blocked', (tester) async {
    await pumpForm(tester);
    await tester.tap(find.text('Cadastrar revendedor'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe o nome do revendedor.'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('3-9 create success auto-select refresh preserve lines no stock',
      (tester) async {
    await pumpForm(tester, lines: threeLines());
    await tester.tap(find.text('Cadastrar revendedor'));
    await tester.pumpAndSettle();
    final dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(dialogField.first, 'Revendedor Teste');
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Salvar'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Revendedor Teste'), findsWidgets);
    expect(find.text('Nenhum revendedor cadastrado'), findsNothing);
    await reveal(tester, 'Produto A');
    await reveal(tester, 'Produto B');
    await reveal(tester, 'Produto C');
    expect(calls, hasLength(1));
    expect(calls.single['name'], 'consignmentCommand');
    expect(calls.single['operation'], 'createReseller');
    expect(calls.single['lojaId'], 'master');
    expect(
      (calls.single['payload'] as Map)['displayName'],
      'Revendedor Teste',
    );
  });

  testWidgets('14 existing reseller selectable', (tester) async {
    await fake
        .collection('lojas')
        .doc('master')
        .collection('consignment_resellers')
        .doc('rev1')
        .set({
      'storeId': 'master',
      'resellerId': 'rev1',
      'displayName': 'Maria',
      'active': true,
    });
    await pumpForm(tester);
    expect(find.text('Nenhum revendedor cadastrado'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maria').last);
    await tester.pumpAndSettle();
    expect(find.text('Maria'), findsWidgets);
    expect(calls, isEmpty);
  });

  testWidgets('15 inactive reseller excluded', (tester) async {
    final col = fake
        .collection('lojas')
        .doc('master')
        .collection('consignment_resellers');
    await col.doc('rev1').set({
      'storeId': 'master',
      'resellerId': 'rev1',
      'displayName': 'Maria',
      'active': true,
    });
    await col.doc('rev0').set({
      'storeId': 'master',
      'resellerId': 'rev0',
      'displayName': 'Inativo',
      'active': false,
    });
    await col.doc('revx').set({
      'storeId': 'other',
      'resellerId': 'revx',
      'displayName': 'Outra Loja',
      'active': true,
    });
    await pumpForm(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Maria').hitTestable(), findsWidgets);
    expect(find.text('Inativo'), findsNothing);
    expect(find.text('Outra Loja'), findsNothing);
  });

  test('createReseller empty name does not call transport', () {
    expect(
      () => ConsignmentService.createReseller(lojaId: 'master', displayName: '  '),
      throwsA(predicate((e) =>
          e is ConsignmentException &&
          e.code == 'INVALID_ARGUMENT' &&
          e.message == 'Informe o nome do revendedor.')),
    );
    expect(calls, isEmpty);
  });

  test('4-13 watchResellers store scope and createReseller command isolation', () async {
    final col = fake
        .collection('lojas')
        .doc('master')
        .collection('consignment_resellers');
    await col.doc('a').set({
      'storeId': 'master',
      'resellerId': 'a',
      'displayName': 'Zeca',
      'active': true,
    });
    await col.doc('b').set({
      'storeId': 'master',
      'resellerId': 'b',
      'displayName': 'Ana',
      'active': true,
    });
    await col.doc('c').set({
      'storeId': 'master',
      'resellerId': 'c',
      'displayName': 'Inativo',
      'active': false,
    });
    await col.doc('d').set({
      'storeId': 'other',
      'resellerId': 'd',
      'displayName': 'Outra',
      'active': true,
    });
    final list = await ConsignmentService.watchResellers('master').first;
    expect(list.map((e) => e.displayName).toList(), ['Ana', 'Zeca']);
    final created = await ConsignmentService.createReseller(
      lojaId: 'master',
      displayName: 'Revendedor Teste',
      phone: '1199',
    );
    expect(created['displayName'], 'Revendedor Teste');
    expect(calls.single['operation'], 'createReseller');
    expect(calls.single['name'], 'consignmentCommand');
    expect(calls.any((c) => c['operation'] == 'issue'), isFalse);
    expect(calls.any((c) => c['operation'] == 'createDraft'), isFalse);
    expect(calls.any((c) => c['name'] == 'stockCatalogCommand'), isFalse);
  });

  testWidgets('16 consignados list still renders nova consignacao chrome',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ConsignmentListScreen()));
    await tester.pump();
    expect(find.text('Consignados'), findsOneWidget);
  });

  List<ConsignmentPickerItem> pickerCatalog() => const [
        ConsignmentPickerItem(
          productId: 'master-consignment-canary-simple-20260920',
          name: 'Produto Teste Consignado Canary',
          price: 10,
          availableQty: 2,
          stockKind: 'simple',
          variacoes: {},
          eligible: true,
          unavailableReason: '',
        ),
        ConsignmentPickerItem(
          productId: 'master-anel-2-folhas-t-18-prata-925',
          name: 'Anel 2 Folhas',
          price: 80,
          availableQty: 1,
          stockKind: '',
          variacoes: {},
          eligible: false,
        ),
      ];

  test('1-13 picker eligibility contract matches backend', () {
    ConsignmentPickerItem eval({
      required String id,
      required Map<String, dynamic> stock,
      Map<String, dynamic>? draft,
      Map<String, dynamic>? dependency,
      String lojaId = 'master',
    }) =>
        evaluateConsignmentPickerItem(
          productId: id,
          lojaId: lojaId,
          stock: stock,
          draft: draft ?? {'nome': id, 'preco': 10, 'publicadoNoCatalogo': false, 'ativo': false},
          dependency: dependency,
        );

    final canary = eval(
      id: 'master-consignment-canary-simple-20260920',
      stock: {
        'stockKind': 'simple',
        'stockRevision': 0,
        'quantidade': 2,
        'variacoes': {},
      },
      draft: {
        'nome': 'Produto Teste Consignado Canary',
        'preco': 10,
        'publicadoNoCatalogo': false,
        'ativo': false,
      },
      dependency: {'comboIds': []},
    );
    expect(canary.eligible, isTrue);
    expect(canary.name, 'Produto Teste Consignado Canary');

    final variation = eval(
      id: 'varp',
      stock: {
        'stockKind': 'variation',
        'stockRevision': 0,
        'quantidade': 4,
        'variacoes': {
          'P': {'sem-cor': 4},
        },
      },
      dependency: {'comboIds': []},
    );
    expect(variation.eligible, isTrue);

    expect(
      eval(
        id: 'zero',
        stock: {'stockKind': 'simple', 'stockRevision': 0, 'quantidade': 0, 'variacoes': {}},
        dependency: {'comboIds': []},
      ).eligible,
      isFalse,
    );
    expect(
      eval(
        id: 'nodep',
        stock: {'stockKind': 'simple', 'stockRevision': 0, 'quantidade': 3, 'variacoes': {}},
      ).eligible,
      isFalse,
    );
    expect(
      eval(
        id: 'bad',
        stock: {'tipoProduto': 'simples', 'quantidade': 3},
        dependency: {'comboIds': []},
      ).eligible,
      isFalse,
    );
    expect(
      eval(
        id: 'grade',
        stock: {
          'stockKind': 'variation',
          'stockRevision': 0,
          'quantidade': 3,
          'variacoes': {
            'P': {'Azul': 1, 'Vermelho': 2},
          },
          'tamanhos': ['P'],
          'cores': ['Azul', 'Vermelho'],
        },
        dependency: {'comboIds': []},
      ).stockKind,
      'grade',
    );
    expect(
      eval(
        id: 'grade',
        stock: {
          'stockKind': 'variation',
          'stockRevision': 0,
          'quantidade': 3,
          'variacoes': {
            'P': {'Azul': 1, 'Vermelho': 2},
          },
          'tamanhos': ['P'],
          'cores': ['Azul', 'Vermelho'],
        },
        dependency: {'comboIds': []},
      ).eligible,
      isTrue,
    );
    expect(
      eval(
        id: 'combo',
        stock: {
          'stockKind': 'combo',
          'tipoProduto': 'combo',
          'stockRevision': 0,
          'quantidade': 1,
          'itensCombo': [
            {'productId': 'x', 'quantidade': 1},
          ],
        },
        dependency: {'comboIds': []},
      ).eligible,
      isFalse,
    );
    expect(
      eval(
        id: 'foreign',
        stock: {
          'stockKind': 'simple',
          'stockRevision': 0,
          'quantidade': 4,
          'variacoes': {},
          'lojaId': 'other',
        },
        dependency: {'comboIds': []},
      ).eligible,
      isFalse,
    );
    expect(
      consignmentPickerVisibleItems([canary]).map((e) => e.productId),
      ['master-consignment-canary-simple-20260920'],
    );
  });

  test('loadPickerProducts uses consignmentCommand listEligibleProducts', () async {
    ConsignmentService.debugConnectivity = () async => [ConnectivityResult.wifi];
    ConsignmentService.debugPickerItems = null;
    ConsignmentService.debugTransport = (name, data) async {
      calls.add({'name': name, ...Map<String, dynamic>.from(data)});
      expect(data['operation'], 'listEligibleProducts');
      return {
        'products': [
          {
            'productId': 'master-consignment-canary-simple-20260920',
            'name': 'Produto Teste Consignado Canary',
            'price': 10,
            'availableQty': 2,
            'stockKind': 'simple',
            'variacoes': {},
          },
        ],
      };
    };
    final items = await ConsignmentService.loadPickerProducts('master');
    expect(items, hasLength(1));
    expect(items.single.name, 'Produto Teste Consignado Canary');
    expect(items.single.availableQty, 2);
    expect(calls.single['operation'], 'listEligibleProducts');
    expect(calls.any((c) => c['name'] == 'stockCatalogCommand'), isFalse);
  });

  testWidgets('11-12 14-16 canary visible selectable no stock mutation', (tester) async {
    ConsignmentService.debugPickerItems = pickerCatalog();
    await pumpForm(tester);
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    expect(find.text('Disponíveis para consignação'), findsOneWidget);
    expect(find.text('Produto Teste Consignado Canary'), findsOneWidget);
    expect(find.textContaining('2 disponíveis'), findsOneWidget);
    expect(find.text('Anel 2 Folhas'), findsNothing);
    await tester.tap(find.text('Produto Teste Consignado Canary'));
    await tester.pumpAndSettle();
    expect(find.text('Produto Teste Consignado Canary'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('27 30 unsafe product excluded then disabled on search', (tester) async {
    ConsignmentService.debugPickerItems = pickerCatalog();
    await pumpForm(tester);
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    expect(find.text('Anel 2 Folhas'), findsNothing);
    await tester.enterText(find.byKey(const Key('consignment_product_search')), 'Anel 2 Folhas');
    await tester.pumpAndSettle();
    expect(find.text('Anel 2 Folhas'), findsWidgets);
    expect(find.text(consignmentProductUnavailableReason), findsOneWidget);
    final unsafeTile = find.ancestor(
      of: find.text(consignmentProductUnavailableReason),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(unsafeTile).enabled, isFalse);
    await tester.tap(unsafeTile);
    await tester.pumpAndSettle();
    expect(find.text('Disponíveis para consignação'), findsOneWidget);
    Navigator.pop(tester.element(find.text('Disponíveis para consignação')));
    await tester.pumpAndSettle();
    expect(find.text('Anel 2 Folhas'), findsNothing);
  });

  testWidgets('31-32 existing reseller and draft lines preserved after picker',
      (tester) async {
    ConsignmentService.debugPickerItems = pickerCatalog();
    await fake
        .collection('lojas')
        .doc('master')
        .collection('consignment_resellers')
        .doc('rev1')
        .set({
      'storeId': 'master',
      'resellerId': 'rev1',
      'displayName': 'Maria',
      'active': true,
    });
    await pumpForm(tester, lines: threeLines());
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maria').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Produto Teste Consignado Canary'));
    await tester.pumpAndSettle();
    expect(find.text('Maria'), findsWidgets);
    await reveal(tester, 'Produto A');
    await reveal(tester, 'Produto B');
    await reveal(tester, 'Produto C');
    await reveal(tester, 'Produto Teste Consignado Canary');
  });

  testWidgets('33 empty item submit still blocked', (tester) async {
    await fake
        .collection('lojas')
        .doc('master')
        .collection('consignment_resellers')
        .doc('rev1')
        .set({
      'storeId': 'master',
      'resellerId': 'rev1',
      'displayName': 'Maria',
      'active': true,
    });
    await pumpForm(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maria').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Enviar em consignação'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Enviar em consignação'));
    await tester.pumpAndSettle();
    expect(find.text('Adicione ao menos um produto.'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('34 no reseller submit still blocked', (tester) async {
    await pumpForm(tester, lines: threeLines());
    await tester.scrollUntilVisible(
      find.text('Enviar em consignação'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Enviar em consignação'));
    await tester.pumpAndSettle();
    expect(find.text('Selecione um revendedor.'), findsOneWidget);
    expect(calls, isEmpty);
  });
}
