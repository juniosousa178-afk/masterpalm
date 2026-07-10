// M3.7-HOMOLOG-FINAL — ROLETAUI card vendedor

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/widgets/premio_roleta_vendedor_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ROLETAUI — card pré-pedido vendedor', () {
    testWidgets('ROLETAUI-1 percentual', (tester) async {
      await tester.pumpWidget(wrap(const PremioRoletaVendedorCard(
        premioRaw: {
          'tipo': 'desconto',
          'codigo': 'CUP10',
          'valor': 10,
          'descricao': '10% OFF',
          'status': 'pendente',
        },
      )));
      expect(find.textContaining('10% de desconto'), findsOneWidget);
      expect(find.textContaining('CUP10'), findsOneWidget);
      expect(find.textContaining('Cupom de 0%'), findsNothing);
    });

    testWidgets('ROLETAUI-2 valor fixo', (tester) async {
      await tester.pumpWidget(wrap(const PremioRoletaVendedorCard(
        premioRaw: {
          'tipo': 'valor_fixo',
          'codigo': 'R10',
          'valor': 10,
          'descricao': 'R\$ 10,00 OFF',
        },
      )));
      expect(find.textContaining('R\$ 10,00 de desconto'), findsOneWidget);
    });

    testWidgets('ROLETAUI-3 frete grátis', (tester) async {
      await tester.pumpWidget(wrap(const PremioRoletaVendedorCard(
        premioRaw: {
          'tipo': 'frete_gratis',
          'codigo': 'FRETE_GRATIS',
          'valor': 0,
          'descricao': 'Frete grátis',
        },
      )));
      expect(find.textContaining('Frete grátis'), findsWidgets);
    });

    testWidgets('ROLETAUI-4 sem prêmio', (tester) async {
      await tester.pumpWidget(wrap(const PremioRoletaVendedorCard(
        premioRaw: null,
      )));
      expect(find.text('Prêmio da roleta'), findsNothing);
    });

    testWidgets('ROLETAUI-5 payload legado valor 0 + descricao', (tester) async {
      await tester.pumpWidget(wrap(const PremioRoletaVendedorCard(
        premioRaw: {
          'tipo': 'desconto',
          'codigo': 'LEG',
          'valor': 0,
          'descricao': '20% OFF',
        },
      )));
      expect(find.textContaining('20% de desconto'), findsOneWidget);
      expect(find.textContaining('Tipo: 0%'), findsNothing);
    });

    testWidgets('ROLETAUI-6 status usado', (tester) async {
      await tester.pumpWidget(wrap(const PremioRoletaVendedorCard(
        premioRaw: {
          'tipo': 'desconto',
          'codigo': 'X',
          'valor': 5,
          'status': 'usado',
          'valido': false,
        },
      )));
      expect(find.textContaining('Status: Usado'), findsOneWidget);
    });
  });
}
