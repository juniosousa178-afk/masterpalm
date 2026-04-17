import 'package:flutter/material.dart';

/// Após adicionar ao carrinho (ex.: combo): `true` = ir ao carrinho; `false` = continuar comprando (ou dismiss).
Future<bool> showCatalogAfterAddChoiceDialog(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        icon: Icon(
          Icons.shopping_cart_checkout_outlined,
          color: theme.colorScheme.primary,
          size: 32,
        ),
        title: const Text('Adicionado ao carrinho'),
        content: const Text(
          'O que deseja fazer agora?',
          style: TextStyle(height: 1.35),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuar comprando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ir para o carrinho'),
          ),
        ],
      );
    },
  );
  return r == true;
}
