// M3.8 HOTFIX-VENDEDOR-R3.1-DIAG — mapeamento de catches / unknown (somente diag).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/vendedor_create_flow.dart';

void main() {
  late String screenSrc;
  late String flowSrc;
  late String serviceSrc;

  setUpAll(() {
    screenSrc = File('lib/screens/vendedores_screen.dart').readAsStringSync();
    flowSrc = File('lib/core/vendedor_create_flow.dart').readAsStringSync();
    serviceSrc = File('lib/services/vendedor_service.dart').readAsStringSync();
  });

  group('VENDOR-R31-DIAG', () {
    test('R31-1 fluxo UI usa sheet local (não service.cadastrar na UI)', () {
      expect(screenSrc.contains('_cadastrarVendedor'), isTrue);
      expect(screenSrc.contains('createUserWithEmailAndPassword'), isTrue);
      expect(screenSrc.contains("Firebase.app('secondary')"), isTrue);
      // UI não chama VendedorService.cadastrarVendedor
      expect(
        screenSrc.contains('_vendedorService.cadastrarVendedor'),
        isFalse,
      );
    });

    test('R31-2 authSteps instrumentados', () {
      for (final step in [
        'secondary-app',
        'secondary-app-ok',
        'app-check',
        'app-check-ok',
        'createUser',
        'createUser-ok',
      ]) {
        expect(screenSrc.contains(step), isTrue, reason: 'missing $step');
      }
    });

    test('R31-3 firstCatch sites existem', () {
      expect(
        screenSrc.contains('vendedores_screen._ensureSecondaryApp'),
        isTrue,
      );
      expect(
        screenSrc.contains(
          'vendedores_screen._cadastrarVendedor.onFirebaseAuthException',
        ),
        isTrue,
      );
      expect(
        screenSrc.contains('vendedores_screen._cadastrarVendedor.catch'),
        isTrue,
      );
    });

    test('R31-4 log fields R3.1 presentes', () {
      for (final k in [
        'runtimeType=',
        'firebaseCode=',
        'firebaseMessage=',
        'firebaseAuthCode=',
        'platformCode=',
        'platformMessage=',
        'toString=',
        'stack=',
        'unknownOrigin=',
      ]) {
        expect(flowSrc.contains(k), isTrue, reason: 'missing log field $k');
      }
    });

    test('R31-5 unknown gerado em _codeFromText fallback', () {
      expect(flowSrc.contains("return 'unknown';"), isTrue);
      expect(
        VendorCreateFlow.extractFirebaseCode('sem padrao reconhecivel'),
        'unknown',
      );
    });

    test('R31-6 JS auth/code NÃO vira unknown', () {
      expect(
        VendorCreateFlow.extractFirebaseCode(
          'FirebaseError: Firebase: Error (auth/operation-not-allowed).',
        ),
        'operation-not-allowed',
      );
    });

    test('R31-7 snackCode nunca é só unknown sem contexto', () {
      final diag = VendorCreateFlow.captureAuthError(
        StateError('falha app-check simulada'),
        authStep: 'app-check',
        firstCatchSite: 'test',
      );
      final snack = diag.displayCode();
      expect(snack, isNot('unknown'));
      expect(snack.contains('StateError'), isTrue);
      final detailed = VendorCreateFlow.detailedFailureMessage(
        diag: diag,
        stage: VendorCreateFlow.stageAuth,
      );
      expect(detailed.contains('app-check'), isTrue);
      expect(diag.unknownOriginHint(), contains('_codeFromText'));
    });

    test('R31-8 service.cadastrar engole erro (NULL) — path morto na UI', () {
      expect(serviceSrc.contains('cadastrarVendedor'), isTrue);
      expect(serviceSrc.contains('return null;'), isTrue);
      // catch genérico sem rethrow
      expect(
        RegExp(r'cadastrarVendedor[\s\S]*?\} catch \(e\) \{[\s\S]*?return null;')
            .hasMatch(serviceSrc),
        isTrue,
      );
    });

    test('R31-9 PII: sanitize não deixa password=', () {
      final line = VendorCreateFlow.captureAuthError(
        'password=segredo123 email=abcd@x.com',
      ).toStringValue;
      expect(line.toLowerCase().contains('password=***'), isTrue);
      expect(line.contains('segredo123'), isFalse);
    });
  });
}
