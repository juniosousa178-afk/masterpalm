// M2.3-R6 — corrida modal/card bidirecional, trace pré-fix, alcançabilidade produtiva.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_product_add_seed.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_card.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_selection_sheet.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

// Papéis imutáveis do incidente (R6).
const _nomeA = 'Colar Coração Cravejado Rosa';
const _nomeB = 'Colar Ponto de Luz Gota 45cm';
const _precoB = 79.90;
const _precoPixB = 75.91;
const _precoA = 99.90;
const _tamA = 'variacao-a';
const _corA = 'cor-a';
const _tamB = 'variacao-b';
const _corB = 'cor-b';
const _imgA = 'imagem-a';
const _imgB = 'imagem-b';
const _slugA = 'colar-coracao-rosa';
const _slugB = 'colar-ponto-luz-gota';
const _lojaId = 'loja-r6-race';

Map<String, dynamic> _produtoA() => {
      'id': 'produto-a',
      'nome': _nomeA,
      'preco': _precoA,
      'slug': _slugA,
      'estoquePorTamanho': {_tamA: 3},
      'estoquePorCor': const <String, int>{},
      'imageUrl': _imgA,
      'imagens': [_imgA],
      'percentualDescontoPix': 0.0,
    };

Map<String, dynamic> _produtoB() => {
      'id': 'produto-b',
      'nome': _nomeB,
      'preco': _precoB,
      'slug': _slugB,
      'estoquePorTamanho': {_tamB: 5},
      'estoquePorCor': const <String, int>{},
      'imageUrl': _imgB,
      'imagens': [_imgB],
      'percentualDescontoPix': 5.0,
    };

bool _isExactClientTuple(Map<String, dynamic> line) {
  final pid = (line['productId'] ?? line['id'] ?? '').toString();
  final nome = (line['nomeSnapshot'] ?? line['nome'] ?? '').toString();
  final preco = (line['precoUnitarioSnapshot'] ?? line['preco'] as num?)?.toDouble();
  final tam = (line['tamanho'] ?? '').toString();
  final cor = (line['cor'] ?? '').toString();
  final precoBMatch = preco != null &&
      (preco - _precoB).abs() < 0.02;
  return pid == 'produto-b' &&
      nome == _nomeA &&
      precoBMatch &&
      tam == _tamA &&
      cor == _corA;
}

Map<String, dynamic> _traceTuple(
  String stage, {
  required Map<String, dynamic>? line,
  String? widgetProductId,
  String? openedProductId,
  String? capturedProductId,
}) {
  final l = line ?? const <String, dynamic>{};
  return {
    'stage': stage,
    'productId': (l['productId'] ?? l['id'] ?? widgetProductId ?? '').toString(),
    'nome': (l['nomeSnapshot'] ?? l['nome'] ?? '').toString(),
    'preco': (l['precoUnitarioSnapshot'] ?? l['preco'])?.toString() ?? '',
    'precoPix': (l['precoPixSnapshot'] ?? '').toString(),
    'imagem': (l['imagemSnapshot'] ?? l['imageUrl'] ?? '').toString(),
    'tamanho': (l['tamanho'] ?? '').toString(),
    'cor': (l['cor'] ?? '').toString(),
    'slug': (l['slug'] ?? '').toString(),
    'widgetProductId': widgetProductId ?? '',
    'openedProductId': openedProductId ?? '',
    'capturedProductId': capturedProductId ?? '',
  };
}

/// Simula commit HEAD (lê widget atual no momento do clique, não snapshot).
Map<String, dynamic> preFixHeadCommit({
  required Map<String, dynamic> widgetNow,
  required String tamanho,
  required String cor,
  required num precoSheet,
  required String slugAtOpen,
  required String imageAtOpen,
}) {
  return {
    'produtosId': widgetNow['id'],
    'id': widgetNow['id'],
    'nome': widgetNow['nome'],
    'preco': precoSheet,
    'slug': slugAtOpen,
    'imageUrl': imageAtOpen,
    'tamanho': tamanho,
    'cor': cor,
    'quantidade': 1,
  };
}

Future<void> _pumpIgnoreImages(WidgetTester tester) async {
  await tester.pump();
  while (tester.takeException() != null) {}
}

