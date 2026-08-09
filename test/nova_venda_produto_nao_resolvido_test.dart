// Testa validação de produtos não resolvidos na finalização da venda

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validação de produtos não resolvidos', () {
    test('produto com texto mas sem productId é rejeitado', () {
      final itens = [
        {
          'produto': 'Produto Teste',
          'quantidade': 1,
          'preco': 0.0,
        },
      ];

      final temNaoResolvido = itens.any((item) {
        final produtoNome = (item['produto'] ?? '').toString().trim();
        if (produtoNome.isNotEmpty) {
          final productId = (item['productId'] as String?)?.trim();
          if (productId == null || productId.isEmpty) {
            return true;
          }
        }
        return false;
      });

      expect(temNaoResolvido, isTrue);
    });

    test('produto com productId válido é aceito', () {
      final itens = [
        {
          'produto': 'Produto Teste',
          'quantidade': 1,
          'preco': 49.90,
          'productId': 'produto-123',
        },
      ];

      final temNaoResolvido = itens.any((item) {
        final produtoNome = (item['produto'] ?? '').toString().trim();
        if (produtoNome.isNotEmpty) {
          final productId = (item['productId'] as String?)?.trim();
          if (productId == null || productId.isEmpty) {
            return true;
          }
        }
        return false;
      });

      expect(temNaoResolvido, isFalse);
    });

    test('linha vazia não bloqueia finalização', () {
      final itens = [
        {
          'produto': '',
          'quantidade': 1,
          'preco': 0.0,
        },
      ];

      final temNaoResolvido = itens.any((item) {
        final produtoNome = (item['produto'] ?? '').toString().trim();
        if (produtoNome.isNotEmpty) {
          final productId = (item['productId'] as String?)?.trim();
          if (productId == null || productId.isEmpty) {
            return true;
          }
        }
        return false;
      });

      expect(temNaoResolvido, isFalse);
    });

    test('produto com preço zero real mas productId válido é aceito', () {
      final itens = [
        {
          'produto': 'Produto Brinde',
          'quantidade': 1,
          'preco': 0.0,
          'productId': 'produto-brinde',
        },
      ];

      final temNaoResolvido = itens.any((item) {
        final produtoNome = (item['produto'] ?? '').toString().trim();
        if (produtoNome.isNotEmpty) {
          final productId = (item['productId'] as String?)?.trim();
          if (productId == null || productId.isEmpty) {
            return true;
          }
        }
        return false;
      });

      expect(temNaoResolvido, isFalse);
    });

    test('múltiplos produtos - um não resolvido bloqueia', () {
      final itens = [
        {
          'produto': 'Produto Resolvido',
          'quantidade': 1,
          'preco': 100.0,
          'productId': 'produto-1',
        },
        {
          'produto': 'Produto Não Resolvido',
          'quantidade': 1,
          'preco': 0.0,
        },
      ];

      final temNaoResolvido = itens.any((item) {
        final produtoNome = (item['produto'] ?? '').toString().trim();
        if (produtoNome.isNotEmpty) {
          final productId = (item['productId'] as String?)?.trim();
          if (productId == null || productId.isEmpty) {
            return true;
          }
        }
        return false;
      });

      expect(temNaoResolvido, isTrue);
    });

    test('todos produtos resolvidos - permite finalização', () {
      final itens = [
        {
          'produto': 'Produto 1',
          'quantidade': 1,
          'preco': 50.0,
          'productId': 'produto-1',
        },
        {
          'produto': 'Produto 2',
          'quantidade': 2,
          'preco': 75.0,
          'productId': 'produto-2',
        },
      ];

      final temNaoResolvido = itens.any((item) {
        final produtoNome = (item['produto'] ?? '').toString().trim();
        if (produtoNome.isNotEmpty) {
          final productId = (item['productId'] as String?)?.trim();
          if (productId == null || productId.isEmpty) {
            return true;
          }
        }
        return false;
      });

      expect(temNaoResolvido, isFalse);
    });
  });
}
