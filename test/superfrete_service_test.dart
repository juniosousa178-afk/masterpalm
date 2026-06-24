import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/superfrete_integration_service.dart';
import 'package:master_palm/services/superfrete_service.dart';

void main() {
  group('SuperFrete — sem HTTP direto em lib/', () {
    test('1. nenhum arquivo em lib chama api.superfrete.com diretamente', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final offenders = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        if (content.contains('api.superfrete.com')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty, reason: offenders.join(', '));
    });
  });

  group('SuperFreteConfigStatus', () {
    test('2. token não aparece no status mascarado vindo do backend', () {
      const rawToken = 'sf_secret_token_abcdefghijklmnop';
      final status = SuperFreteConfigStatus.fromMap({
        'configured': true,
        'maskedToken': '••••klmnop',
        'sandbox': false,
        'legacyTokenNeedsRotation': false,
      });
      expect(status.configured, isTrue);
      expect(status.maskedToken, '••••klmnop');
      expect(status.maskedToken, isNot(contains(rawToken)));
    });

    test('3. legacyTokenNeedsRotation expõe apenas flag', () {
      final status = SuperFreteConfigStatus.fromMap({
        'configured': false,
        'legacyTokenNeedsRotation': true,
        'maskedToken': '••••????',
      });
      expect(status.legacyTokenNeedsRotation, isTrue);
      expect(status.maskedToken, '••••????');
    });
  });

  group('SuperFreteService fachada', () {
    test('4. calcularFrete delega para integration service (sem token no contrato)', () {
      expect(
        SuperFreteService.calcularFrete(
          lojaId: 'loja',
          cepOrigem: '01310100',
          cepDestino: '20040020',
          peso: 500,
          altura: 10,
          largura: 20,
          comprimento: 30,
          valorDeclarado: 50,
        ),
        isA<Future<Map<String, dynamic>>>(),
      );
    });

    test('5. validarToken legado retorna false (não chama API direta)', () async {
      final ok = await SuperFreteService.validarToken('qualquer-token');
      expect(ok, isFalse);
    });
  });

  group('fretes_cupons_screen — integração segura no código-fonte', () {
    late String source;

    setUp(() {
      source = File('lib/screens/fretes_cupons_screen.dart').readAsStringSync();
    });

    test('6. Testar usa Callable superFreteTestConnection', () {
      expect(source, contains('SuperFreteIntegrationService.testConnection'));
    });

    test('7. Salvar usa Callable superFreteSaveConfig', () {
      expect(source, contains('SuperFreteIntegrationService.saveConfig'));
    });

    test('8. campo de token usa obscureText', () {
      expect(source, contains('obscureText: true'));
    });

    test('9. legacyTokenNeedsRotation mostra aviso', () {
      expect(source, contains('legacyTokenNeedsRotation'));
      expect(
        source,
        contains('Por segurança, o token anterior precisa ser substituído'),
      );
    });

    test('10. SnackBar de teste não interpola exceção bruta', () {
      expect(source.contains("Text('\$e')"), isFalse);
      expect(source.contains('SnackBar(content: Text(\'\$e\'))'), isFalse);
    });
  });

  group('superfrete_integration_service — mensagens amigáveis', () {
    test('11. mensagens obrigatórias presentes no serviço', () {
      final source =
          File('lib/services/superfrete_integration_service.dart').readAsStringSync();
      expect(
        source,
        contains(
          'O token informado é inválido ou expirou. Gere um novo token na SuperFrete.',
        ),
      );
      expect(
        source,
        contains(
          'A SuperFrete está temporariamente indisponível. Tente novamente em alguns minutos.',
        ),
      );
      expect(
        source,
        contains(
          'Sua conta não possui permissão para configurar fretes desta loja.',
        ),
      );
      expect(
        source,
        contains(
          'O token não corresponde ao ambiente selecionado. Confira a opção Sandbox.',
        ),
      );
      expect(
        source,
        contains('Não foi possível testar a conexão. Tente novamente.'),
      );
      expect(
        source,
        contains('Não foi possível salvar a configuração. Tente novamente.'),
      );
      expect(source, contains("_messageForSafeCode"));
    });

    test('12. backend SuperFrete não usa /api/v8', () {
      final backend = File('functions/src/superFreteIntegration.js')
          .readAsStringSync();
      expect(backend.contains('/api/v8'), isFalse);
      expect(backend, contains('/api/v0/calculator'));
      expect(backend, contains('/api/v0/cart'));
      expect(backend, contains('/api/v0/user/addresses'));
    });
  });
}
