// Geometria do card sem variações (nome, preço/Pix, CTA, foto) comparada com o
// fixture gerado a partir do card de 1.0.146 (b0214c8): o card sem variação
// deve permanecer idêntico.
//
// Regenerar o fixture (somente a partir do card de referência):
//   MP_CARD_GEOMETRY_OUT=<arquivo> flutter test test/public_catalog/catalog_card_no_variation_geometry_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_product_card_size.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_image_placeholder.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_card.dart';

const _fixturePath =
    'test/public_catalog/fixtures/catalog_card_no_variation_geometry.json';

class GeometryCase {
  const GeometryCase(this.screenWidth, this.minimal, this.size, this.pix);
  final double screenWidth;
  final bool minimal;
  final String size;
  final double pix;

  String get id =>
      'w${screenWidth.toInt()}_${minimal ? 'minimal' : 'classic'}_${size}_pix${pix.toInt()}';
}

int gridCols(double w) => w >= 1024 ? 4 : (w >= 640 ? 3 : 2);

Size gridCellSize(double w, bool minimal, String size) {
  final cols = gridCols(w);
  final cellW = (w - 24 - 16 * (cols - 1)) / cols;
  double ratio;
  if (minimal) {
    ratio = CatalogProductCardSize.minimalAspectRatio(size);
    if (w >= 1024) ratio = (ratio + 0.045).clamp(0.30, 0.52);
  } else {
    ratio = CatalogProductCardSize.standardAspectRatio(size);
    if (w < 360) {
      ratio += 0.065;
    } else if (w < 640) {
      ratio += 0.04;
    }
  }
  return Size(cellW, cellW / ratio);
}

List<GeometryCase> geometryCases() {
  final out = <GeometryCase>[];
  for (final w in const [320.0, 360.0, 390.0, 412.0, 768.0, 1280.0]) {
    for (final minimal in const [true, false]) {
      for (final pix in const [0.0, 5.0]) {
        out.add(GeometryCase(w, minimal, CatalogProductCardSize.medium, pix));
      }
    }
  }
  for (final size in const [
    CatalogProductCardSize.small,
    CatalogProductCardSize.large,
  ]) {
    for (final minimal in const [true, false]) {
      out.add(GeometryCase(390, minimal, size, 5));
    }
  }
  return out;
}

Widget geometryCard(GeometryCase c, {Key? key}) {
  final cell = gridCellSize(c.screenWidth, c.minimal, c.size);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 8),
          child: SizedBox(
            width: cell.width,
            height: cell.height,
            child: CatalogProductCard(
              key: key,
              id: 'pingente-cruz',
              name: 'Pingente Cruz',
              lojaId: 'loja-teste',
              price: 89.9,
              imageUrl: '',
              imagens: const [],
              descricao: '',
              slug: 'pingente-cruz',
              percentualDescontoPix: c.pix,
              maxParcelas: 3,
              divideSemJuros: true,
              minimalLayout: c.minimal,
              classicMinimalCardVisual: !c.minimal,
              productCardSize: c.size,
              onAbrirCarrinho: () {},
              onAdd: (_) => true,
            ),
          ),
        ),
      ),
    ),
  );
}

List<double> _rect(WidgetTester tester, Finder f) {
  final r = tester.getRect(f);
  double q(double v) => (v * 100).roundToDouble() / 100;
  return [q(r.left), q(r.top), q(r.width), q(r.height)];
}

Map<String, Object> captureGeometry(WidgetTester tester, String name) {
  final out = <String, Object>{};
  out['image'] = _rect(tester, find.byType(CatalogImagePlaceholder).first);
  out['name'] = _rect(tester, find.text(name).first);
  out['price'] = _rect(tester, find.text('R\$ 89,90').first);
  final comprar = find.text('Comprar');
  out['comprar'] = [
    for (var i = 0; i < comprar.evaluate().length; i++)
      _rect(tester, comprar.at(i)),
  ];
  final cart = find.byIcon(Icons.shopping_cart_outlined);
  out['cart'] = [
    for (var i = 0; i < cart.evaluate().length; i++) _rect(tester, cart.at(i)),
  ];
  final pix = find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').toLowerCase().contains('pix'),
  );
  out['pix'] = [
    for (var i = 0; i < pix.evaluate().length; i++) _rect(tester, pix.at(i)),
  ];
  return out;
}

Future<void> pumpGeometryCase(WidgetTester tester, GeometryCase c) async {
  tester.view.physicalSize = Size(c.screenWidth, 1400);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(geometryCard(c));
  await tester.pump();
}

void main() {
  testWidgets('card sem variação: geometria idêntica ao card de 1.0.146',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final results = <String, Object>{};
    for (final c in geometryCases()) {
      await pumpGeometryCase(tester, c);
      expect(tester.takeException(), isNull, reason: c.id);
      results[c.id] = captureGeometry(tester, 'Pingente Cruz');
    }

    final outPath = Platform.environment['MP_CARD_GEOMETRY_OUT'];
    if (outPath != null && outPath.isNotEmpty) {
      File(outPath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(results),
      );
      return;
    }
    final expected = jsonDecode(File(_fixturePath).readAsStringSync())
        as Map<String, dynamic>;
    expect(results.keys.toSet(), expected.keys.toSet());
    for (final id in results.keys) {
      expect(jsonDecode(jsonEncode(results[id])), expected[id], reason: id);
    }
  });
}
