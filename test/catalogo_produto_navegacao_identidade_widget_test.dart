// M2.3-R2 — navegação real UI catálogo → detalhe → add-to-cart → freeze.
// Não fabrica linha contaminada manualmente.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_cart_identity_trace.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_detail_screen.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_variation_pick_body.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

const _nomeA = 'Colar Coração Cravejado Rosa';
const _nomeB = 'Colar Ponto de Luz Gota 45cm';
const _precoB = 79.90;
const _pctPixB = 5.0;
const _precoPixB = 75.91;
const _tamA = 'coracao-rosa';
const _tamB = 'gota-45cm';
const _tamAmbiguo = '45cm v12';
const _lojaId = 'loja-widget-ident-r2';

Map<String, dynamic> _produtoA({String tam = _tamA}) => {
      'id': 'produto-a',
      'produtosId': 'produto-a',
      'slug': 'colar-coracao-cravejado-rosa',
      'nome': _nomeA,
      'preco': 120.0,
      'quantidade': 3,
      'percentualDescontoPix': 0.0,
      'estoquePorTamanho': {tam: 3},
      'imageUrl': '',
    };

Map<String, dynamic> _produtoB({String tam = _tamB}) => {
      'id': 'produto-b',
      'produtosId': 'produto-b',
      'slug': 'colar-ponto-luz-gota-45cm',
      'nome': _nomeB,
      'preco': _precoB,
      'quantidade': 5,
      'percentualDescontoPix': _pctPixB,
      'estoquePorTamanho': {tam: 5},
      'imageUrl': '',
    };

void _assertLinhaCoerente(
  Map<String, dynamic> line, {
  required String produtoId,
  required String nome,
  required String tamanho,
  double? preco,
}) {
  expect(line['productId'] ?? line['id'], produtoId, reason: 'productId');
  expect(line['nomeSnapshot'] ?? line['nome'], nome, reason: 'nome');
  expect(line['tamanho'], tamanho, reason: 'tamanho');
  if (preco != null) {
    expect((line['preco'] as num?)?.toDouble(), closeTo(preco, 0.01));
  }
  if (nome != _nomeA) {
    expect(line['nome'], isNot(contains('Coração Cravejado')));
  }
}

