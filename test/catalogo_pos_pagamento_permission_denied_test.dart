import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Diagnóstico estático: coleções usadas no pós-pagamento vs firestore.rules.
void main() {
  group('Catálogo pós-pagamento — permission-denied (rules)', () {
    late String rules;

    setUp(() {
      rules = File('firestore.rules').readAsStringSync();
    });

    test('estoque_baixa_pagamento tem match nas rules (deploy 3305805)', () {
      expect(rules, contains('match /estoque_baixa_pagamento/{vendaId}'));
      expect(rules, contains('allow read: if belongsToStore(lojaId);'));
      expect(rules, contains('allow create, update: if belongsToStore(lojaId)'));
      expect(rules, contains('request.resource.data.lojaId == lojaId'));
    });

    test('estoque_produtos permite write para belongsToStore', () {
      expect(rules, contains('match /estoque_produtos/{prodId}'));
      expect(rules, contains('allow read, write: if belongsToStore(lojaId);'));
    });

    test('produtos só permite update de vendasCatalogoTotal para loja (não espelho de estoque)', () {
      expect(rules, contains('isVendasCatalogoTotalOnlySafeUpdate'));
    });

    test('pre_pedidos update de confirmação exige admin ou governança', () {
      expect(rules, contains('match /pre_pedidos/{pedidoId}'));
      expect(rules, contains('isValidPrePedidoGovernancaSubstituicao'));
      // confirmarPrePedido escreve status/vendaId — só passa com isAdminOrSystem().
    });
  });
}
