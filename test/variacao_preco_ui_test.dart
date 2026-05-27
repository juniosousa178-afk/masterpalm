import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/screens/nova_venda/variacao_selection_sheet.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_product_variation_pick_body.dart';

Produto _produtoComPrecosPorTamanho() {
  return Produto(
    nome: 'Colar Teste',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 49.9,
    quantidade: 5,
    precoUnitario: 49.9,
    categoria: 'Teste',
    dataEntrada: DateTime(2026, 5, 26),
    estoquePorTamanho: const {
      '45 cm': 2,
      '45 + 5 cm': 2,
      '60 cm': 1,
    },
    precoPorTamanho: const {
      '45 cm': 49.9,
      '45 + 5 cm': 52.9,
      '60 cm': 59.9,
    },
  );
}

Produto _produtoComLabelsSemEspacoEPrecosComEspaco() {
  return Produto(
    nome: 'Correntes Veneziana V 15',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 73.9,
    quantidade: 5,
    precoUnitario: 73.9,
    categoria: 'Teste',
    dataEntrada: DateTime(2026, 5, 26),
    estoquePorTamanho: const {
      '45cm': 2,
      '40cm': 2,
      '60cm': 1,
    },
    precoPorTamanho: const {
      '45 cm': 49.9,
      '40 cm': 52.9,
      '60 cm': 59.9,
    },
  );
}

Produto _produtoComLabelsComEspacoEPrecosSemEspaco() {
  return Produto(
    nome: 'Correntes Veneziana V 15',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 73.9,
    quantidade: 5,
    precoUnitario: 73.9,
    categoria: 'Teste',
    dataEntrada: DateTime(2026, 5, 26),
    estoquePorTamanho: const {
      '45 cm': 2,
    },
    precoPorTamanho: const {
      '45cm': 49.9,
    },
  );
}

Produto _produtoComFallbackPrecoFinal() {
  return Produto(
    nome: 'Correntes Veneziana V 15',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 73.9,
    quantidade: 5,
    precoUnitario: 70.0,
    categoria: 'Teste',
    dataEntrada: DateTime(2026, 5, 26),
    estoquePorTamanho: const {
      '45cm': 2,
    },
    precoPorTamanho: const {
      '60 cm': 59.9,
    },
  );
}

