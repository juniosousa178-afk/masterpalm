import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fretes_cupons_screen — UI e fluxo seguro', () {
    late String source;

    setUp(() {
      source = File('lib/screens/fretes_cupons_screen.dart').readAsStringSync();
    });

    test('1. não chama api.superfrete.com', () {
      expect(source.contains('api.superfrete.com'), isFalse);
    });

    test('2. não pré-preenche token do Hive no bootstrap', () {
      expect(source, contains('_superFreteTokenCtrl.clear()'));
      expect(source.contains('frete_superfrete_token'), isTrue);
      expect(
        source.contains('_superFreteTokenCtrl.text ='),
        isFalse,
        reason: 'token não deve ser carregado no controller',
      );
    });

    test('3. token mascarado no status', () {
      expect(source, contains('maskedToken'));
      expect(source, contains('Token configurado:'));
    });

    test('4. após salvar limpa controller e Hive', () {
      expect(source, contains('_superFreteTokenCtrl.clear()'));
      expect(source, contains("await _putConfig('frete_superfrete_token', '');"));
    });

    test('5. documento público sem token SuperFrete', () {
      expect(source, contains("'integrations'"));
      expect(source, contains("FieldValue.delete()"));
      expect(source.contains("'superfrete': {\n            'token'"), isFalse);
    });

    test('6. mensagem de integração configurada com segurança', () {
      expect(source, contains('A integração foi configurada com segurança.'));
    });

    test('7. CORS/fetch não aparece em SnackBar de SuperFrete', () {
      final testBlock = source.split('Future<void> _testarSuperFrete')[1].split('Future<void> _testarCorreios')[0];
      expect(testBlock.contains('Failed to fetch'), isFalse);
      expect(testBlock.contains('ClientException'), isFalse);
      expect(testBlock.contains('\$e'), isFalse);
    });
  });
}
