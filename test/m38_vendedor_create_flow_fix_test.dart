// M3.8 HOTFIX-VENDEDOR-R2-FIX — VENDOR-FIX-1…10

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/vendedor_create_flow.dart';

void main() {
  late String screenSrc;

  setUpAll(() {
    screenSrc = File('lib/screens/vendedores_screen.dart').readAsStringSync();
  });

  group('VENDOR-FIX', () {
    test('VENDOR-FIX-1 sucesso completo', () {
      final r = VendorCreateFlow.evaluateRefresh(
        beforeCount: 0,
        afterCount: 1,
        vendorUidInList: true,
      );
      expect(r.ok, isTrue);
      expect(VendorCreateFlow.mayShowSuccessAndPop(r), isTrue);
      expect(screenSrc.contains('reportSuccessToParent'), isTrue);
      expect(screenSrc.contains('Navigator.pop'), isTrue);
      expect(
        screenSrc.indexOf('reportSuccessToParent') <
            screenSrc.indexOf("Navigator.pop(context)"),
        isTrue,
      );
    });

    test('VENDOR-FIX-2 permission-denied', () {
      expect(
        VendorCreateFlow.failureMessage(
          code: 'permission-denied',
          stage: VendorCreateFlow.stageVendedores,
        ),
        contains('permission-denied'),
      );
      expect(
        VendorCreateFlow.failureMessage(
          code: 'permission-denied',
          stage: VendorCreateFlow.stageVendedores,
        ),
        contains(VendorCreateFlow.stageVendedores),
      );
      expect(screenSrc.contains('failureMessage'), isTrue);
    });

    test('VENDOR-FIX-3 email-already-in-use', () {
      expect(
        VendorCreateFlow.extractFirebaseCode(
          '[firebase_auth/email-already-in-use]',
        ),
        'email-already-in-use',
      );
      expect(screenSrc.contains('email-already-in-use'), isTrue);
      expect(
        VendorCreateFlow.failureMessage(
          code: 'email-already-in-use',
          stage: VendorCreateFlow.stageAuth,
        ),
        contains('email-already-in-use'),
      );
    });

    test('VENDOR-FIX-4 write vendedores falha', () {
      final msg = VendorCreateFlow.failureMessage(
        code: 'permission-denied',
        stage: VendorCreateFlow.stageVendedores,
      );
      expect(msg.contains('vendedores'), isTrue);
      expect(VendorCreateFlow.mayCloseModalOnError(), isFalse);
    });

    test('VENDOR-FIX-5 members falha', () {
      final msg = VendorCreateFlow.failureMessage(
        code: 'permission-denied',
        stage: VendorCreateFlow.stageMembers,
      );
      expect(msg.contains('members'), isTrue);
      expect(screenSrc.contains("collection('members')"), isTrue);
    });

    test('VENDOR-FIX-6 refresh não encontra vendedor', () {
      final r = VendorCreateFlow.evaluateRefresh(
        beforeCount: 2,
        afterCount: 2,
        vendorUidInList: false,
      );
      expect(r.ok, isFalse);
      expect(VendorCreateFlow.mayShowSuccessAndPop(r), isFalse);
      expect(
        VendorCreateFlow.refreshMissMessage(),
        'O vendedor não apareceu após atualização.',
      );
      expect(screenSrc.contains('refreshMissMessage'), isTrue);
    });

    test('VENDOR-FIX-7 modal permanece aberto em erro', () {
      expect(screenSrc.contains('isDismissible: false'), isTrue);
      expect(screenSrc.contains('enableDrag: false'), isTrue);
      expect(screenSrc.contains('canPop: !_carregando'), isTrue);
      expect(VendorCreateFlow.mayCloseModalOnError(), isFalse);
      // Pop de sucesso existe; em catch não há Navigator.pop.
      final catchIdx = screenSrc.indexOf('on FirebaseAuthException');
      final catchWindow = screenSrc.substring(catchIdx, catchIdx + 900);
      expect(catchWindow.contains('Navigator.pop'), isFalse);
    });

    test('VENDOR-FIX-8 snackbar sucesso somente após refresh', () {
      expect(screenSrc.contains('stageRefresh'), isTrue);
      expect(screenSrc.contains('mayShowSuccessAndPop'), isTrue);
      expect(screenSrc.contains('successMessage'), isTrue);
      final refreshIdx = screenSrc.indexOf('stageRefresh');
      final successIdx = screenSrc.indexOf('stageSuccess');
      expect(refreshIdx, greaterThan(0));
      expect(successIdx, greaterThan(refreshIdx));
    });

    test('VENDOR-FIX-9 senha nunca persiste', () {
      final payload = VendorCreateFlow.usuariosDocPayload(
        uid: 'u1',
        email: 'a@b.com',
        nome: 'N',
        telefone: '1',
        ownerAdminEmail: 'admin@x.com',
        storeId: 'loja',
        createdAt: 'ts',
        updatedAt: 'ts',
      );
      expect(VendorCreateFlow.payloadContainsPassword(payload), isFalse);
      expect(payload.containsKey('senha'), isFalse);
      expect(VendorCreateFlow.hivePasswordPlaceholder(), isEmpty);
      expect(screenSrc.contains("'senha': senha"), isFalse);
      expect(screenSrc.contains('senha: senha'), isFalse);
      expect(screenSrc.contains('FieldValue.delete()'), isTrue);
      expect(screenSrc.contains('hivePasswordPlaceholder'), isTrue);
    });

    test('VENDOR-FIX-10 secondary auth permanece isolada', () {
      expect(
        VendorCreateFlow.primarySessionStillAdmin(
          adminUidBefore: 'admin1',
          primaryUidAfterSecondaryCreate: 'admin1',
          newVendorUid: 'vend2',
        ),
        isTrue,
      );
      expect(
        VendorCreateFlow.primarySessionStillAdmin(
          adminUidBefore: 'admin1',
          primaryUidAfterSecondaryCreate: 'vend2',
          newVendorUid: 'vend2',
        ),
        isFalse,
      );
      expect(screenSrc.contains("Firebase.app('secondary')"), isTrue);
      expect(screenSrc.contains('instanceFor(app: secApp)'), isTrue);
      expect(screenSrc.contains('primarySessionStillAdmin'), isTrue);
      expect(screenSrc.contains('primary-session-swapped'), isTrue);
    });
  });
}
