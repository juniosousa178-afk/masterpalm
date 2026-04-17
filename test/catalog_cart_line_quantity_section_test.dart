// Costura pai (estado mutável em items) + CatalogCartLineQuantitySection + stepper.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_cart_line_quantity_section.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_cart_quantity_stepper.dart';

void main() {
  testWidgets(
    'linha carrinho: pai aplica delta e seção recalcula teto (trava +)',
    (tester) async {
      await tester.pumpWidget(const _PaiCarrinhoHarness());

      expect(find.text('2'), findsOneWidget);

      final botaoMais = find.ancestor(
        of: find.byIcon(Icons.add_rounded),
        matching: find.byType(IconButton),
      );
      await tester.tap(botaoMais);
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);

      final maisApos = tester.widget<IconButton>(botaoMais);
      expect(maisApos.onPressed, isNull);

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
          catalogProducts: _catalogFixo,
          index: 0,
        ),
        3,
      );
    },
  );

  testWidgets(
    'linha carrinho: decremento até 1 e remoção da linha ao zerar (costura pai)',
    (tester) async {
      await tester.pumpWidget(
        const _PaiCarrinhoHarness(
          quantidadeInicial: 3,
          removerLinhaQuandoZerar: true,
        ),
      );

      expect(find.text('3'), findsOneWidget);

      Finder botaoMenos() => find.ancestor(
        of: find.byIcon(Icons.remove_rounded),
        matching: find.byType(IconButton),
      );

      await tester.tap(botaoMenos());
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);

      await tester.tap(botaoMenos());
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      await tester.tap(botaoMenos());
      await tester.pumpAndSettle();

      expect(find.byType(CatalogCartQuantityStepper), findsNothing);
    },
  );
}

const _catalogFixo = [
  {'id': 'p1', 'nome': 'Produto teste', 'quantidade': 3, 'preco': 10.0},
];

/// Pai mínimo: aplica delta em [items]; opcionalmente remove a linha se cair abaixo de 1
/// (espelha _changeLineQuantity + remoção do CarrinhoSheetWeb).
class _PaiCarrinhoHarness extends StatefulWidget {
  const _PaiCarrinhoHarness({
    this.quantidadeInicial = 2,
    this.removerLinhaQuandoZerar = false,
  });

  final int quantidadeInicial;
  final bool removerLinhaQuandoZerar;

  @override
  State<_PaiCarrinhoHarness> createState() => _PaiCarrinhoHarnessState();
}

class _PaiCarrinhoHarnessState extends State<_PaiCarrinhoHarness> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = [
      {
        'id': 'p1',
        'nome': 'Produto teste',
        'quantidade': widget.quantidadeInicial,
        'preco': 10.0,
        'tamanho': '',
        'cor': '',
      },
    ];
  }

  Future<void> _onQuantityDelta(int index, int delta) async {
    if (index < 0 || index >= _items.length) return;
    final cur =
        CatalogEstoqueHelper.parseCartItemQuantidade(_items[index]['quantidade']);
    final next = cur + delta;
    if (next < 1) {
      if (widget.removerLinhaQuandoZerar) {
        setState(() => _items.removeAt(index));
      }
      return;
    }
    setState(() {
      _items[index]['quantidade'] = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: CatalogCartLineQuantitySection(
            items: _items,
            catalogProducts: _catalogFixo,
            lineIndex: 0,
            onQuantityDelta: _onQuantityDelta,
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
