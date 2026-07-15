// M3.8 HOTFIX-VENDEDOR-R3.2 — App Check soft-fail + never bare unknown.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/vendedor_create_flow.dart';

void main() {
  late String screenSrc;

  setUpAll(() {
    screenSrc = File('lib/screens/vendedores_screen.dart').readAsStringSync();
  });

  group('VENDOR-R32', () {
    test('R32-1 App Check secondary não bloqueia create', () {
      expect(VendorCreateFlow.appCheckFailureBlocksCreate(), isFalse);
      expect(
        screenSrc.contains('secondary-web-skip-nonblocking') ||
            screenSrc.contains('soft-fail'),
        isTrue,
      );
      expect(
        screenSrc.contains('_ativarAppCheckNoSecundario'),
        isTrue,
      );
      // Soft-fail catch presente (native) + skip web.
      expect(screenSrc.contains('app-check-skip-web-debug'), isTrue);
      expect(screenSrc.contains('soft-fail-continue') ||
          screenSrc.contains('appCheckSoftFailLogLine'), isTrue);
    });

    test('R32-2 falha App Check não rethrow no método secondary', () {
      // Após soft-fail o fluxo deve seguir para createUser.
      expect(screenSrc.contains("authStep = 'createUser'"), isTrue);
      expect(screenSrc.contains('createUserWithEmailAndPassword'), isTrue);
      // Não deve haver rethrow dentro de _ativarAppCheckNoSecundario.
      final start = screenSrc.indexOf('Future<void> _ativarAppCheckNoSecundario');
      final end = screenSrc.indexOf('Future<void> _cadastrarVendedor');
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final method = screenSrc.substring(start, end);
      expect(method.contains('rethrow'), isFalse);
    });

    test('R32-3 displayCode nunca é só unknown', () {
      final diag = VendorCreateFlow.captureAuthError(
        'FirebaseException without pattern',
        authStep: 'app-check',
      );
      final code = diag.displayCode();
      expect(code, isNot('unknown'));
      expect(code.contains('String') || code.contains('(resolved=unknown)'), isTrue);
    });

    test('R32-4 detailedFailureMessage traz Stage + Código + Mensagem', () {
      final diag = VendorCreateFlow.captureAuthError(
        Exception('attestation failed'),
        authStep: 'app-check',
      );
      final msg = VendorCreateFlow.detailedFailureMessage(
        diag: diag,
        stage: VendorCreateFlow.stageAuth,
      );
      expect(msg.contains('Stage:'), isTrue);
      expect(msg.contains('app-check'), isTrue);
      expect(msg.contains('Código:'), isTrue);
      expect(msg.contains('Mensagem:'), isTrue);
      expect(msg.trim(), isNot(equals('unknown')));
      // Nunca snack só "Código:\nunknown" sem contexto.
      expect(RegExp(r'Código:\s*\nunknown\s*$', multiLine: true).hasMatch(msg),
          isFalse);
    });

    test('R32-5 UX modal não fecha em erro + cadastrando', () {
      expect(VendorCreateFlow.mayCloseModalOnError(), isFalse);
      expect(screenSrc.contains('Cadastrando vendedor...'), isTrue);
      expect(screenSrc.contains('isDismissible: false'), isTrue);
      expect(screenSrc.contains('detailedFailureMessage'), isTrue);
    });
  });
}
