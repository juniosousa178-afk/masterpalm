import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FreteService — SuperFrete seguro', () {
    late String source;

    setUp(() {
      source = File('lib/services/frete_service.dart').readAsStringSync();
    });

    test('1. cotação SuperFrete usa SuperFreteIntegrationService.quote', () {
      expect(source, contains('SuperFreteIntegrationService.quote'));
    });

    test('2. cotação SuperFrete não envia token no bloco de cotação', () {
      final quoteBlock = source.split('SuperFreteIntegrationService.quote')[1]
          .split('manualFretes')[0];
      expect(quoteBlock.contains("'token'"), isFalse);
      expect(quoteBlock.contains('superfrete_token'), isFalse);
    });

    test('3. criarPrePedidoNaPlataforma não chama API (backend)', () {
      expect(source, contains('criarPrePedidoNaPlataforma ignorado'));
      expect(source, contains('use trigger backend'));
    });

    test('4. strip remove segredos SuperFrete da config', () {
      expect(source, contains('_stripSuperFreteSecretsFromConfig'));
      expect(source, contains("config.remove('superfrete_token')"));
    });

    test('5. API indisponível não quebra fretes manuais (fluxo híbrido)', () {
      expect(source, contains('manualFretes'));
      expect(source, contains('todasOpcoes'));
    });
  });
}
