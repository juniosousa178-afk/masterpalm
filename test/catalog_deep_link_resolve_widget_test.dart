// Widget smoke: resolve produto deep link (?prod) com árvore mínima (MaterialApp + Text).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_deep_link_resolve.dart';

void main() {
  testWidgets(
    'deep link catálogo: resolve por slug/id normalizado e fallback seguro',
    (tester) async {
      final produtos = [
        {'id': 'abc-123', 'slug': 'meu-produto', 'nome': 'Alpha'},
        {'id': 'x', 'slug': '', 'nome': 'Beta'},
      ];

      Future<void> pumpTarget(String? target) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Text(
                resolveCatalogDeepLinkProduct(
                  produtos: produtos,
                  targetRaw: target,
                )?['nome']
                        ?.toString() ??
                    '__none__',
                textDirection: TextDirection.ltr,
              ),
            ),
          ),
        );
      }

      await pumpTarget('meu-produto');
      expect(find.text('Alpha'), findsOneWidget);

      await pumpTarget('abc-123');
      expect(find.text('Alpha'), findsOneWidget);

      // Normalização alinhada ao catálogo (slug com underscore vs hífen).
      await pumpTarget('meu_produto');
      expect(find.text('Alpha'), findsOneWidget);

      await pumpTarget('nao-existe');
      expect(find.text('__none__'), findsOneWidget);

      await pumpTarget(null);
      expect(find.text('__none__'), findsOneWidget);
    },
  );
}