Widget _card(
  Map<String, dynamic> p,
  bool Function(Map<String, dynamic>) onAdd, {
  Key? key,
}) {
  return CatalogProductCard(
    key: key,
    id: p['id'] as String,
    name: p['nome'] as String,
    price: (p['preco'] as num).toDouble(),
    imageUrl: p['imageUrl'] as String? ?? '',
    imagens: List<String>.from(p['imagens'] as List? ?? const []),
    descricao: '',
    slug: p['slug'] as String,
    estoquePorTamanho: Map<String, int>.from(p['estoquePorTamanho'] as Map),
    estoquePorCor: Map<String, int>.from(p['estoquePorCor'] as Map? ?? {}),
    percentualDescontoPix: (p['percentualDescontoPix'] as num?)?.toDouble() ?? 0,
    onAdd: onAdd,
    lojaId: _lojaId,
    onAbrirCarrinho: () {},
    produtoCatalogoMap: p,
    quantidade: 5,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R6 — trace pré-fix HEAD (simulação offline)', () {
    test('Race 2 pré-fix: abrir B, card vira A, commit HEAD', () {
      final traces = <Map<String, dynamic>>[];
      const opened = 'produto-b';
      const capturedAtOpen = 'produto-b';
      final widgetAfterSwap = _produtoA();
      const precoSheet = _precoB;
      traces.add(_traceTuple(
        'card_before_open',
        line: null,
        openedProductId: opened,
        capturedProductId: capturedAtOpen,
        widgetProductId: opened,
      ));
      traces.add(_traceTuple('modal_open_snapshot', line: _produtoB()));
      traces.add(_traceTuple('variation_selected', line: {
        'tamanho': _tamB,
        'cor': _corB,
      }));
      traces.add(_traceTuple(
        'underlying_grid_updated',
        line: null,
        widgetProductId: 'produto-a',
      ));
      final committed = preFixHeadCommit(
        widgetNow: widgetAfterSwap,
        tamanho: _tamB,
        cor: _corB,
        precoSheet: precoSheet,
        slugAtOpen: _slugB,
        imageAtOpen: _imgB,
      );
      traces.add(_traceTuple('sheet_commit', line: committed));
      freezeCatalogCartLineSnapshotOnAdd(committed);
      traces.add(_traceTuple('after_freeze', line: committed));

      expect(committed['id'], 'produto-a');
      expect(committed['nome'], _nomeA);
      expect(committed['tamanho'], _tamB);
      expect((committed['preco'] as num).toDouble(), closeTo(_precoB, 0.01));
      expect(_isExactClientTuple(committed), isFalse);
      expect(traces.first['stage'], 'card_before_open');
    });

    test('Race 1 pré-fix: abrir A, card vira B, commit HEAD', () {
      final widgetAfterSwap = _produtoB();
      final committed = preFixHeadCommit(
        widgetNow: widgetAfterSwap,
        tamanho: _tamA,
        cor: _corA,
        precoSheet: _precoA,
        slugAtOpen: _slugA,
        imageAtOpen: _imgA,
      );
      freezeCatalogCartLineSnapshotOnAdd(committed);
      expect(committed['id'], 'produto-b');
      expect(committed['nome'], _nomeB);
      expect(committed['tamanho'], _tamA);
      expect(_isExactClientTuple(committed), isFalse);
    });
  });

  group('R6 — Race 1–4 pós-fix (widget)', () {
    Future<void> runRaceWidget(
      WidgetTester tester, {
      required Map<String, dynamic> openProduct,
      required Map<String, dynamic> swapProduct,
      required String tapTam,
      required List<Map<String, dynamic>> cart,
    }) async {
      var current = openProduct;
      void Function(void Function())? swapGrade;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                swapGrade = setState;
                return Column(
                  children: [
                    Expanded(
                      child: _card(current, (item) {
                        final copy = Map<String, dynamic>.from(item);
                        freezeCatalogCartLineSnapshotOnAdd(copy);
                        cart.add(copy);
                        return true;
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprar').first);
      await _pumpIgnoreImages(tester);
      await tester.pump(const Duration(milliseconds: 400));
      swapGrade!(() => current = swapProduct);
      await tester.pumpAndSettle();
      await tester.tap(find.text(tapTam));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adicionar ao carrinho'));
      await tester.pumpAndSettle();
    }

    testWidgets('Race 1 — abrir A, grade vira B, confirma A', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final cart = <Map<String, dynamic>>[];
      await runRaceWidget(
        tester,
        openProduct: _produtoA(),
        swapProduct: _produtoB(),
        tapTam: _tamA,
        cart: cart,
      );
      final line = cart.single;
      expect(line['id'], 'produto-a');
      expect(line['nomeSnapshot'] ?? line['nome'], _nomeA);
      expect(line['tamanho'], _tamA);
      expect(_isExactClientTuple(line), isFalse);
    });

    testWidgets('Race 2 — abrir B, grade vira A, confirma B', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final cart = <Map<String, dynamic>>[];
      await runRaceWidget(
        tester,
        openProduct: _produtoB(),
        swapProduct: _produtoA(),
        tapTam: _tamB,
        cart: cart,
      );
      final line = cart.single;
      expect(line['id'], 'produto-b');
      expect(line['nomeSnapshot'] ?? line['nome'], _nomeB);
      expect(line['tamanho'], _tamB);
      expect(_isExactClientTuple(line), isFalse);
    });

    testWidgets('Race 3 — preço do sheet permanece B após troca do card', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final cart = <Map<String, dynamic>>[];
      await runRaceWidget(
        tester,
        openProduct: _produtoB(),
        swapProduct: _produtoA(),
        tapTam: _tamB,
        cart: cart,
      );
      final line = cart.single;
      expect(line['id'], 'produto-b');
      expect(line['nomeSnapshot'] ?? line['nome'], _nomeB);
      expect((line['preco'] as num).toDouble(), closeTo(_precoB, 0.01));
      expect(_isExactClientTuple(line), isFalse);
    });

    testWidgets('Race 4 — imagem e slug vêm do seed aberto, não do widget trocado',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final cart = <Map<String, dynamic>>[];
      await runRaceWidget(
        tester,
        openProduct: _produtoB(),
        swapProduct: _produtoA(),
        tapTam: _tamB,
        cart: cart,
      );
      final line = cart.single;
      expect(line['slug'], _slugB);
      expect(line['imagemSnapshot'] ?? line['imageUrl'], _imgB);
      expect(_isExactClientTuple(line), isFalse);
    });
  });

  group('R6 — cópia defensiva CatalogProductAddSeed', () {
    test('mutação pós-captura não altera linha do modal', () {
      final estoque = <String, int>{_tamB: 5};
      final variacoes = <String, dynamic>{'x': 1};
      final seed = CatalogProductAddSeed(
        productId: 'produto-b',
        name: _nomeB,
        price: _precoB,
        slug: _slugB,
        percentualDescontoPix: 5,
        divideSemJuros: false,
        maxParcelas: 1,
        peso: 0,
        tipoEmbalagem: 'padrao',
        imagens: [_imgB],
        imageUrl: _imgB,
        minimalLayout: false,
        emPromocao: false,
        mostrarQuantidadeNoCatalogo: false,
        estoquePorTamanho: catalogProductAddSeedCopyIntMap(estoque),
        estoquePorCor: const {},
        variacoes: catalogProductAddSeedCopyDynamicMap(variacoes),
      );
      estoque[_tamB] = 0;
      estoque['novo'] = 99;
      variacoes['x'] = 999;
      variacoes['y'] = 2;

      expect(seed.estoquePorTamanho[_tamB], 5);
      expect(seed.variacoes!['x'], 1);
      expect(seed.variacoes!.containsKey('y'), isFalse);

      final line = seed.buildCartLine(
        tamanho: _tamB,
        cor: _corB,
        preco: _precoB,
        extraValor: '',
        extraTipo: '',
        resumoExtra: '',
      );
      expect(line['id'], 'produto-b');
      expect(line['nome'], _nomeB);
      expect(line['slug'], _slugB);
      expect(line['imageUrl'], _imgB);
    });
  });

  group('R6 — alcançabilidade produtiva (filtro real com sheet aberto)', () {
    testWidgets('atualização da grade troca props do card sem fechar o sheet',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final cart = <Map<String, dynamic>>[];
      var current = _produtoA();
      void Function(void Function())? applyFilter;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                applyFilter = setState;
                return Column(
                  children: [
                    Expanded(
                      child: _card(
                        current,
                        (item) {
                          final copy = Map<String, dynamic>.from(item);
                          freezeCatalogCartLineSnapshotOnAdd(copy);
                          cart.add(copy);
                          return true;
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Comprar').first);
      await _pumpIgnoreImages(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester
            .widget<CatalogProductSelectionSheet>(
              find.byType(CatalogProductSelectionSheet),
            )
            .productId,
        'produto-a',
      );

      await tester.tap(find.text(_tamA));
      await tester.pumpAndSettle();

      applyFilter!(() => current = _produtoB());
      await tester.pumpAndSettle();

      expect(
        tester.widget<CatalogProductCard>(find.byType(CatalogProductCard)).id,
        'produto-b',
      );
      expect(
        tester
            .widget<CatalogProductSelectionSheet>(
              find.byType(CatalogProductSelectionSheet),
            )
            .productId,
        'produto-a',
      );

      await tester.tap(find.text('Adicionar ao carrinho'));
      await tester.pumpAndSettle();

      expect(cart.single['id'], 'produto-a');
      expect(cart.single['nomeSnapshot'] ?? cart.single['nome'], _nomeA);
    });
  });

  group('R6 — invariância preço PIX', () {
    test('precoPixSnapshot deriva do preço B congelado após troca de catálogo', () {
      final line = {
        'id': 'produto-b',
        'nome': _nomeB,
        'preco': _precoB,
        'percentualDescontoPix': 5.0,
        'quantidade': 1,
        'tamanho': _tamB,
        'cor': _corB,
      };
      freezeCatalogCartLineSnapshotOnAdd(line);
      final checkout = prepareCatalogCheckoutCartItems(
        cartLines: [line],
        catalogProducts: [_produtoA()],
        pagamento: 'PIX',
      ).single;
      expect(
        (checkout['precoPixSnapshot'] as num).toDouble(),
        closeTo(_precoPixB, 0.02),
      );
      expect(checkout['productId'], 'produto-b');
      expect(checkout['nomeSnapshot'], _nomeB);
    });
  });
}