Produto _produtoComFallbackPrecoUnitario() {
  return Produto(
    nome: 'Correntes Veneziana V 15',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 0,
    quantidade: 5,
    precoUnitario: 73.9,
    categoria: 'Teste',
    dataEntrada: DateTime(2026, 5, 26),
    estoquePorTamanho: const {
      '45cm': 2,
    },
    precoPorTamanho: const {
      '60 cm': 59.9,
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Preço por variação na UI', () {
    testWidgets(
      'NovaVendaVariacaoSheet recalcula preço e total ao trocar o tamanho',
      (tester) async {
        final produto = _produtoComPrecosPorTamanho();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NovaVendaVariacaoSheet(
                produto: produto,
                preco: produto.precoFinal,
                onConfirmar: (
                  tamanho,
                  cor,
                  quantidade,
                  extraValor,
                  resumo,
                ) {},
              ),
            ),
          ),
        );

        await tester.tap(find.text('45 + 5 cm'));
        await tester.pumpAndSettle();

        expect(find.text('R\$ 52,90'), findsOneWidget);
        expect(find.text('Adicionar (R\$ 52,90)'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.add_circle_outline));
        await tester.pumpAndSettle();

        expect(find.text('Adicionar (R\$ 105,80)'), findsOneWidget);
      },
    );

    testWidgets(
      'NovaVendaVariacaoSheet encontra preco por tamanho com label sem espaco',
      (tester) async {
        final produto = _produtoComLabelsSemEspacoEPrecosComEspaco();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NovaVendaVariacaoSheet(
                produto: produto,
                preco: produto.precoFinal,
                onConfirmar: (
                  tamanho,
                  cor,
                  quantidade,
                  extraValor,
                  resumo,
                ) {},
              ),
            ),
          ),
        );

        await tester.tap(find.text('45cm'));
        await tester.pumpAndSettle();
        expect(find.text('R\$ 49,90'), findsOneWidget);
        expect(find.text('Adicionar (R\$ 49,90)'), findsOneWidget);

        await tester.tap(find.text('40cm'));
        await tester.pumpAndSettle();
        expect(find.text('R\$ 52,90'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.add_circle_outline));
        await tester.pumpAndSettle();
        expect(find.text('Adicionar (R\$ 105,80)'), findsOneWidget);

        await tester.tap(find.text('60cm'));
        await tester.pumpAndSettle();
        expect(find.text('R\$ 59,90'), findsOneWidget);
      },
    );

    testWidgets(
      'NovaVendaVariacaoSheet encontra preco por tamanho no sentido inverso',
      (tester) async {
        final produto = _produtoComLabelsComEspacoEPrecosSemEspaco();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NovaVendaVariacaoSheet(
                produto: produto,
                preco: produto.precoFinal,
                onConfirmar: (
                  tamanho,
                  cor,
                  quantidade,
                  extraValor,
                  resumo,
                ) {},
              ),
            ),
          ),
        );

        await tester.tap(find.text('45 cm'));
        await tester.pumpAndSettle();

        expect(find.text('R\$ 49,90'), findsOneWidget);
        expect(find.text('Adicionar (R\$ 49,90)'), findsOneWidget);
      },
    );

    testWidgets(
      'NovaVendaVariacaoSheet usa fallback precoFinal sem chave compativel',
      (tester) async {
        final produto = _produtoComFallbackPrecoFinal();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NovaVendaVariacaoSheet(
                produto: produto,
                preco: produto.precoFinal,
                onConfirmar: (
                  tamanho,
                  cor,
                  quantidade,
                  extraValor,
                  resumo,
                ) {},
              ),
            ),
          ),
        );

        await tester.tap(find.text('45cm'));
        await tester.pumpAndSettle();

        expect(find.text('R\$ 73,90'), findsOneWidget);
        expect(find.text('Adicionar (R\$ 73,90)'), findsOneWidget);
      },
    );

    testWidgets(
      'NovaVendaVariacaoSheet usa fallback precoUnitario sem precoFinal',
      (tester) async {
        final produto = _produtoComFallbackPrecoUnitario();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NovaVendaVariacaoSheet(
                produto: produto,
                preco: produto.precoUnitario,
                onConfirmar: (
                  tamanho,
                  cor,
                  quantidade,
                  extraValor,
                  resumo,
                ) {},
              ),
            ),
          ),
        );

        await tester.tap(find.text('45cm'));
        await tester.pumpAndSettle();

        expect(find.text('R\$ 73,90'), findsOneWidget);
        expect(find.text('Adicionar (R\$ 73,90)'), findsOneWidget);
      },
    );

    testWidgets(
      'CatalogProductVariationPickBody envia o preço do tamanho selecionado ao carrinho',
      (tester) async {
        final produto = _produtoComPrecosPorTamanho();
        double? precoCapturado;
        String? tamanhoCapturado;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 420,
                child: CatalogProductVariationPickBody(
                  name: produto.nome,
                  price: produto.precoFinal,
                  emPromocao: false,
                  imageUrl: '',
                  estoquePorTamanho: produto.estoquePorTamanho,
                  estoquePorCor: const {},
                  precoPorTamanho: produto.precoPorTamanho,
                  onPickCommit: (tamanho, cor, preco, extraValor, extraTipo) {
                    tamanhoCapturado = tamanho;
                    precoCapturado = preco;
                  },
                  showProductSnippet: false,
                  showAddToCartButton: true,
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('60 cm'));
        await tester.pumpAndSettle();

        expect(find.text('R\$ 59,90'), findsOneWidget);

        await tester.tap(find.text('Adicionar ao carrinho'));
        await tester.pumpAndSettle();

        expect(tamanhoCapturado, '60 cm');
        expect(precoCapturado, 59.9);
      },
    );
  });
}
