import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/categories/category_service.dart';
import 'package:master_palm/features/categories/category_tree.dart';
import 'package:master_palm/features/categories/screens/category_tree_screen.dart';
import 'package:master_palm/features/categories/widgets/category_breadcrumb.dart';
import 'package:master_palm/features/categories/widgets/category_picker.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_category_deep_levels.dart';

import 'category_tree_test.dart' show doc, sixLevels;

const _sizes = <String, Size>{
  '360': Size(360, 740),
  '390': Size(390, 844),
  'tablet': Size(800, 1100),
  'desktop': Size(1366, 800),
};

const _longName = 'Nossa Senhora Aparecida em Prata 925 com Zircônias Cravejadas';

List<Map<String, dynamic>> _docsWithLongName() => [
      ...sixLevels().where((d) => d['id'] != 'cat_ns'),
      doc('cat_ns', _longName, parentId: 'cat_ane'),
    ];

Future<void> _setSize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _pumpTreeScreen(WidgetTester tester, {List<Map<String, dynamic>>? docs}) async {
  CategoryService.debugLoadDocs = (loja) async => docs ?? _docsWithLongName();
  await tester.pumpWidget(MaterialApp(
    home: CategoryTreeScreen(
      lojaId: 'mirjoias',
      productRefsLoader: () async => const [
        CategoryProductRef(pathIds: ['cat_fem', 'cat_rel', 'cat_ane']),
      ],
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _expandAll(WidgetTester tester) async {
  for (final id in ['cat_fem', 'cat_rel', 'cat_ane', 'cat_ns', 'cat_p925']) {
    final f = find.byKey(ValueKey('category_expand_$id'));
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }
}

void main() {
  tearDown(CategoryService.debugReset);

  for (final entry in _sizes.entries) {
    testWidgets('árvore com 6 níveis em ${entry.key}: recuo por nível, sem overflow nem texto cortado',
        (tester) async {
      await _setSize(tester, entry.value);
      await _pumpTreeScreen(tester);
      expect(find.byKey(const ValueKey('category_row_cat_rel')), findsNothing);
      await _expandAll(tester);
      final leaf = find.byKey(const ValueKey('category_row_cat_crav'));
      await tester.ensureVisible(leaf);
      expect(leaf, findsOneWidget);
      expect(tester.takeException(), isNull);

      final fem = tester.getTopLeft(find.byKey(const ValueKey('category_name_cat_fem')));
      final rel = tester.getTopLeft(find.byKey(const ValueKey('category_name_cat_rel')));
      expect(rel.dx, greaterThan(fem.dx));

      final longText = tester.widget<Text>(find.byKey(const ValueKey('category_name_cat_ns')));
      expect(longText.data, _longName);
      expect(longText.overflow, isNot(TextOverflow.ellipsis));
      expect(longText.maxLines, isNull);
      final box = tester.renderObject<RenderBox>(find.byKey(const ValueKey('category_name_cat_ns')));
      expect(box.size.width, lessThanOrEqualTo(entry.value.width));
    });
  }

  testWidgets('Adicionar subcategoria: diálogo "Nova subcategoria de: Anéis" com caminho e nível', (tester) async {
    await _setSize(tester, const Size(390, 844));
    final calls = <Map<String, dynamic>>[];
    CategoryService.debugTransport = (data) async {
      calls.add(data);
      return {'ok': true};
    };
    await _pumpTreeScreen(tester, docs: sixLevels());
    for (final id in ['cat_fem', 'cat_rel']) {
      await tester.tap(find.byKey(ValueKey('category_expand_$id')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('category_menu_cat_ane')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar subcategoria'));
    await tester.pumpAndSettle();
    expect(find.text('Nova subcategoria de:'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('category_dialog_parent'))).data, 'Anéis');
    final path = find.byKey(const ValueKey('category_dialog_path'));
    expect(find.descendant(of: path, matching: find.text('Feminino')), findsOneWidget);
    expect(find.descendant(of: path, matching: find.text('Religioso')), findsOneWidget);
    expect(find.descendant(of: path, matching: find.text('+')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('category_dialog_level'))).data, 'Nível 4 de 6');
    await tester.enterText(find.byKey(const ValueKey('category_name_field')), 'Nossa Senhora de Fátima');
    await tester.tap(find.byKey(const ValueKey('category_dialog_save')));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(calls.single['payload'], {
      'parent': {'id': 'cat_ane'},
      'nome': 'Nossa Senhora de Fátima',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('N6: menu mostra "Limite de 6 níveis" desabilitado e não chama o servidor', (tester) async {
    await _setSize(tester, const Size(360, 740));
    var calls = 0;
    CategoryService.debugTransport = (data) async {
      calls++;
      return {'ok': true};
    };
    await _pumpTreeScreen(tester, docs: sixLevels());
    await _expandAll(tester);
    final menu = find.byKey(const ValueKey('category_menu_cat_crav'));
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Limite de 6 níveis'), findsOneWidget);
    expect(find.text('Adicionar subcategoria'), findsNothing);
    final item = tester.widget<PopupMenuItem<String>>(
        find.ancestor(of: find.text('Limite de 6 níveis'), matching: find.byType(PopupMenuItem<String>)));
    expect(item.enabled, isFalse);
    await tester.tap(find.text('Limite de 6 níveis'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Nova subcategoria de:'), findsNothing);
    expect(calls, 0);
  });

  testWidgets('excluir categoria com subcategorias mostra o bloqueio', (tester) async {
    await _setSize(tester, const Size(390, 844));
    var calls = 0;
    CategoryService.debugTransport = (data) async {
      calls++;
      return {'ok': true};
    };
    await _pumpTreeScreen(tester, docs: sixLevels());
    await tester.tap(find.byKey(const ValueKey('category_menu_cat_fem')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir/Arquivar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('category_blocked_dialog')), findsOneWidget);
    expect(find.text('Esta categoria possui subcategorias.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('busca "anel" mostra Anéis com o caminho completo', (tester) async {
    await _setSize(tester, const Size(360, 740));
    await _pumpTreeScreen(tester, docs: sixLevels());
    await tester.enterText(find.byKey(const ValueKey('category_search')), 'anel');
    await tester.pumpAndSettle();
    final result = find.byKey(const ValueKey('category_search_result_cat_ane'));
    expect(result, findsOneWidget);
    expect(find.descendant(of: result, matching: find.text('Feminino > Religioso > Anéis')), findsOneWidget);
    await tester.tap(result);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('category_row_cat_ane')), findsOneWidget);
  });

  testWidgets('seletor do produto navega a árvore e devolve a folha', (tester) async {
    await _setSize(tester, const Size(360, 740));
    final tree = CategoryTree.build(lojaId: 'mirjoias', docs: sixLevels());
    CategoryPickResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => result = await showCategoryPicker(context, tree: tree),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category_picker_item_cat_fem')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category_picker_item_cat_rel')));
    await tester.pumpAndSettle();
    final crumb = find.byKey(const ValueKey('category_picker_breadcrumb'));
    expect(find.descendant(of: crumb, matching: find.text('Início')), findsOneWidget);
    expect(find.descendant(of: crumb, matching: find.text('Religioso')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('category_picker_item_cat_ane')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category_picker_use_current')));
    await tester.pumpAndSettle();
    expect(result?.node?.id, 'cat_ane');
    expect(result?.node?.pathNames, ['Feminino', 'Religioso', 'Anéis']);
    expect(tester.takeException(), isNull);
  });

  for (final entry in _sizes.entries) {
    testWidgets('breadcrumb do catálogo quebra linha em ${entry.key} (sem corte)', (tester) async {
      await _setSize(tester, entry.value);
      int? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CategoryBreadcrumb(
            names: const ['Feminino', 'Religioso', 'Anéis', _longName, 'Prata 925', 'Cravejados'],
            onTapLevel: (l) => tapped = l,
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Início'), findsOneWidget);
      expect(find.text(_longName), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('category_breadcrumb_1')));
      expect(tapped, 1);
      await tester.tap(find.byKey(const ValueKey('category_breadcrumb_-1')));
      expect(tapped, -1);
      expect(find.byKey(const ValueKey('category_breadcrumb_5')), findsNothing);
    });

    testWidgets('chips dos níveis 3–6 do catálogo em ${entry.key}', (tester) async {
      await _setSize(tester, entry.value);
      final picks = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CatalogCategoryDeepLevels(
            parentNames: const ['Religioso', 'Anéis'],
            levels: const [
              ['Anéis', 'Brincos', 'Colares', 'Pulseiras', 'Tornozeleiras'],
              [_longName, 'São Bento'],
            ],
            selected: const ['Anéis'],
            onSelect: (level, name) => picks.add('$level:${name ?? '*'}'),
            textColor: Colors.black,
            primaryColor: Colors.purple,
            surfaceColor: Colors.white,
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Todas em Religioso'), findsOneWidget);
      expect(find.text(_longName), findsOneWidget);
      final chip = tester.widget<ChoiceChip>(
          find.byKey(const ValueKey('catalog_category_level_0_Anéis')));
      expect(chip.selected, isTrue);
      await tester.tap(find.text('São Bento'));
      await tester.tap(find.text('Todas em Religioso'));
      expect(picks, ['1:São Bento', '0:*']);
    });
  }
}
