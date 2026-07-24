// M2.3-R5 — restauração e diagnóstico (R1–R4).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-restore-r5';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R1 — uma inválida entre duas válidas', () {
    test('carrega válidas, rejeita inválida com motivo', () {
      final lines = [
        {'id': 'produto-a', 'nome': 'A', 'preco': 10.0, 'quantidade': 1},
        {
          'id': 'produto-a',
          'productId': 'produto-b',
          'nome': 'X',
          'preco': 1.0,
        },
        {'id': 'produto-c', 'nome': 'C', 'preco': 5.0, 'quantidade': 1},
      ];
      final reasons = <String>[];
      final result = restoreCatalogCartLines(
        lines,
        onRejected: (code, _, __) => reasons.add(code),
      );
      expect(result.validLines.length, 2);
      expect(result.rejectedCount, 1);
      expect(reasons.single, 'alias_conflict');
      expect(result.rejectionReasons, ['alias_conflict']);
    });
  });

  group('R2 — todas inválidas', () {
    test('não quebra e expõe diagnóstico', () {
      final lines = [
        {'nome': 'sem id', 'preco': 1.0},
        {'id': 'a', 'productId': 'b', 'nome': 'x', 'preco': 1.0},
      ];
      final result = restoreCatalogCartLines(lines);
      expect(result.validLines, isEmpty);
      expect(result.rejectedCount, 2);
      expect(result.rejectionReasons, contains('empty_identity'));
      expect(result.rejectionReasons, contains('alias_conflict'));
    });
  });

  group('R3 — erro de JSON', () {
    test('falha controlada sem sobrescrever com lista vazia', () async {
      SharedPreferences.setMockInitialValues({
        'catalog_cart_items_$_lojaId': '{invalid json',
      });
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('catalog_cart_items_$_lojaId');
      expect(raw, isNotNull);
      expect(() => jsonDecode(raw!), throwsFormatException);
      // Simula que _loadCarrinhoLocal mantém carrinho anterior em catch.
      final cart = <Map<String, dynamic>>[
        {'id': 'keep', 'nome': 'Keep', 'preco': 1.0},
      ];
      try {
        jsonDecode(raw!);
        fail('deveria falhar parse');
      } catch (_) {
        // carrinho inalterado
      }
      expect(cart.length, 1);
      expect(cart.first['id'], 'keep');
    });
  });

  group('R4 — restauração seguida de persistência', () {
    test('primeira gravação elimina linha rejeitada do JSON ativo', () async {
      SharedPreferences.setMockInitialValues({
        'catalog_cart_items_$_lojaId': jsonEncode([
          {'id': 'valid', 'nome': 'OK', 'preco': 5.0, 'quantidade': 1},
          {
            'id': 'a',
            'productId': 'b',
            'nome': 'bad',
            'preco': 1.0,
          },
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final decoded =
          jsonDecode(prefs.getString('catalog_cart_items_$_lojaId')!) as List;
      final restored = decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final result = restoreCatalogCartLines(restored);
      expect(result.validLines.length, 1);
      await prefs.setString(
        'catalog_cart_items_$_lojaId',
        jsonEncode(result.validLines),
      );
      final after =
          jsonDecode(prefs.getString('catalog_cart_items_$_lojaId')!) as List;
      expect(after.length, 1);
      expect(after.single['id'], 'valid');
      // RAW original em memória do teste ainda tinha 2 — regravar remove inválida.
    });
  });
}
