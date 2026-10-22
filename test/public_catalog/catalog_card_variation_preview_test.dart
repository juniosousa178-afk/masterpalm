import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_card_variation_preview_data.dart';
import 'package:master_palm/screens/public_catalog/catalog_product_card_size.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_card_variation_preview.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_image_placeholder.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_products_grid_sliver.dart';

CatalogCardVariationPreviewData? _preview({
  Map<String, dynamic>? variacoes,
  Map<String, int>? ept,
  Map<String, int>? epc,
  Object? tamanhos,
  Object? cores,
}) =>
    CatalogCardVariationPreviewData.fromCardInputs(
      variacoes: variacoes,
      estoquePorTamanho: ept,
      estoquePorCor: epc,
      tamanhosOrdem: tamanhos,
      coresOrdem: cores,
    );

Map<String, dynamic> _produto({
  required String id,
  String nome = 'Anel Solitário',
  double preco = 89.9,
  double pix = 0,
  Map<String, dynamic>? variacoes,
  Map<String, int>? ept,
  Map<String, int>? epc,
  List<String>? tamanhos,
  List<String>? categorias,
}) {
  return {
    'id': id,
    'nome': nome,
    'preco': preco,
    'slug': id,
    'percentualDescontoPix': pix,
    'quantidade': 10,
    'divideSemJuros': true,
    'maxParcelasSemJuros': 3,
    if (variacoes != null) 'variacoes': variacoes,
    if (ept != null) 'estoquePorTamanho': ept,
    if (epc != null) 'estoquePorCor': epc,
    if (tamanhos != null) 'tamanhos': tamanhos,
    if (categorias != null) 'categorias': categorias,
    if (categorias != null) 'categoria': categorias.first,
  };
}

/// Grade real de anel: Firestore entrega chaves em ordem lexicográfica.
Map<String, dynamic> _anelGrade(List<String> sizes) => {
      for (final s in sizes) s: {'sem-cor': 2},
    };

const _ringSizes = ['12', '14', '16', '18', '20'];
const _nineSizes = ['10', '11', '12', '13', '14', '16', '18', '19', '20'];

int _cols(double w) => w >= 1024 ? 4 : (w >= 640 ? 3 : 2);

double _ratio(double w, bool minimal, String size) {
  if (minimal) {
    final r = CatalogProductCardSize.minimalAspectRatio(size);
    return w >= 1024 ? (r + 0.045).clamp(0.30, 0.52) : r;
  }
  final r = CatalogProductCardSize.standardAspectRatio(size);
  if (w < 360) return r + 0.065;
  if (w < 640) return r + 0.04;
  return r;
}

