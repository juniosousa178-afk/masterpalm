// M2.3-R4 — proteção _asyncGeneration (callback tardio coerente com A ignorado em B).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_variation_pick_body.dart';

const _tamA = 'coracao-rosa';
const _tamB = '45cm-v12';

Map<String, dynamic> _produtoA() => {
      'id': 'produto-a',
      'nome': 'Colar Coração Cravejado Rosa',
      'preco': 99.90,
      'estoquePorTamanho': {_tamA: 3},
    };

Map<String, dynamic> _produtoB() => {
      'id': 'produto-b',
      'nome': 'Colar Ponto de Luz Gota 45cm',
      'preco': 79.90,
      'estoquePorTamanho': {_tamB: 5},
    };

void main() {
  testWidgets(
      '_asyncGeneration ignora callback tardio coerente com A após troca para B',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final staleGate = Completer<void>();
    Map<String, dynamic>? lastCommit;
    var current = _produtoA();
    var phase = 0;

    Future<void> pumpPick() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        current = _produtoB();
                        phase = 1;
                      }),
                      child: const Text('SWITCH_TO_B'),
                    ),
                    Expanded(
                      child: CatalogProductVariationPickBody(
                        key: ValueKey('pick-$phase'),
                        productId: current['id'] as String,
                        name: current['nome'] as String,
                        price: (current['preco'] as num).toDouble(),
                        emPromocao: false,
                        imageUrl: 'https://cdn.example/${current['id']}.jpg',
                        estoquePorTamanho: Map<String, int>.from(
                          current['estoquePorTamanho'] as Map,
                        ),
                        estoquePorCor: const {},
                        variacoes: phase == 0
                            ? {
                                _tamA: {'rosa': 2, 'extra-a': 1},
                              }
                            : null,
                        variacoesExtraTipo: phase == 0
                            ? const {'extra-a': 'texto'}
                            : null,
                        initialExtraValor:
                            phase == 0 ? 'extra-a' : null,
                        onCatalogVariacaoExtraChanged: (v) async {
                          await staleGate.future;
                        },
                        onPickCommit: (tam, cor, preco, extra, tipo) {
                          lastCommit = {
                            'productId': current['id'],
                            'nome': current['nome'],
                            'tamanho': tam,
                            'cor': cor,
                            'preco': preco,
                            'extra': extra,
                          };
                        },
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
      await tester.pumpAndSettle();
    }

    await pumpPick();
    await tester.tap(find.text(_tamA));
    await tester.pump();
    await tester.tap(find.text('SWITCH_TO_B'));
    await tester.pump();
    staleGate.complete();
    await tester.pumpAndSettle();

    final state = tester.state<CatalogProductVariationPickBodyState>(
      find.byType(CatalogProductVariationPickBody),
    );
    expect(state.widget.productId, 'produto-b');
    expect(state.widget.name, 'Colar Ponto de Luz Gota 45cm');
    expect(state.podeAdicionarVariacao, isFalse);

    await tester.tap(find.text(_tamB));
    await tester.pumpAndSettle();
    expect(state.podeAdicionarVariacao, isTrue);
    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pumpAndSettle();

    expect(lastCommit, isNotNull);
    expect(lastCommit!['productId'], 'produto-b');
    expect(lastCommit!['nome'], 'Colar Ponto de Luz Gota 45cm');
    expect(lastCommit!['tamanho'], _tamB);
    expect(lastCommit!['tamanho'], isNot(_tamA));
    expect(lastCommit!['preco'], closeTo(79.90, 0.01));
  });
}
