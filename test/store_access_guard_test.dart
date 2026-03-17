// test/store_access_guard_test.dart
// Testes para validação centralizada de lojaId.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/utils/store_access_guard.dart';

void main() {
  group('StoreAccessGuard', () {
    test('requireLojaId retorna valor trimado quando válido', () {
      expect(StoreAccessGuard.requireLojaId('  loja_a  '), 'loja_a');
      expect(StoreAccessGuard.requireLojaId('loja_a'), 'loja_a');
    });

    test('requireLojaId lança quando null', () {
      expect(
        () => StoreAccessGuard.requireLojaId(null),
        throwsA(isA<InvalidLojaIdException>()),
      );
    });

    test('requireLojaId lança quando vazio', () {
      expect(
        () => StoreAccessGuard.requireLojaId(''),
        throwsA(isA<InvalidLojaIdException>()),
      );
      expect(
        () => StoreAccessGuard.requireLojaId('   '),
        throwsA(isA<InvalidLojaIdException>()),
      );
    });

    test('validateLojaId retorna null para null ou vazio', () {
      expect(StoreAccessGuard.validateLojaId(null), isNull);
      expect(StoreAccessGuard.validateLojaId(''), isNull);
      expect(StoreAccessGuard.validateLojaId('  '), isNull);
    });

    test('validateLojaId retorna trimado quando válido', () {
      expect(StoreAccessGuard.validateLojaId(' loja_x '), 'loja_x');
    });
  });
}
