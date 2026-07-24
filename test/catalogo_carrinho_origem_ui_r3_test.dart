// M2.3-R3 — origem real UI: card, detalhe, merge, restore (sem fabricar linha contaminada).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_cart_identity_trace.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_detail_screen.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_variation_pick_body.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _nomeA = 'Colar Coração Cravejado Rosa';
const _nomeB = 'Colar Ponto de Luz Gota 45cm';
const _precoA = 99.90;
const _precoB = 79.90;
const _pctPixA = 5.0;
const _pctPixB = 5.0;
const _tamA = 'coracao-rosa';
const _tamB = '45cm-v12';
const _imgA = '';
const _imgB = '';
const _lojaId = 'loja-origem-r3';

Map<String, dynamic> _produtoA() => {
      'id': 'produto-a',
      'produtosId': 'produto-a',
      'slug': 'colar-coracao-cravejado-rosa',
      'nome': _nomeA,
      'preco': _precoA,
      'quantidade': 3,
      'percentualDescontoPix': _pctPixA,
      'estoquePorTamanho': {_tamA: 3},
      'imageUrl': _imgA,
    };

Map<String, dynamic> _produtoB() => {
      'id': 'produto-b',
      'produtosId': 'produto-b',
      'slug': 'colar-ponto-luz-gota-45cm',
      'nome': _nomeB,
      'preco': _precoB,
      'quantidade': 5,
      'percentualDescontoPix': _pctPixB,
      'estoquePorTamanho': {_tamB: 5},
      'imageUrl': _imgB,
    };