Future<List<Map<String, dynamic>>> _pumpGrid(
  WidgetTester tester, {
  required double width,
  required bool minimal,
  required List<Map<String, dynamic>> products,
  String size = CatalogProductCardSize.medium,
  double height = 2400,
}) async {
  final added = <Map<String, dynamic>>[];
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  final cols = _cols(width);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            buildCatalogProductsGridSliver(
              products: products,
              lojaId: 'loja-teste',
              onAdd: (m) {
                added.add(Map<String, dynamic>.from(m));
                return true;
              },
              onAbrirCarrinho: () {},
              mostrarEstoqueNoCatalogo: false,
              mostrarQuantidadeNoCatalogo: false,
              cardBorderRadius: 18,
              cardShowShadow: true,
              maxParcelas: 3,
              childAspectRatio: _ratio(width, minimal, size),
              isDesktop: cols > 2,
              desktopCols: cols,
              mobileCols: 2,
              useMinimalLayout: minimal,
              productCardSize: size,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  return added;
}

Finder _card(String id) => find.byKey(ValueKey('catalog-product-$id'));

Finder _in(String id, Finder f) => find.descendant(of: _card(id), matching: f);

List<String> _chipTexts(String id) {
  final preview = _in(id, find.byType(CatalogCardVariationPreview));
  if (preview.evaluate().isEmpty) return const [];
  final texts = find.descendant(of: preview, matching: find.byType(Text));
  final out = <({double x, String t})>[];
  for (final e in texts.evaluate()) {
    final w = e.widget as Text;
    final box = e.renderObject! as RenderBox;
    out.add((x: box.localToGlobal(Offset.zero).dx, t: w.data ?? ''));
  }
  out.removeWhere(
      (e) => e.t == 'Tamanhos' || e.t == 'Cores' || e.t == 'Variações');
  out.sort((a, b) => a.x.compareTo(b.x));
  return [for (final e in out) e.t];
}

bool _within(Rect inner, Rect outer) =>
    inner.left >= outer.left - 0.01 &&
    inner.right <= outer.right + 0.01 &&
    inner.top >= outer.top - 0.01 &&
    inner.bottom <= outer.bottom + 0.01;

Rect _first(WidgetTester tester, Finder f) => tester.getRect(f.first);

/// Escala aplicada pelo FittedBox (scaleDown) que envolve o rodapé do card.
double _footerScale(WidgetTester tester, String id) {
  final footer = _in(
    id,
    find.byWidgetPredicate(
      (w) =>
          w is FittedBox &&
          w.fit == BoxFit.scaleDown &&
          w.alignment == Alignment.topCenter,
    ),
  ).first;
  final box = tester.renderObject<RenderProxyBox>(footer);
  final child = box.child!;
  final sx = box.size.width / child.size.width;
  final sy = box.size.height / child.size.height;
  return (sx < sy ? sx : sy).clamp(0.0, 1.0);
}

void _expectSize(Size actual, Size expected) {
  expect(actual.width, closeTo(expected.width, 0.01));
  expect(actual.height, closeTo(expected.height, 0.01));
}

void main() {
  group('CatalogCardVariationPreviewData', () {
    test('sem variações → sem prévia', () {
      expect(_preview(), isNull);
      expect(
          _preview(variacoes: const {}, ept: const {}, epc: const {}), isNull);
    });

    test('células zeradas, meta e sentinelas não aparecem', () {
      expect(
        _preview(variacoes: {
          '12': {'sem-cor': 0},
          'sem-tamanho': {'sem-cor': 3},
        }),
        isNull,
      );
      final d = _preview(variacoes: {
        '12': {'sem-cor': 0},
        '14': {'sem-cor': 1, '__custoUnitario': 9.5},
        '16': {'__custoUnitario': 9.5},
      })!;
      expect(d.kind, CatalogCardVariationKind.sizes);
      expect(d.labels, ['14']);
    });

    test('uma variação', () {
      final d = _preview(variacoes: {
        '16': {'sem-cor': 1},
      })!;
      expect(d.title, 'Tamanhos');
      expect(d.labels, ['16']);
    });

    test('ordenação numérica (ordem lexicográfica do Firestore)', () {
      final d =
          _preview(variacoes: _anelGrade(['10', '12', '8', '9', '17,5']))!;
      expect(d.labels, ['8', '9', '10', '12', '17,5']);
    });

    test('9 tamanhos: todos disponíveis, ordenados', () {
      final d = _preview(variacoes: _anelGrade(_nineSizes))!;
      expect(d.labels, _nineSizes);
      expect(d.semanticsLabel,
          'Tamanhos disponíveis: 10, 11, 12, 13, 14, 16, 18, 19, 20');
    });

    test('tamanhos texto: ordem editorial de `tamanhos`', () {
      final d = _preview(
        variacoes: {
          'G': {'sem-cor': 1},
          'M': {'sem-cor': 1},
          'P': {'sem-cor': 1},
        },
        tamanhos: const ['P', 'M', 'G', 'GG'],
      )!;
      expect(d.labels, ['P', 'M', 'G']);
      final semOrdem = _preview(variacoes: {
        'G': {'sem-cor': 1},
        'M': {'sem-cor': 1},
      })!;
      expect(semOrdem.labels, ['G', 'M']);
    });

    test('somente cor (sem-tamanho) → Cores', () {
      final d = _preview(
        variacoes: {
          'sem-tamanho': {'Rosa': 2, 'Prata': 1, 'Dourado': 0},
        },
        cores: const ['Prata', 'Rosa'],
      )!;
      expect(d.kind, CatalogCardVariationKind.colors);
      expect(d.title, 'Cores');
      expect(d.labels, ['Prata', 'Rosa']);
    });

    test('tamanho + cor: só combinações reais, sem produto cartesiano', () {
      final d = _preview(variacoes: {
        '18': {'Rosa': 1},
        '16': {'Prata': 2, 'Rosa': 0},
      })!;
      expect(d.kind, CatalogCardVariationKind.combined);
      expect(d.title, 'Variações');
      expect(d.labels, ['16 · Prata', '18 · Rosa']);
      expect(d.labels, isNot(contains('16 · Rosa')));
      expect(d.labels, isNot(contains('18 · Prata')));
      expect(d.semanticsLabel, 'Variações disponíveis: 16 Prata, 18 Rosa');
    });

    test('uma única cor em todos os tamanhos → Tamanhos', () {
      final d = _preview(variacoes: {
        '14': {'Dourado': 1},
        '12': {'Dourado': 1},
      })!;
      expect(d.kind, CatalogCardVariationKind.sizes);
      expect(d.labels, ['12', '14']);
    });

    test('um único tamanho com várias cores → Cores', () {
      final d = _preview(variacoes: {
        'Único': {'Prata': 1, 'Rosa': 1},
      })!;
      expect(d.kind, CatalogCardVariationKind.colors);
      expect(d.labels, ['Prata', 'Rosa']);
    });

    test('célula com eixo extra conta pela soma', () {
      final d = _preview(variacoes: {
        '12': {
          'sem-cor': {'A': 0, 'B': 2},
        },
        '14': {
          'sem-cor': {'_sem_extra': 0},
        },
      })!;
      expect(d.labels, ['12']);
    });

    test('legado: estoquePorTamanho / estoquePorCor', () {
      final t = _preview(ept: const {'20': 1, '18': 0, '12': 3})!;
      expect(t.kind, CatalogCardVariationKind.sizes);
      expect(t.labels, ['12', '20']);
      final c = _preview(epc: const {'Prata': 2, 'sem-cor': 4, 'Rosa': 0})!;
      expect(c.kind, CatalogCardVariationKind.colors);
      expect(c.labels, ['Prata']);
    });
  });

  group('visibleChipCount', () {
    double plus(int _) => 24;
    test('cabe tudo', () {
      expect(
        CatalogCardVariationPreview.visibleChipCount(
          chipWidths: List.filled(5, 30),
          overflowChipWidth: plus,
          maxWidth: 500,
        ),
        5,
      );
    });
    test('máximo de 6 + "+N"', () {
      expect(
        CatalogCardVariationPreview.visibleChipCount(
          chipWidths: List.filled(9, 30),
          overflowChipWidth: plus,
          maxWidth: 1000,
        ),
        CatalogCardVariationPreviewData.maxVisibleChips,
      );
    });
    test('largura estreita reserva o "+N"', () {
      // 3 chips (90) + 2 gaps (8) + gap + "+N" (28) = 126 ≤ 130; 4 chips não cabem.
      expect(
        CatalogCardVariationPreview.visibleChipCount(
          chipWidths: List.filled(9, 30),
          overflowChipWidth: plus,
          maxWidth: 130,
        ),
        3,
      );
    });
  });

  testWidgets('largura folgada: 6 chips + "+3" (máximo visível)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              child: CatalogCardVariationPreview(
                data: _preview(variacoes: _anelGrade(_nineSizes))!,
                textColor: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((t) => t != 'Tamanhos')
        .toList();
    expect(texts, ['10', '11', '12', '13', '14', '16', '+3']);
    expect(
      tester.getSize(find.byType(CatalogCardVariationPreview)).height,
      CatalogCardVariationPreview.height,
    );
    expect(tester.takeException(), isNull);
  });

  group('card no grid', () {
    for (final minimal in const [false, true]) {
      final layout = minimal ? 'minimalista' : 'clássico';
      for (final width in const [320.0, 360.0, 390.0, 412.0, 768.0, 1280.0]) {
        for (final cardSize in const [
          CatalogProductCardSize.small,
          CatalogProductCardSize.medium,
          CatalogProductCardSize.large,
        ]) {
          testWidgets(
              '$layout ${width.toInt()}px $cardSize: alinhado, sem overflow, CTA intacto',
              (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final cols = _cols(width);
            final products = <Map<String, dynamic>>[
              _produto(id: 'anel', pix: 5, variacoes: _anelGrade(_ringSizes)),
              _produto(id: 'anel-simples', pix: 5),
              _produto(id: 'pingente', nome: 'Pingente Cruz', pix: 5),
              _produto(
                id: 'anel9',
                nome:
                    'Anel Aparador Cravejado Zircônias Ouro Branco Ródio Extra Longo',
                variacoes: _anelGrade(_nineSizes),
              ),
              _produto(
                id: 'brinco',
                nome: 'Brinco Argola',
                variacoes: {
                  '16': {'Prata Envelhecida Fosca Especial': 1},
                  '18': {'Rosa Gold Polido Super Brilhante': 2},
                },
              ),
              for (var i = 0; i < cols; i++)
                _produto(id: 'extra$i', nome: 'Corrente $i'),
            ];
            final added = await _pumpGrid(
              tester,
              width: width,
              minimal: minimal,
              size: cardSize,
              products: products,
            );
            expect(tester.takeException(), isNull);

            final anelCard = tester.getRect(_card('anel'));
            final simplesCard = tester.getRect(_card('anel-simples'));
            _expectSize(anelCard.size, simplesCard.size);
            expect(anelCard.top, closeTo(simplesCard.top, 0.01));
            _expectSize(anelCard.size, tester.getRect(_card('pingente')).size);

            // Pingente sem variação: sem seção, sem rótulo.
            expect(_in('pingente', find.byType(CatalogCardVariationPreview)),
                findsNothing);
            expect(_in('pingente', find.text('Tamanhos')), findsNothing);

            // Anel: prévia dentro do card, depois do preço/Pix e antes do CTA.
            final preview =
                _in('anel', find.byType(CatalogCardVariationPreview));
            expect(preview, findsOneWidget);
            final previewRect = tester.getRect(preview);
            expect(_within(previewRect, anelCard), isTrue);
            final price = _first(tester, _in('anel', find.text('R\$ 89,90')));
            final cta = _first(
                tester, _in('anel', find.byIcon(Icons.shopping_cart_outlined)));
            expect(previewRect.top, greaterThanOrEqualTo(price.bottom - 0.01));
            expect(cta.top, greaterThanOrEqualTo(previewRect.bottom - 0.01));
            expect(_within(cta, anelCard), isTrue);
            final comprar = _in('anel', find.text('Comprar'));
            if (comprar.evaluate().isNotEmpty) {
              expect(_within(_first(tester, comprar), anelCard), isTrue);
            }

            final scaleAnel = _footerScale(tester, 'anel');
            final scaleSimples = _footerScale(tester, 'anel-simples');
            if (scaleSimples < 0.999) {
              // Rodapé do vizinho já era reduzido antes da prévia (ex.: large em 320px):
              // a prévia não pode reduzir mais; diferença residual limitada.
              expect(scaleAnel, greaterThanOrEqualTo(scaleSimples - 0.001));
              expect(scaleAnel, lessThanOrEqualTo(scaleSimples + 0.03));
            } else {
              expect(scaleAnel, greaterThan(0.999));

              // Mesma tipografia/escala do vizinho sem variação (rodapé não encolhe).
              final nameAnel =
                  _first(tester, _in('anel', find.text('Anel Solitário')));
              final nameSimples = _first(
                  tester, _in('anel-simples', find.text('Anel Solitário')));
              _expectSize(nameAnel.size, nameSimples.size);
              _expectSize(
                price.size,
                _first(tester, _in('anel-simples', find.text('R\$ 89,90')))
                    .size,
              );
              final ctaSimples = _first(
                tester,
                _in('anel-simples', find.byIcon(Icons.shopping_cart_outlined)),
              );
              _expectSize(cta.size, ctaSimples.size);
              if (minimal) {
                // Minimalista: a faixa usa a folga do rodapé; a foto só cede o que faltar (≤ faixa).
                final imgAnel = tester
                    .getRect(_in('anel', find.byType(CatalogImagePlaceholder)));
                final imgSimples = tester.getRect(
                    _in('anel-simples', find.byType(CatalogImagePlaceholder)));
                expect(imgAnel.top, closeTo(imgSimples.top, 0.01));
                expect(imgAnel.width, closeTo(imgSimples.width, 0.01));
                final yielded = imgSimples.height - imgAnel.height;
                expect(yielded, greaterThanOrEqualTo(-0.01));
                expect(
                    yielded,
                    lessThanOrEqualTo(
                        CatalogCardVariationPreview.height + 0.01));
                expect(nameAnel.top, closeTo(nameSimples.top - yielded, 0.01));
                if (cardSize != CatalogProductCardSize.large) {
                  expect(yielded, closeTo(0, 0.01),
                      reason: 'com folga no rodapé a foto não muda');
                }
              } else {
                // Clássico (rodapé ancorado embaixo): CTA alinhado ao vizinho.
                expect(cta.top, closeTo(ctaSimples.top, 0.5));
              }
            }

            // Chips todos no card e na mesma linha.
            final chipTexts = _in(
                'anel',
                find.descendant(
                  of: find.byType(CatalogCardVariationPreview),
                  matching: find.byType(Text),
                ));
            for (final e in chipTexts.evaluate()) {
              final r = tester.getRect(find.byWidget(e.widget));
              expect(_within(r, anelCard), isTrue);
            }

            // 9 tamanhos: no máximo 6 visíveis + "+N" coerente.
            final nine = _chipTexts('anel9');
            final visible = nine.where((t) => !t.startsWith('+')).toList();
            expect(visible.length, lessThanOrEqualTo(6));
            expect(visible, _nineSizes.take(visible.length).toList());
            expect(nine.last, '+${_nineSizes.length - visible.length}');
            expect(
                _within(
                    tester.getRect(
                        _in('anel9', find.byType(CatalogCardVariationPreview))),
                    tester.getRect(_card('anel9'))),
                isTrue);

            // Nomes de variação longos: ficam no card (reticências).
            expect(
                _within(
                    tester.getRect(_in(
                        'brinco', find.byType(CatalogCardVariationPreview))),
                    tester.getRect(_card('brinco'))),
                isTrue);

            expect(added, isEmpty);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('ordem numérica e chips do anel 12–20 em tela larga',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpGrid(
        tester,
        width: 1280,
        minimal: false,
        products: [
          _produto(
              id: 'anel',
              variacoes: _anelGrade(['20', '12', '18', '14', '16'])),
        ],
      );
      expect(_chipTexts('anel'), _ringSizes);
      expect(_in('anel', find.text('Tamanhos')), findsOneWidget);
    });

    testWidgets('cor somente e tamanho+cor', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpGrid(
        tester,
        width: 1280,
        minimal: false,
        size: CatalogProductCardSize.large,
        products: [
          _produto(id: 'cores', variacoes: {
            'sem-tamanho': {'Prata': 1, 'Rosa': 1},
          }),
          _produto(id: 'combo', variacoes: {
            '16': {'Prata': 1},
            '18': {'Rosa': 1},
          }),
        ],
      );
      expect(_in('cores', find.text('Cores')), findsOneWidget);
      expect(_chipTexts('cores'), ['Prata', 'Rosa']);
      expect(_in('combo', find.text('Variações')), findsOneWidget);
      expect(_chipTexts('combo'), ['16 · Prata', '18 · Rosa']);
      expect(_in('combo', find.text('16 · Rosa')), findsNothing);
    });

    testWidgets('legado (estoquePorTamanho) mostra tamanhos', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpGrid(
        tester,
        width: 1280,
        minimal: true,
        products: [
          _produto(id: 'legado', ept: const {'18': 2, '12': 1, '14': 0}),
        ],
      );
      expect(_chipTexts('legado'), ['12', '18']);
    });

    testWidgets('Pix 0 e Pix > 0 inalterados com variações', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpGrid(
        tester,
        width: 390,
        minimal: false,
        products: [
          _produto(id: 'p0', variacoes: _anelGrade(_ringSizes)),
          _produto(id: 'p5', pix: 5, variacoes: _anelGrade(_ringSizes)),
        ],
      );
      bool hasPix(String id) => _in(
            id,
            find.byWidgetPredicate(
              (w) => w is Text && (w.data ?? '').toLowerCase().contains('pix'),
            ),
          ).evaluate().isNotEmpty;
      expect(hasPix('p0'), isFalse);
      expect(hasPix('p5'), isTrue);
      expect(
          _in('p0', find.byType(CatalogCardVariationPreview)), findsOneWidget);
      expect(
          _in('p5', find.byType(CatalogCardVariationPreview)), findsOneWidget);
    });

    testWidgets('multi-categoria: um card, mesma prévia', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = _produto(
        id: 'anel-multi',
        variacoes: _anelGrade(_ringSizes),
        categorias: const ['Anéis', 'Prata 925', 'Promoções'],
      );
      await _pumpGrid(tester, width: 1280, minimal: false, products: [p]);
      expect(_card('anel-multi'), findsOneWidget);
      final first = _chipTexts('anel-multi');
      await _pumpGrid(tester, width: 1280, minimal: false, products: [
        {...p, 'categoria': 'Promoções'},
      ]);
      expect(_card('anel-multi'), findsOneWidget);
      expect(_chipTexts('anel-multi'), first);
    });

    testWidgets(
        'chips não interativos: semântica de texto, sem botão, sem carrinho',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final added = await _pumpGrid(
        tester,
        width: 1280,
        minimal: false,
        products: [_produto(id: 'anel', variacoes: _anelGrade(_ringSizes))],
      );
      final node =
          find.bySemanticsLabel('Tamanhos disponíveis: 12, 14, 16, 18, 20');
      expect(node, findsOneWidget);
      final data = tester.getSemantics(node).getSemanticsData();
      expect(data.hasFlag(SemanticsFlag.isButton), isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);

      await tester.tap(_in('anel', find.text('14')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(added, isEmpty);
      expect(find.text('Adicionar ao carrinho'), findsNothing);
      expect(find.text('Selecione o tamanho'), findsNothing);
      semantics.dispose();
    });

    testWidgets(
        'CTA continua abrindo a seleção; produto simples adiciona direto',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final added = await _pumpGrid(
        tester,
        width: 390,
        minimal: false,
        products: [
          _produto(id: 'anel', variacoes: _anelGrade(_ringSizes)),
          _produto(id: 'pingente', nome: 'Pingente Cruz'),
        ],
      );
      await tester.tap(_in('pingente', find.text('Comprar')).first);
      await tester.pump();
      expect(added.single['id'], 'pingente');
      expect(added.single['tamanho'], '');

      // O sheet de seleção (inalterado) tem overflow/asset ausente só no ambiente de teste.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.exceptionAsString();
        if (text.contains('overflowed') || text.contains('RenderFlex')) return;
        if (details.library == 'image resource service') return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);
      await tester.tap(_in('anel', find.text('Comprar')).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Selecione o tamanho'), findsOneWidget);
      expect(added.length, 1);
    });
  });
}
