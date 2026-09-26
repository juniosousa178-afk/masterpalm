import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_card.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_products_grid_sliver.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_variation_pick_body.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';
import 'package:master_palm/services/catalog_pre_pedido_compute.dart';

void main() {
  const elosId = 'nathy-pratas-e-folheados-anel-elos-cora-ozinho';
  const bocaId = 'nathy-pratas-e-folheados-anel-boca-de-tubar-o-pontos-de-luz';

  Map<String, dynamic> elosCommit() => {
        'produtosId': elosId,
        'id': elosId,
        'nome': 'Anel Elos Coraçãozinho',
        'preco': 37.9,
        'imageUrl': 'elos.jpg',
        'url_foto': 'elos.jpg',
        'slug': elosId,
        'tamanho': '19',
        'cor': 'sem-cor',
        'quantidade': 1,
        'percentualDescontoPix': 5,
      };

  Map<String, dynamic> bocaCommit() => {
        'produtosId': bocaId,
        'id': bocaId,
        'nome': 'Anel Boca De Tubarão',
        'preco': 69.9,
        'imageUrl': 'boca.jpg',
        'url_foto': 'boca.jpg',
        'slug': bocaId,
        'tamanho': '19',
        'cor': 'prata',
        'quantidade': 1,
        'percentualDescontoPix': 5,
      };

  void addLikeCatalog(List<Map<String, dynamic>> cart, Map<String, dynamic> item) {
    final key = CatalogEstoqueHelper.cartLineIdentity(item);
    final idx = cart.indexWhere(
      (e) => CatalogEstoqueHelper.cartLineIdentity(e) == key,
    );
    if (idx >= 0) {
      final cur = CatalogEstoqueHelper.parseCartItemQuantidade(
        cart[idx]['quantidade'],
      );
      cart[idx]['quantidade'] = cur + 1;
      refreshCatalogCartLineFromAdd(cart[idx], item);
    } else {
      final copy = Map<String, dynamic>.from(item);
      copy['quantidade'] = 1;
      freezeCatalogCartLineSnapshotOnAdd(copy);
      cart.add(copy);
    }
  }

  void expectAtomic(Map<String, dynamic> line, {required bool elos}) {
    if (elos) {
      expect(line['id'], elosId);
      expect(line['nome'], 'Anel Elos Coraçãozinho');
      expect(line['imageUrl'] ?? line['imagemSnapshot'], 'elos.jpg');
      expect(line['preco'] ?? line['precoUnitarioSnapshot'], 37.9);
      expect(line['cor'], 'sem-cor');
    } else {
      expect(line['id'], bocaId);
      expect(line['nome'], 'Anel Boca De Tubarão');
      expect(line['imageUrl'] ?? line['imagemSnapshot'], 'boca.jpg');
      expect(line['preco'] ?? line['precoUnitarioSnapshot'], 69.9);
      expect(line['cor'], 'prata');
    }
    expect(line['tamanho'], '19');
  }

  test('add B/19 depois A não funde e não hibrida', () {
    final cart = <Map<String, dynamic>>[];
    addLikeCatalog(cart, bocaCommit());
    addLikeCatalog(cart, elosCommit());
    expect(cart, hasLength(2));
    expectAtomic(cart[0], elos: false);
    expectAtomic(cart[1], elos: true);
    expect(
      CatalogEstoqueHelper.cartLineIdentity(cart[0]) ==
          CatalogEstoqueHelper.cartLineIdentity(cart[1]),
      isFalse,
    );
  });

  test('add A depois B/19 não funde', () {
    final cart = <Map<String, dynamic>>[];
    addLikeCatalog(cart, elosCommit());
    addLikeCatalog(cart, bocaCommit());
    expect(cart, hasLength(2));
    expectAtomic(cart[0], elos: true);
    expectAtomic(cart[1], elos: false);
  });

  test('carrinho persistido recarregado não hibrida ao adicionar A', () {
    final cart = <Map<String, dynamic>>[];
    addLikeCatalog(cart, bocaCommit());
    final restored = (jsonDecode(jsonEncode(cart)) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    addLikeCatalog(restored, elosCommit());
    expect(restored, hasLength(2));
    expectAtomic(restored[0], elos: false);
    expectAtomic(restored[1], elos: true);
  });

  test('PIX recalcula o preço da própria linha e preserva a identidade', () {
    final cart = <Map<String, dynamic>>[];
    addLikeCatalog(cart, bocaCommit());
    addLikeCatalog(cart, elosCommit());
    final money = computeCatalogPrePedidoMoneySnapshot(
      items: prepareCatalogCheckoutCartItems(
        cartLines: cart,
        pagamento: 'PIX',
      ),
      entrega: const {'valor': 0, 'freteGratis': true},
      pagamento: 'PIX',
    );
    final boca = money.itensList.firstWhere((e) => e['productId'] == bocaId);
    final elos = money.itensList.firstWhere((e) => e['productId'] == elosId);
    expect(boca['nome'], 'Anel Boca De Tubarão');
    expect(boca['cor'], 'prata');
    expect(boca['precoUnitario'], closeTo(69.9 * 0.95, 0.001));
    expect(elos['nome'], 'Anel Elos Coraçãozinho');
    expect(elos['cor'], 'sem-cor');
    expect(elos['precoUnitario'], closeTo(37.9 * 0.95, 0.001));
  });

  testWidgets(
    'trocar o produto do seletor não grava o preço do Elos na identidade da Boca',
    (tester) async {
      final harness = GlobalKey<_HybridHarnessState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _HybridHarness(key: harness),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('19'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('sem-cor'));
      await tester.pumpAndSettle();

      harness.currentState!.showBoca();
      await tester.pump();

      expect(harness.currentState!.captured, isNull);
      expect(find.text('Adicionar ao carrinho'), findsNothing);
      expect(find.text('Selecione o tamanho'), findsOneWidget);
    },
  );

  testWidgets(
    'sheet do Elos aberto e card reapontado para Boca grava o híbrido do incidente',
    (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.exceptionAsString();
        if (text.contains('overflowed') || text.contains('RenderFlex')) return;
        if (details.library == 'image resource service') return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = GlobalKey<_CardSwapHarnessState>();
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = _PngHttpOverrides();
      addTearDown(() => HttpOverrides.global = previousOverrides);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: _CardSwapHarness(key: harness)),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.shopping_cart_outlined).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('19').last);
      await tester.pump();
      await tester.tap(find.text('sem-cor').last);
      await tester.pump();

      harness.currentState!.showBoca();
      await tester.pump();

      await tester.tap(find.text('Adicionar ao carrinho'));
      await tester.pump();

      final line = harness.currentState!.captured;
      expect(line, isNotNull);
      expect(line!['id'], elosId);
      expect(line['nome'], 'Anel Elos Coraçãozinho');
      expect(line['slug'], elosId);
      expect(line['imageUrl'], 'https://example.test/elos.jpg');
      expect(line['preco'], 37.9);
      expect(line['tamanho'], '19');
      expect(line['cor'], 'sem-cor');
      expect(line['id'], isNot(bocaId));
    },
  );

  test('cor explícita inexistente não herda o saldo de outra cor', () {
    final boca = {
      'id': bocaId,
      'variacoes': {
        '19': {'prata': 1},
      },
    };
    expect(
      CatalogEstoqueHelper.estoqueDisponivelVariacao(boca, '19', 'sem-cor'),
      0,
    );
    expect(
      CatalogEstoqueHelper.canonicalExplicitVariationExists(
        boca,
        '19',
        'sem-cor',
      ),
      isFalse,
    );
    final elos = {
      'id': elosId,
      'variacoes': {
        '19': {'sem-cor': 1},
      },
    };
    expect(
      CatalogEstoqueHelper.estoqueDisponivelVariacao(elos, '19', 'sem-cor'),
      1,
    );
    expect(
      CatalogEstoqueHelper.canonicalExplicitVariationExists(
        elos,
        '19',
        'sem-cor',
      ),
      isTrue,
    );
  });

  test('carrinho híbrido antigo não passa no checkout e o legado válido passa', () {
    final catalog = [
      {
        'id': bocaId,
        'nome': 'Anel Boca De Tubarão',
        'preco': 69.9,
        'variacoes': {
          '19': {'prata': 1},
        },
      },
      {
        'id': elosId,
        'nome': 'Anel Elos Coraçãozinho',
        'preco': 37.9,
        'variacoes': {
          '19': {'sem-cor': 1},
        },
      },
    ];
    final hybrid = {
      'id': bocaId,
      'productId': bocaId,
      'nome': 'Anel Boca De Tubarão',
      'imageUrl': 'boca.jpg',
      'preco': 37.9,
      'tamanho': '19',
      'cor': 'sem-cor',
      'quantidade': 1,
    };
    expect(
      catalogCartVariationIntegrityBlock(
        cartLines: [hybrid],
        catalogProducts: catalog,
      ),
      kCatalogCartLineNeedsRefreshMessage,
    );
    final legacy = {
      'id': elosId,
      'nome': 'Anel Elos Coraçãozinho',
      'nomeSnapshot': 'Anel Elos Coraçãozinho',
      'schemaVersion': 1,
      'preco': 40.0,
      'precoUnitarioSnapshot': 40.0,
      'tamanho': '19',
      'cor': 'sem-cor',
      'quantidade': 1,
      'percentualDescontoPix': 5,
    };
    expect(
      catalogCartVariationIntegrityBlock(
        cartLines: [legacy],
        catalogProducts: catalog,
      ),
      isNull,
    );
    final guarded = prepareCatalogCheckoutCartItems(
      cartLines: [legacy],
      catalogProducts: catalog,
      pagamento: 'PIX',
    );
    final money = computeCatalogPrePedidoMoneySnapshot(
      items: guarded,
      entrega: const {'valor': 0, 'freteGratis': true},
      pagamento: 'PIX',
    );
    expect(money.itensList.single['precoUnitario'], closeTo(40 * 0.95, 0.001));
    expect(money.itensList.single['nome'], 'Anel Elos Coraçãozinho');
    expect(money.itensList.single.containsKey('cartLineConsistencyVersion'), isFalse);
  });

  testWidgets('reordenar o grid não troca o produto do modal aberto', (tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('overflowed') || text.contains('RenderFlex')) return;
      if (details.library == 'image resource service') return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _PngHttpOverrides();
    addTearDown(() => HttpOverrides.global = previousOverrides);

    final harness = GlobalKey<_GridOrderHarnessState>();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: _GridOrderHarness(key: harness))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final elosKey = find.byKey(ValueKey('catalog-product-$elosId'));
    expect(elosKey, findsOneWidget);
    await tester.tap(
      find.descendant(
        of: elosKey,
        matching: find.byIcon(Icons.shopping_cart_outlined),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('19').last);
    await tester.pump();
    await tester.tap(find.text('sem-cor').last);
    await tester.pump();

    harness.currentState!.reorderAndInsert();
    await tester.pump();

    expect(find.byKey(ValueKey('catalog-product-$elosId')), findsOneWidget);
    expect(find.byKey(ValueKey('catalog-product-$bocaId')), findsOneWidget);
    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pump();

    final line = harness.currentState!.captured;
    expect(line, isNotNull);
    expect(line!['id'], elosId);
    expect(line['nome'], 'Anel Elos Coraçãozinho');
    expect(line['preco'], 37.9);
    expect(line['cor'], 'sem-cor');
    expect(line['id'], isNot(bocaId));
  });
}

