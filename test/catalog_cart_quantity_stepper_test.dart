// Widget smoke: mesmo stepper e mesmo teto de estoque usados pelo CarrinhoSheetWeb.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_cart_quantity_stepper.dart';

void main() {
  testWidgets(
    'carrinho catálogo: incremento respeita estoque (trava + na borda)',
    (tester) async {
      await tester.pumpWidget(const _CarrinhoQtyHarness());

      expect(find.text('2'), findsOneWidget);

      final botaoMais = find.ancestor(
        of: find.byIcon(Icons.add_rounded),
        matching: find.byType(IconButton),
      );
      expect(botaoMais, findsOneWidget);

      await tester.tap(botaoMais);
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);

      final aumentar = tester.widget<IconButton>(botaoMais);
      expect(
        aumentar.onPressed,
        isNull,
        reason: 'no teto de estoque o + deve ficar desabilitado',
      );

      // Estado interno permanece em 3 (sem ultrapassar estoque).
      expect(
        CatalogEstoqueHelper.maxOrderableForCartLine(
          items: const [
            {
              'id': 'p1',
              'nome': 'Produto teste',
              'quantidade': 3,
              'preco': 10.0,
              'tamanho': '',
              'cor': '',
            },
          ],
          catalogProducts: _harnessCatalog,
          index: 0,
        ),
        3,
      );
    },
  );
}

const _harnessCatalog = [
  {'id': 'p1', 'nome': 'Produto teste', 'quantidade': 3, 'preco': 10.0},
];

/// Réplica mínima da costura qty / maxQ / [CatalogCartQuantityStepper] do sheet.
class _CarrinhoQtyHarness extends StatefulWidget {
  const _CarrinhoQtyHarness();

  @override
  State<_CarrinhoQtyHarness> createState() => _CarrinhoQtyHarnessState();
}

class _CarrinhoQtyHarnessState extends State<_CarrinhoQtyHarness> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = [
      {
        'id': 'p1',
        'nome': 'Produto teste',
        'quantidade': 2,
        'preco': 10.0,
        'tamanho': '',
        'cor': '',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final qty =
        CatalogEstoqueHelper.parseCartItemQuantidade(_items[0]['quantidade']);
    final maxQ = CatalogEstoqueHelper.maxOrderableForCartLine(
      items: _items,
      catalogProducts: _harnessCatalog,
      index: 0,
    );
    final canInc = qty < maxQ;

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: CatalogCartQuantityStepper(
            quantity: qty,
            canIncrement: canInc,
            onDecrement: () {
              final next = qty - 1;
              if (next >= 1) {
                setState(() => _items[0]['quantidade'] = next);
              }
            },
            onIncrement: () {
              setState(() => _items[0]['quantidade'] = qty + 1);
            },
            primaryTextColor: const Color(0xFF111827),
            mutedTextColor: const Color(0xFF9CA3AF),
            inputBorderColor: const Color(0xFFD1D5DB),
            inputBackground: Colors.white,
          ),
        ),
      ),
    );
  }
}
