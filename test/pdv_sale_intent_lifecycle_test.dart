import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/pdv_sale_intent_lifecycle.dart';
import 'package:master_palm/core/venda_finalizacao_reentrada_guard.dart';

void main() {
  group('PdvSaleIntentLifecycle — UI', () {
    test('UI-1 primeira finalização cria saleIntentId', () {
      final lc = PdvSaleIntentLifecycle();
      expect(lc.activeId, isNull);
      final id = lc.ensureForAttempt();
      expect(id, isNotEmpty);
      expect(lc.activeId, id);
    });

    test('UI-2 duplo clique bloqueado não cria segunda intent', () {
      final guard = VendaFinalizacaoReentradaGuard();
      final lc = PdvSaleIntentLifecycle();
      expect(guard.tentarIniciar(), isTrue);
      expect(guard.tentarIniciar(), isFalse);
      final id1 = lc.ensureForAttempt();
      expect(lc.ensureForAttempt(), id1);
      guard.liberar();
    });

    test('UI-3 erro recuperável mantém saleIntentId para retry', () {
      final lc = PdvSaleIntentLifecycle();
      final id = lc.ensureForAttempt();
      expect(lc.ensureForAttempt(), id);
    });

    test('UI-4 sucesso limpa saleIntentId', () {
      final lc = PdvSaleIntentLifecycle();
      lc.ensureForAttempt();
      lc.clearOnSuccess();
      expect(lc.activeId, isNull);
      final novo = lc.ensureForAttempt();
      expect(novo, isNotEmpty);
    });

    test('UI-5 nova tentativa após clear recebe nova saleIntentId', () {
      final lc = PdvSaleIntentLifecycle();
      final id1 = lc.ensureForAttempt();
      lc.clearOnSuccess();
      final id2 = lc.ensureForAttempt();
      expect(id2, isNot(equals(id1)));
    });

    test('UI-6 mesma tentativa não gera nova intent silenciosa', () {
      final lc = PdvSaleIntentLifecycle();
      final id = lc.ensureForAttempt();
      expect(lc.ensureForAttempt(), id);
      expect(lc.ensureForAttempt(), id);
    });
  });
}