void _useLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _scrollTap(WidgetTester tester, Finder finder) async {
  if (tester.any(find.byType(Scrollable))) {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void _assertLinhaB(Map<String, dynamic> line) {
  expect(line['productId'] ?? line['id'], 'produto-b');
  expect(line['nomeSnapshot'] ?? line['nome'], _nomeB);
  expect(line['tamanho'], _tamB);
  expect((line['preco'] as num?)?.toDouble(), closeTo(_precoB, 0.01));
  expect(line['imageUrl'] ?? line['imagemSnapshot'] ?? '', isEmpty);
  expect(line['nome'], isNot(contains('Coração Cravejado')));
}

bool _addToCartHarness(
  List<Map<String, dynamic>> cart,
  Map<String, dynamic> item,
) {
  final copy = Map<String, dynamic>.from(item);
  copy['quantidade'] = 1;
  final key = CatalogEstoqueHelper.cartLineIdentity(copy);
  final idx = cart.indexWhere(
    (e) => CatalogEstoqueHelper.cartLineIdentity(e) == key,
  );
  if (idx >= 0) {
    refreshCatalogCartLineFromAdd(cart[idx], copy);
    cart[idx]['quantidade'] =
        (cart[idx]['quantidade'] as int? ?? 1) + 1;
  } else {
    freezeCatalogCartLineSnapshotOnAdd(copy);
    cart.add(copy);
  }
  return true;
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final traces = <CatalogCartIdentityTraceEvent>[];
  void Function(FlutterErrorDetails details)? _prevFlutterError;

  setUp(() {
    catalogCartIdentityTraceReset();
    traces.clear();
    catalogCartIdentityTraceSubscribe(traces.add);
    SharedPreferences.setMockInitialValues({});
    _prevFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('Unable to load asset') &&
          msg.contains('placeholder.png')) {
        return;
      }
      _prevFlutterError?.call(details);
    };
  });

  tearDown(() {
    catalogCartIdentityTraceReset();
    if (_prevFlutterError != null) {
      FlutterError.onError = _prevFlutterError;
    }
  });

  group('M2.3-R3 origem UI real', () {
    testWidgets('B1 — card inline: filtro troca índice, add B coerente', (tester) async {
      _useLargeViewport(tester);
      final cart = <Map<String, dynamic>>[];

      // Mesmo contrato de item que CatalogProductCard._openSelectionModal → onAddToCart.
      Future<void> pumpPick(Map<String, dynamic> p) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CatalogProductVariationPickBody(
                productId: p['id'] as String,
                name: p['nome'] as String,
                price: (p['preco'] as num).toDouble(),
                emPromocao: false,
                imageUrl: '',
                estoquePorTamanho:
                    Map<String, int>.from(p['estoquePorTamanho'] as Map),
                estoquePorCor: const {},
                percentualDescontoPix:
                    (p['percentualDescontoPix'] as num?)?.toDouble() ?? 0,
                showProductSnippet: false,
                onPickCommit: (tamanho, cor, preco, extraValor, extraTipo) {
                  _addToCartHarness(cart, {
                    'produtosId': p['id'],
                    'id': p['id'],
                    'nome': p['nome'],
                    'preco': preco,
                    'percentualDescontoPix': p['percentualDescontoPix'] ?? 0,
                    'quantidade': 1,
                    'tamanho': tamanho ?? '',
                    'cor': cor ?? '',
                    if (extraValor.trim().isNotEmpty) 'extraValor': extraValor,
                  });
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpPick(_produtoA());
      await _scrollTap(tester, find.text(_tamA));
      // Não adiciona — troca produto (simula filtro/reordenação).

      await pumpPick(_produtoB());
      await _scrollTap(tester, find.text(_tamB));
      await tester.tap(find.text('Adicionar ao carrinho'));
      await tester.pumpAndSettle();

      expect(cart.length, 1);
      _assertLinhaB(cart.single);
    });

    testWidgets('B2 — detalhe A sem add, depois B com variação', (tester) async {
      _useLargeViewport(tester);
      final cart = <Map<String, dynamic>>[];
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Navigator(
              key: navKey,
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (_) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );

      navKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => CatalogProductDetailScreen.fromProdutoMap(
            p: _produtoA(),
            lojaId: _lojaId,
            onAdd: (it) => _addToCartHarness(cart, it),
            listaCatalogoMemoria: [_produtoA(), _produtoB()],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _scrollTap(tester, find.text(_tamA));
      navKey.currentState!.pop();
      await tester.pumpAndSettle();

      navKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => CatalogProductDetailScreen.fromProdutoMap(
            p: _produtoB(),
            lojaId: _lojaId,
            onAdd: (it) => _addToCartHarness(cart, it),
            listaCatalogoMemoria: [_produtoA(), _produtoB()],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _scrollTap(tester, find.text(_tamB));
      await _scrollTap(
        tester,
        find.widgetWithText(FilledButton, 'Adicionar ao carrinho'),
      );

      _assertLinhaB(cart.single);
    });

    testWidgets('B3 — callback tardio de seed extra não contamina B', (tester) async {
      _useLargeViewport(tester);
      final completer = Completer<void>();
      String? extraCapturado;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                var current = _produtoA();
                return Column(
                  children: [
                    TextButton(
                      onPressed: () => setState(() => current = _produtoB()),
                      child: const Text('SWITCH'),
                    ),
                    Expanded(
                      child: CatalogProductVariationPickBody(
                        productId: current['id'] as String,
                        name: current['nome'] as String,
                        price: (current['preco'] as num).toDouble(),
                        emPromocao: false,
                        imageUrl: current['imageUrl'] as String,
                        estoquePorTamanho: Map<String, int>.from(
                          current['estoquePorTamanho'] as Map,
                        ),
                        estoquePorCor: const {},
                        variacoes: {
                          _tamA: {'rosa': 2, 'extra-a': 1},
                          _tamB: {'sem-cor': 3, 'extra-b': 1},
                        },
                        variacoesExtraTipo: const {'extra-a': 'texto', 'extra-b': 'texto'},
                        initialExtraValor: 'extra-a',
                        onCatalogVariacaoExtraChanged: (v) async {
                          await completer.future;
                          extraCapturado = v;
                        },
                        onPickCommit: (_, __, ___, ____, _____) {},
                        showProductSnippet: false,
                        showAddToCartButton: true,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('SWITCH'));
      await tester.pump();
      completer.complete();
      await tester.pumpAndSettle();

      expect(extraCapturado, isNot('extra-a'));
      final state = tester.state<CatalogProductVariationPickBodyState>(
        find.byType(CatalogProductVariationPickBody),
      );
      expect(state.podeAdicionarVariacao, isFalse);
    });

    testWidgets('B4 — refresh merge não mistura A e B', (tester) async {
      final cart = <Map<String, dynamic>>[];
      final linhaA = {
        'id': 'produto-a',
        'produtosId': 'produto-a',
        'nome': _nomeA,
        'preco': _precoA,
        'quantidade': 1,
        'tamanho': _tamA,
        'cor': '',
      };
      freezeCatalogCartLineSnapshotOnAdd(linhaA);
      cart.add(linhaA);

      final incomingB = {
        'id': 'produto-b',
        'produtosId': 'produto-b',
        'nome': _nomeB,
        'preco': _precoB,
        'quantidade': 1,
        'tamanho': _tamB,
        'cor': '',
      };
      _addToCartHarness(cart, incomingB);

      expect(cart.length, 2);
      final a = cart.firstWhere((e) => e['id'] == 'produto-a');
      final b = cart.firstWhere((e) => e['id'] == 'produto-b');
      expect(a['nomeSnapshot'], _nomeA);
      expect(b['nomeSnapshot'], _nomeB);

      final mergeIncoming = {
        'id': 'produto-a',
        'nome': _nomeA,
        'preco': _precoA,
        'quantidade': 1,
        'tamanho': _tamA,
        'cor': '',
      };
      refreshCatalogCartLineFromAdd(a, mergeIncoming);
      expect(a['nomeSnapshot'], _nomeA);
      expect(b['nomeSnapshot'], _nomeB);
    });

    testWidgets('B5 — restauração local mantém A e add B independente', (tester) async {
      SharedPreferences.setMockInitialValues({
        'catalog_cart_items_$_lojaId': jsonEncode([
          {
            'id': 'produto-a',
            'productId': 'produto-a',
            'nome': _nomeA,
            'nomeSnapshot': _nomeA,
            'preco': _precoA,
            'precoUnitarioSnapshot': _precoA,
            'quantidade': 1,
            'tamanho': _tamA,
            'schemaVersion': 1,
          },
        ]),
      });

      final cart = <Map<String, dynamic>>[];
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('catalog_cart_items_$_lojaId');
      final decoded = jsonDecode(json!) as List;
      for (final e in decoded) {
        if (e is Map) cart.add(Map<String, dynamic>.from(e));
      }

      _addToCartHarness(cart, {
        'id': 'produto-b',
        'produtosId': 'produto-b',
        'nome': _nomeB,
        'preco': _precoB,
        'quantidade': 1,
        'tamanho': _tamB,
        'cor': '',
        'imageUrl': _imgB,
      });

      expect(cart.length, 2);
      final a = cart.firstWhere((e) => e['id'] == 'produto-a');
      final b = cart.firstWhere((e) => e['id'] == 'produto-b');
      expect(a['nomeSnapshot'], _nomeA);
      _assertLinhaB(b);
    });
  });
}
