import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/consignments/consignment_feature_flag.dart';
import 'package:master_palm/features/consignments/consignment_service.dart';
import 'package:master_palm/features/consignments/reports/widgets/consignment_combined_print_bar.dart';
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

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

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
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  tearDown(() {
    ConsignmentFeatureFlag.debugFirestore = null;
    ConsignmentService.debugFirestore = null;
    ConsignmentListScreen.debugLojaId = null;
    WidgetController.hitTestWarningShouldBeFatal = false;
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
    debugPrint('SELECT_MEASURE width=${size.width.toInt()} fg=${_hex(textColor)} '
        'icon=${_hex(iconColor)} appBar=${_hex(barColor)} '
        'contrast=${_contrast(textColor, barColor).toStringAsFixed(2)}');
    expect(_contrast(textColor, barColor), greaterThanOrEqualTo(4.5),
        reason: 'label $textColor on AppBar $barColor');
    expect(_contrast(iconColor, barColor), greaterThanOrEqualTo(3),
        reason: 'icon $iconColor on AppBar $barColor');
    expect(tester.takeException(), isNull);
  }

  void expectPrintBarLayout(WidgetTester tester, Size size, String statusText) {
    final bar = find.byType(ConsignmentCombinedPrintBar);
    final barRect = tester.getRect(bar);
    final status = find.descendant(of: bar, matching: find.text(statusText));
    final button = find.byKey(const Key('consignment_print_selected'));
    final statusRect = tester.getRect(status);
    final buttonRect = tester.getRect(button);
    final fontSize = tester
            .widget<RichText>(find.descendant(of: status, matching: find.byType(RichText)))
            .text
            .style
            ?.fontSize ??
        14;
    expect(statusRect.height, lessThanOrEqualTo(fontSize * 3), reason: 'status at most 2 lines: $statusRect');
    expect(barRect.height, lessThanOrEqualTo(size.height * 0.25), reason: 'bar must not cover the list: $barRect');
    expect(button.hitTestable(), findsOneWidget);
    if (size.width < 480) {
      expect(statusRect.bottom, lessThanOrEqualTo(buttonRect.top), reason: 'text on top of button');
      expect(buttonRect.width, closeTo(size.width - 32, 1), reason: 'full-width button');
    } else {
      expect(statusRect.right, lessThanOrEqualTo(buttonRect.left), reason: 'wide: text beside button');
      expect((statusRect.center.dy - buttonRect.center.dy).abs(), lessThan(4), reason: 'wide: single row');
    }
    expect(tester.takeException(), isNull);
  }

  Future<void> selectBoth(WidgetTester tester) async {
    for (final id in ['m1', 'm2']) {
      final box = find.byKey(Key('consignment_select_$id'));
      await tester.ensureVisible(box);
      await tester.pumpAndSettle();
      expect(box.hitTestable(), findsOneWidget);
      await tester.tap(box);
      await tester.pumpAndSettle();
    }
  }

  FilledButton printButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('consignment_print_selected')));

  for (final entry in _sizes.entries) {
    final size = entry.value;

    testWidgets('list: Selecionar visible with app theme (${entry.key}) and prints 2 same-customer',
        (tester) async {
      await pushWithAppTheme(tester, size, const ConsignmentListScreen());
      expect(find.text('Consignados'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expectSelectVisible(tester, size);

      await tester.tap(find.text('Selecionar'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNWidgets(3));
      expect(printButton(tester).onPressed, isNull);
      expectPrintBarLayout(tester, size, 'Selecione 2 ou mais consignações da mesma cliente.');

      await selectBoth(tester);
      expect(find.text('Imprimir selecionadas'), findsOneWidget);
      expect(printButton(tester).onPressed, isNotNull);
      expectPrintBarLayout(tester, size, '2 selecionadas');
    });

    testWidgets('reseller history: Selecionar visible with app theme (${entry.key}) and prints 2 same-customer',
        (tester) async {
      await pushWithAppTheme(tester, size, const ConsignmentResellerHistoryScreen(lojaId: 'mirjoias'));
      expect(find.byType(Checkbox), findsNothing);
      expectSelectVisible(tester, size);

      await tester.tap(find.text('Selecionar'));
      await tester.pumpAndSettle();
      expect(printButton(tester).onPressed, isNull);
      expectPrintBarLayout(tester, size, 'Selecione 2 ou mais consignações da mesma cliente.');
      await tester.tap(find.text('Maria'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNWidgets(2));

      await selectBoth(tester);
      expect(printButton(tester).onPressed, isNotNull);
      expectPrintBarLayout(tester, size, '2 selecionadas');
    });
  }
}
