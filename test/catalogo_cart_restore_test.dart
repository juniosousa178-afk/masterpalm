// M2.3-R4 — persistência/restauração carrinho (11.1–11.3).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-restore-r4';
const _nomeA = 'Colar Coração';
const _nomeB = 'Colar Gota';
const _tamA = 'coracao-rosa';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('11.1 — linha antiga coerente', () {
    test('schema legado restaura sem alterar nome/preço', () {
      final legacy = {
        'id': 'produto-a',
        'nome': _nomeA,
        'preco': 120.0,
        'quantidade': 1,
        'tamanho': _tamA,
      };
      final restored = filterStructurallyValidCatalogCartLines([legacy]);
      expect(restored.length, 1);
      expect(restored.single['nome'], _nomeA);
      expect((restored.single['preco'] as num).toDouble(), 120.0);
    });
  });

  group('11.2 — aliases conflitantes persistidos', () {
    test('não insere linha com id/productId conflitantes', () async {
      SharedPreferences.setMockInitialValues({
        'catalog_cart_items_$_lojaId': jsonEncode([
          {
            'id': 'produto-a',
            'productId': 'produto-b',
            'nome': 'X',
            'preco': 10.0,
            'quantidade': 1,
          },
          {
            'id': 'produto-valido',
            'nome': 'OK',
            'preco': 5.0,
            'quantidade': 1,
          },
        ]),
      });

      final rejected = <String>[];
      final cart = <Map<String, dynamic>>[];
      final json = (await SharedPreferences.getInstance())
          .getString('catalog_cart_items_$_lojaId');
      final decoded = jsonDecode(json!) as List;
      for (final e in decoded) {
        if (e is Map) cart.add(Map<String, dynamic>.from(e));
      }
      final valid = filterStructurallyValidCatalogCartLines(
        cart,
        onRejected: (code, _, __) => rejected.add(code),
      );

      expect(rejected, contains('alias_conflict'));
      expect(valid.length, 1);
      expect(valid.single['id'], 'produto-valido');
    });
  });

  group('11.3 — contaminação semântica persistida', () {
    test('PERSISTED_CONTAMINATION_PROPAGATED — restauração não detecta', () {
      final contaminated = {
        'id': 'produto-b',
        'productId': 'produto-b',
        'nome': _nomeA,
        'preco': 79.90,
        'quantidade': 1,
        'tamanho': _tamA,
      };
      final restored =
          filterStructurallyValidCatalogCartLines([contaminated]);
      expect(restored.length, 1);
      expect(restored.single['nome'], _nomeA);
      expect(restored.single['productId'], 'produto-b');
      // Este teste não reproduz a origem na UI — apenas propagação pós-restore.
    });
  });
}