class _PngHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _PngHttpClient();
}

class _PngHttpClient extends Fake implements HttpClient {
  @override
  bool get autoUncompress => true;

  @override
  set autoUncompress(bool value) {}

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _PngRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _PngRequest();
}

class _PngRequest extends Fake implements HttpClientRequest {
  @override
  HttpHeaders get headers => _PngHeaders();

  @override
  Future<HttpClientResponse> close() async => _PngResponse();
}

class _PngHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _PngResponse extends Fake implements HttpClientResponse {
  static final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  @override
  int get statusCode => 200;

  @override
  int get contentLength => _png.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_png).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class _CardSwapHarness extends StatefulWidget {
  const _CardSwapHarness({super.key});

  @override
  State<_CardSwapHarness> createState() => _CardSwapHarnessState();
}

class _CardSwapHarnessState extends State<_CardSwapHarness> {
  bool _boca = false;
  Map<String, dynamic>? captured;

  void showBoca() => setState(() => _boca = true);

  @override
  Widget build(BuildContext context) {
    final elos = !_boca;
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 360,
        height: 640,
        child: CatalogProductCard(
          id: elos
              ? 'nathy-pratas-e-folheados-anel-elos-cora-ozinho'
              : 'nathy-pratas-e-folheados-anel-boca-de-tubar-o-pontos-de-luz',
          name: elos ? 'Anel Elos Coraçãozinho' : 'Anel Boca De Tubarão',
          price: elos ? 37.9 : 69.9,
          imageUrl: '',
          imagens: [
            elos
                ? 'https://example.test/elos.jpg'
                : 'https://example.test/boca.jpg',
          ],
          descricao: '',
          slug: elos
              ? 'nathy-pratas-e-folheados-anel-elos-cora-ozinho'
              : 'nathy-pratas-e-folheados-anel-boca-de-tubar-o-pontos-de-luz',
          lojaId: 'nathy-pratas-e-folheados',
          percentualDescontoPix: 5,
          minimalLayout: true,
          onAbrirCarrinho: () {},
          variacoes: elos
              ? const {
                  '19': {'sem-cor': 1},
                }
              : const {
                  '19': {'prata': 1},
                },
          onAdd: (item) {
            captured = Map<String, dynamic>.from(item);
            return true;
          },
        ),
      ),
    );
  }
}