void _useLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _scrollToVisible(WidgetTester tester, Finder finder) async {
  if (tester.any(find.byType(Scrollable))) {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _tapTamanho(WidgetTester tester, String tam) async {
  final finder = find.text(tam);
  await _scrollToVisible(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapAdicionarPrincipal(WidgetTester tester) async {
  final finder = find.widgetWithText(FilledButton, 'Adicionar ao carrinho');
  await _scrollToVisible(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _NavHarness extends StatefulWidget {
  const _NavHarness({
    required this.catalog,
    required this.onCartChanged,
    this.sharedExtra,
    this.onExtraChanged,
    this.detailKey,
  });

  final List<Map<String, dynamic>> catalog;
  final void Function(List<Map<String, dynamic>> cart) onCartChanged;
  final String? sharedExtra;
  final void Function(String? value)? onExtraChanged;
  final Key? detailKey;

  @override
  State<_NavHarness> createState() => _NavHarnessState();
}

class _NavHarnessState extends State<_NavHarness> {
  final _navKey = GlobalKey<NavigatorState>();
  final List<Map<String, dynamic>> _cart = [];

  bool _addToCart(Map<String, dynamic> item) {
    final copy = Map<String, dynamic>.from(item);
    copy['quantidade'] = 1;
    freezeCatalogCartLineSnapshotOnAdd(copy);
    _cart.add(copy);
    widget.onCartChanged(List.unmodifiable(_cart));
    return true;
  }

  void openProduct(Map<String, dynamic> p) {
    _navKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => KeyedSubtree(
          key: widget.detailKey,
          child: CatalogProductDetailScreen.fromProdutoMap(
            p: p,
            lojaId: _lojaId,
            onAdd: _addToCart,
            initialCatalogExtraValor: widget.sharedExtra,
            onCatalogVariacaoExtraChanged: widget.onExtraChanged,
            listaCatalogoMemoria: widget.catalog,
          ),
        ),
      ),
    );
  }

  void popDetail() => _navKey.currentState?.pop();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Navigator(
          key: _navKey,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final catalog = [_produtoA(), _produtoB()];
  final traces = <CatalogCartIdentityTraceEvent>[];

  setUp(() {
    catalogCartIdentityTraceReset();
    traces.clear();
    catalogCartIdentityTraceSubscribe(traces.add);
  });

  tearDown(catalogCartIdentityTraceReset);

  Future<void> pumpHarness(
    WidgetTester tester, {
    required void Function(_NavHarnessState harness) setup,
    String? sharedExtra,
    Key? detailKey,
  }) async {
    late _NavHarnessState harnessState;
    await tester.pumpWidget(
      _NavHarness(
        catalog: catalog,
        sharedExtra: sharedExtra,
        detailKey: detailKey,
        onCartChanged: (_) {},
        onExtraChanged: (_) {},
      ),
    );
    harnessState = tester.state(find.byType(_NavHarness)) as _NavHarnessState;
    setup(harnessState);
    await tester.pumpAndSettle();
  }

  group('M2.3-R2 navegação UI real', () {
    testWidgets('C1 navegação comum A→B adiciona só B coerente', (tester) async {
      _useLargeViewport(tester);
      final cart = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        _NavHarness(
          catalog: catalog,
          onCartChanged: (c) => cart..clear()..addAll(c),
          onExtraChanged: (_) {},
        ),
      );
      final harness = tester.state(find.byType(_NavHarness)) as _NavHarnessState;

      harness.openProduct(_produtoA());
      await tester.pumpAndSettle();
      await _tapTamanho(tester, _tamA);
      harness.popDetail();
      await tester.pumpAndSettle();

      harness.openProduct(_produtoB());
      await tester.pumpAndSettle();
      await _tapTamanho(tester, _tamB);
      await _tapAdicionarPrincipal(tester);

      expect(cart.length, 1);
      _assertLinhaCoerente(
        cart.single,
        produtoId: 'produto-b',
        nome: _nomeB,
        tamanho: _tamB,
        preco: _precoB,
      );
    });

    testWidgets('C2 abre A, seleciona tam, não adiciona, depois B', (tester) async {
      _useLargeViewport(tester);
      final cart = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        _NavHarness(
          catalog: catalog,
          onCartChanged: (c) => cart..clear()..addAll(c),
          onExtraChanged: (_) {},
        ),
      );
      final harness = tester.state(find.byType(_NavHarness)) as _NavHarnessState;

      harness.openProduct(_produtoA());
      await tester.pumpAndSettle();
      await _tapTamanho(tester, _tamA);
      harness.popDetail();
      await tester.pumpAndSettle();

      harness.openProduct(_produtoB());
      await tester.pumpAndSettle();
      await _tapTamanho(tester, _tamB);
      await _tapAdicionarPrincipal(tester);

      expect(cart.single['productId'], 'produto-b');
      expect(cart.single['nomeSnapshot'], _nomeB);
      expect(cart.single['tamanho'], _tamB);
    });

    testWidgets('C3 navegação rápida sem esperar settle completo em A', (tester) async {
      _useLargeViewport(tester);
      final cart = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        _NavHarness(
          catalog: catalog,
          onCartChanged: (c) => cart..clear()..addAll(c),
          onExtraChanged: (_) {},
        ),
      );
      final harness = tester.state(find.byType(_NavHarness)) as _NavHarnessState;

      harness.openProduct(_produtoA());
      await tester.pump();
      await _tapTamanho(tester, _tamA);
      await tester.pump(const Duration(milliseconds: 50));
      harness.popDetail();
      await tester.pump();

      harness.openProduct(_produtoB());
      await tester.pumpAndSettle();
      await _tapTamanho(tester, _tamB);
      await _tapAdicionarPrincipal(tester);

      _assertLinhaCoerente(
        cart.single,
        produtoId: 'produto-b',
        nome: _nomeB,
        tamanho: _tamB,
        preco: _precoB,
      );
    });

    testWidgets('C4 lista/filtro — produto B no mesmo índice após filtro', (tester) async {
      _useLargeViewport(tester);
      final cart = <Map<String, dynamic>>[];
      final mutableCatalog = [_produtoA(), _produtoB()];

      await tester.pumpWidget(
        MaterialApp(
          home: _CatalogGridHarness(
            products: mutableCatalog,
            onCart: (c) => cart..clear()..addAll(c),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Abre produto no índice 0 (A).
      await tester.tap(find.byKey(const ValueKey('grid-index-0')));
      await tester.pumpAndSettle();
      await _tapTamanho(tester, _tamA);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
      nav.pop();
      await tester.pumpAndSettle();

      // Simula filtro: remove A, B passa a índice 0.
      mutableCatalog.removeAt(0);
      await tester.pumpWidget(
        MaterialApp(
          home: _CatalogGridHarness(
            products: List<Map<String, dynamic>>.from(mutableCatalog),
            onCart: (c) => cart..clear()..addAll(c),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('grid-index-0')));
      await tester.pumpAndSettle();
      await _tapTamanho(tester, _tamB);
      await _tapAdicionarPrincipal(tester);

      _assertLinhaCoerente(
        cart.single,
        produtoId: 'produto-b',
        nome: _nomeB,
        tamanho: _tamB,
        preco: _precoB,
      );
    });

    testWidgets('C5 detalhe reutilizado — mesma Key, troca A→B sem reset pick', (tester) async {
      _useLargeViewport(tester);
      final cart = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: _ReuseDetailHarness(
            onCart: (c) => cart..clear()..addAll(c),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _tapTamanho(tester, _tamA);
      await tester.tap(find.text('SWITCH_TO_B'));
      await tester.pumpAndSettle();

      final pickState = tester.state<CatalogProductVariationPickBodyState>(
        find.byType(CatalogProductVariationPickBody),
      );
      expect(pickState.podeAdicionarVariacao, isFalse);

      await _tapTamanho(tester, _tamB);
      await _tapAdicionarPrincipal(tester);

      _assertLinhaCoerente(
        cart.single,
        produtoId: 'produto-b',
        nome: _nomeB,
        tamanho: _tamB,
        preco: _precoB,
      );
    });

    testWidgets('C6 tamanhos ambíguos iguais — rótulo compartilhado', (tester) async {
      _useLargeViewport(tester);
      final cart = <Map<String, dynamic>>[];
      final a = _produtoA(tam: _tamAmbiguo);
      final b = _produtoB(tam: _tamAmbiguo);
      await tester.pumpWidget(
        _NavHarness(
          catalog: [a, b],
          onCartChanged: (c) => cart..clear()..addAll(c),
          onExtraChanged: (_) {},
        ),
      );
      final harness = tester.state(find.byType(_NavHarness)) as _NavHarnessState;

      harness.openProduct(a);
      await tester.pumpAndSettle();
      await _tapTamanho(tester, _tamAmbiguo);
      harness.popDetail();
      await tester.pumpAndSettle();

      harness.openProduct(b);
      await tester.pumpAndSettle();
      await _tapTamanho(tester, _tamAmbiguo);
      await _tapAdicionarPrincipal(tester);

      _assertLinhaCoerente(
        cart.single,
        produtoId: 'produto-b',
        nome: _nomeB,
        tamanho: _tamAmbiguo,
        preco: _precoB,
      );
    });

    testWidgets('C7 pop navegador e reabertura de B', (tester) async {
      _useLargeViewport(tester);
      final cart = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        _NavHarness(
          catalog: catalog,
          onCartChanged: (c) => cart..clear()..addAll(c),
          onExtraChanged: (_) {},
        ),
      );
      final harness = tester.state(find.byType(_NavHarness)) as _NavHarnessState;

      harness.openProduct(_produtoA());
      await tester.pumpAndSettle();
      harness.popDetail();
      await tester.pumpAndSettle();

      harness.openProduct(_produtoB());
      await tester.pumpAndSettle();
      await _tapTamanho(tester, _tamB);
      await _tapAdicionarPrincipal(tester);

      _assertLinhaCoerente(
        cart.single,
        produtoId: 'produto-b',
        nome: _nomeB,
        tamanho: _tamB,
        preco: _precoB,
      );
    });
  });
}

/// Grid mínima: abre detalhe por índice (simula risco de key por posição).
class _CatalogGridHarness extends StatelessWidget {
  const _CatalogGridHarness({
    required this.products,
    required this.onCart,
  });

  final List<Map<String, dynamic>> products;
  final void Function(List<Map<String, dynamic>> cart) onCart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: products.length,
        itemBuilder: (context, index) {
          final p = products[index];
          return ListTile(
            key: ValueKey('grid-index-$index'),
            title: Text('${p['nome']}'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CatalogProductDetailScreen.fromProdutoMap(
                    p: p,
                    lojaId: _lojaId,
                    onAdd: (item) {
                      final copy = Map<String, dynamic>.from(item);
                      copy['quantidade'] = 1;
                      freezeCatalogCartLineSnapshotOnAdd(copy);
                      onCart([copy]);
                      return true;
                    },
                    listaCatalogoMemoria: products,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Força reutilização de State do detalhe (mesma Key estável).
class _ReuseDetailHarness extends StatefulWidget {
  const _ReuseDetailHarness({required this.onCart});

  final void Function(List<Map<String, dynamic>> cart) onCart;

  @override
  State<_ReuseDetailHarness> createState() => _ReuseDetailHarnessState();
}

class _ReuseDetailHarnessState extends State<_ReuseDetailHarness> {
  Map<String, dynamic> _current = _produtoA();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () => setState(() => _current = _produtoB()),
            child: const Text('SWITCH_TO_B'),
          ),
          Expanded(
            child: KeyedSubtree(
              key: const ValueKey('stable-detail'),
              child: CatalogProductDetailScreen.fromProdutoMap(
              p: _current,
              lojaId: _lojaId,
              onAdd: (item) {
                final copy = Map<String, dynamic>.from(item);
                copy['quantidade'] = 1;
                freezeCatalogCartLineSnapshotOnAdd(copy);
                widget.onCart([copy]);
                return true;
              },
              listaCatalogoMemoria: [_produtoA(), _produtoB()],
            ),
            ),
          ),
        ],
      ),
    );
  }
}
