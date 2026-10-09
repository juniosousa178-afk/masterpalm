import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_feature_flag.dart';
import 'package:master_palm/features/consignments/consignment_service.dart';
import 'package:master_palm/features/consignments/screens/consignment_list_screen.dart';
import 'package:master_palm/features/consignments/screens/consignment_reseller_history_screen.dart';
import 'package:master_palm/themes/masterpalm_app_theme.dart';

const _sizes = {
  'desktop': Size(1366, 900),
  'tablet': Size(800, 1100),
  'mobile390': Size(390, 844),
  'mobile360': Size(360, 760),
};

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  late FakeFirebaseFirestore fake;

  Map<String, dynamic> raw(String reseller, String name, String status, int day) => {
        'storeId': 'mirjoias',
        'resellerId': reseller,
        'resellerSnapshot': {'displayName': name},
        'status': status,
        'lines': [
          {
            'productId': 'pa',
            'productNameSnapshot': 'Colar A',
            'qtySent': 2,
            'qtySold': 0,
            'qtyReturned': 0,
            'unitSalePriceSnapshot': 100,
            'commissionType': 'PERCENTUAL',
            'commissionValueSnapshot': 20,
            'variationKey': {'size': '', 'color': '', 'extra': ''},
          },
        ],
        'totalItemsSent': 2,
        'issuedAt': DateTime(2026, 9, day),
        'createdAt': DateTime(2026, 9, day),
      };

  setUp(() async {
    fake = FakeFirebaseFirestore();
    await fake
        .collection('lojas')
        .doc('mirjoias')
        .collection('consignment_control')
        .doc('state')
        .set({'moduleEnabled': true, 'protocolVersion': 1});
    final col = fake.collection('lojas').doc('mirjoias').collection('consignments');
    await col.doc('m1').set(raw('r1', 'Maria', 'ISSUED', 1));
    await col.doc('m2').set(raw('r1', 'Maria', 'SETTLED', 2));
    await col.doc('o1').set(raw('r2', 'Ana', 'ISSUED', 3));
    ConsignmentFeatureFlag.debugFirestore = fake;
    ConsignmentService.debugFirestore = fake;
    ConsignmentListScreen.debugLojaId = () async => 'mirjoias';
  });

  tearDown(() {
    ConsignmentFeatureFlag.debugFirestore = null;
    ConsignmentService.debugFirestore = null;
    ConsignmentListScreen.debugLojaId = null;
  });

  Future<void> pushWithAppTheme(WidgetTester tester, Size size, Widget screen) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      theme: masterPalmLightTheme(),
      home: const Scaffold(body: SizedBox()),
    ));
    nav.currentState!.push(MaterialPageRoute(builder: (_) => screen));
    await tester.pumpAndSettle();
  }

  void expectSelectVisible(WidgetTester tester, Size size) {
    final label = find.text('Selecionar');
    expect(label.hitTestable(), findsOneWidget);
    final rect = tester.getRect(label);
    final bar = tester.getRect(find.byType(AppBar));
    expect(rect.left >= 0 && rect.right <= size.width, isTrue, reason: 'inside viewport $rect');
    expect(bar.contains(rect.center), isTrue, reason: 'inside AppBar');
    final barColor = tester
        .widget<Material>(find.descendant(of: find.byType(AppBar), matching: find.byType(Material)).first)
        .color!;
    final textColor = tester
        .widget<RichText>(find.descendant(of: label, matching: find.byType(RichText)))
        .text
        .style!
        .color!;
    final iconColor = tester
        .widget<RichText>(find.descendant(
            of: find.descendant(of: find.byKey(const Key('consignment_select_mode')), matching: find.byType(Icon)),
            matching: find.byType(RichText)))
        .text
        .style!
        .color!;
    expect(_contrast(textColor, barColor), greaterThanOrEqualTo(4.5),
        reason: 'label $textColor on AppBar $barColor');
    expect(_contrast(iconColor, barColor), greaterThanOrEqualTo(3),
        reason: 'icon $iconColor on AppBar $barColor');
    expect(tester.takeException(), isNull);
  }

  for (final entry in _sizes.entries) {
    testWidgets('list: Selecionar visible with app theme (${entry.key}) and prints 2 same-customer',
        (tester) async {
      await pushWithAppTheme(tester, entry.value, const ConsignmentListScreen());
      expect(find.text('Consignados'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expectSelectVisible(tester, entry.value);

      await tester.tap(find.text('Selecionar'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNWidgets(3));
      FilledButton printButton() =>
          tester.widget<FilledButton>(find.byKey(const Key('consignment_print_selected')));
      expect(printButton().onPressed, isNull);
      for (final id in ['m1', 'm2']) {
        final box = find.byKey(Key('consignment_select_$id'));
        await tester.ensureVisible(box);
        await tester.pumpAndSettle();
        await tester.tap(box);
        await tester.pumpAndSettle();
      }
      expect(find.text('2 selecionadas'), findsOneWidget);
      expect(find.text('Imprimir selecionadas'), findsOneWidget);
      expect(printButton().onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reseller history: Selecionar visible with app theme (${entry.key})', (tester) async {
      await pushWithAppTheme(tester, entry.value, const ConsignmentResellerHistoryScreen(lojaId: 'mirjoias'));
      expectSelectVisible(tester, entry.value);
      await tester.tap(find.text('Selecionar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('consignment_print_selected')), findsOneWidget);
    });
  }
}