class _GridOrderHarness extends StatefulWidget {
  const _GridOrderHarness({super.key});

  @override
  State<_GridOrderHarness> createState() => _GridOrderHarnessState();
}

class _GridOrderHarnessState extends State<_GridOrderHarness> {
  Map<String, dynamic>? captured;
  var _reordered = false;

  void reorderAndInsert() => setState(() => _reordered = true);

  Map<String, dynamic> _product({
    required String id,
    required String nome,
    required double preco,
    required String cor,
    required String image,
  }) {
    return {
      'id': id,
      'nome': nome,
      'slug': id,
      'preco': preco,
      'percentualDescontoPix': 5,
      'imagens': [image],
      'variacoes': {
        '19': {cor: 1},
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final elos = _product(
      id: 'nathy-pratas-e-folheados-anel-elos-cora-ozinho',
      nome: 'Anel Elos Coraçãozinho',
      preco: 37.9,
      cor: 'sem-cor',
      image: 'https://example.test/elos.jpg',
    );
    final boca = _product(
      id: 'nathy-pratas-e-folheados-anel-boca-de-tubar-o-pontos-de-luz',
      nome: 'Anel Boca De Tubarão',
      preco: 69.9,
      cor: 'prata',
      image: 'https://example.test/boca.jpg',
    );
    final products = _reordered
        ? [boca, elos, _product(
            id: 'nathy-pratas-e-folheados-extra',
            nome: 'Extra',
            preco: 10,
            cor: 'ouro',
            image: 'https://example.test/extra.jpg',
          )]
        : [elos, boca];
    return CustomScrollView(
      slivers: [
        buildCatalogProductsGridSliver(
          products: products,
          lojaId: 'nathy-pratas-e-folheados',
          onAdd: (item) {
            captured = Map<String, dynamic>.from(item);
            return true;
          },
          onAbrirCarrinho: () {},
          mostrarEstoqueNoCatalogo: false,
          mostrarQuantidadeNoCatalogo: false,
          cardBorderRadius: 12,
          cardShowShadow: false,
          maxParcelas: 1,
          mobileCols: 1,
          childAspectRatio: 0.72,
          useMinimalLayout: true,
        ),
      ],
    );
  }
}

class _HybridHarness extends StatefulWidget {
  const _HybridHarness({super.key});

  @override
  State<_HybridHarness> createState() => _HybridHarnessState();
}

class _HybridHarnessState extends State<_HybridHarness> {
  bool _boca = false;
  Map<String, dynamic>? captured;

  void showBoca() => setState(() => _boca = true);

  @override
  Widget build(BuildContext context) {
    final elos = !_boca;
    final id = elos
        ? 'nathy-pratas-e-folheados-anel-elos-cora-ozinho'
        : 'nathy-pratas-e-folheados-anel-boca-de-tubar-o-pontos-de-luz';
    final nome = elos ? 'Anel Elos Coraçãozinho' : 'Anel Boca De Tubarão';
    final image = elos ? 'elos.jpg' : 'boca.jpg';
    return CatalogProductVariationPickBody(
      productId: id,
      name: nome,
      price: elos ? 37.9 : 69.9,
      emPromocao: false,
      imageUrl: image,
      estoquePorTamanho: const {},
      estoquePorCor: const {},
      showProductSnippet: false,
      variacoes: elos
          ? const {
              '19': {'sem-cor': 2},
            }
          : const {
              '19': {'prata': 1},
            },
      onPickCommit: (tamanho, cor, preco, extraValor, extraTipo) {
        captured = {
          'id': id,
          'produtosId': id,
          'nome': nome,
          'slug': id,
          'imageUrl': image,
          'preco': preco,
          'tamanho': tamanho ?? '',
          'cor': cor ?? '',
          'extraValor': extraValor,
          'extraTipo': extraTipo,
        };
      },
    );
  }
}
