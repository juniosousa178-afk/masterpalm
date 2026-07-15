// M3.8 HOTFIX-VENDEDOR-R2 — VENDOR-DIAG (pós R2-FIX; só dependências allowlist).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/vendedor_create_flow.dart';

void main() {
  late String screenSrc;
  late String serviceSrc;

  setUpAll(() {
    screenSrc = File('lib/screens/vendedores_screen.dart').readAsStringSync();
    serviceSrc = File('lib/services/vendedor_service.dart').readAsStringSync();
  });

  group('VENDOR-DIAG', () {
    test('VENDOR-DIAG-1 createUser na Auth principal troca currentUser', () {
      // Modelo puro: Auth principal swapada = uid do vendedor.
      expect(
        VendorCreateFlow.primarySessionStillAdmin(
          adminUidBefore: 'adminUidAAA',
          primaryUidAfterSecondaryCreate: 'vendorUidBBB',
          newVendorUid: 'vendorUidBBB',
        ),
        isFalse,
      );
      expect(serviceSrc.contains('_auth.createUserWithEmailAndPassword'), isTrue);
      expect(screenSrc.contains("Firebase.app('secondary')"), isTrue);
    });

    test('VENDOR-DIAG-2 troca de sessão causa write negado quando aplicável', () {
      expect(
        VendorCreateFlow.primarySessionStillAdmin(
          adminUidBefore: 'admin1',
          primaryUidAfterSecondaryCreate: 'vend2',
          newVendorUid: 'vend2',
        ),
        isFalse,
      );
      expect(screenSrc.contains('primary-session-swapped'), isTrue);
    });

    test('VENDOR-DIAG-3 Auth criado + Firestore falha → estado parcial', () {
      final r = VendorCreateFlow.evaluateRefresh(
        beforeCount: 0,
        afterCount: 0,
        vendorUidInList: false,
      );
      expect(r.ok, isFalse);
    });

    test('VENDOR-DIAG-4 modal não fecha antes do sucesso total (FIX)', () {
      expect(VendorCreateFlow.mayCloseModalOnError(), isFalse);
      expect(screenSrc.contains('isDismissible: false'), isTrue);
      expect(screenSrc.contains('mayShowSuccessAndPop'), isTrue);
      expect(screenSrc.contains('successMessage'), isTrue);
    });

    test('VENDOR-DIAG-5 erro deve aparecer com código real (FIX)', () {
      expect(
        VendorCreateFlow.extractFirebaseCode(
          '[firebase_auth/email-already-in-use] Blah',
        ),
        'email-already-in-use',
      );
      expect(screenSrc.contains('failureMessage'), isTrue);
      expect(screenSrc.contains('reportErrorToParent'), isTrue);
    });

    test('VENDOR-DIAG-6 lista deve consultar o mesmo contrato gravado', () {
      expect(screenSrc.contains("collection('vendedores')"), isTrue);
      expect(serviceSrc.contains("collection('vendedores')"), isTrue);
    });

    test('VENDOR-DIAG-7 email-already-in-use classificado', () {
      expect(screenSrc.contains('email-already-in-use'), isTrue);
      expect(
        VendorCreateFlow.failureMessage(
          code: 'email-already-in-use',
          stage: VendorCreateFlow.stageAuth,
        ),
        contains('email-already-in-use'),
      );
    });

    test('VENDOR-DIAG-8 sucesso exige vendedor visível após refresh (FIX)', () {
      final hidden = VendorCreateFlow.evaluateRefresh(
        beforeCount: 0,
        afterCount: 0,
        vendorUidInList: false,
      );
      expect(hidden.ok, isFalse);
      expect(screenSrc.contains('reloadList'), isTrue);
      expect(screenSrc.contains('vendorUidInList'), isTrue);
    });

    test('VENDOR-DIAG-9 senha nunca aparece em log (FIX)', () {
      expect(screenSrc.contains('senha='), isFalse);
      expect(screenSrc.contains("'senha': senha"), isFalse);
      expect(VendorCreateFlow.logTag, '[M38-VENDOR]');
    });

    test('VENDOR-DIAG-10 nenhuma venda/estoque/financeiro é tocado', () {
      final start = screenSrc.indexOf('Future<void> _cadastrarVendedor()');
      final method = screenSrc.substring(start);
      expect(method.contains('SaleIntent'), isFalse);
      expect(method.contains('EstoqueTransaction'), isFalse);
      expect(method.contains("collection('vendas')"), isFalse);
    });

    test('VENDOR-DIAG-extra erros não são engolidos sem report (FIX)', () {
      expect(screenSrc.contains('reportErrorToParent'), isTrue);
      expect(screenSrc.contains('unmounted-before-success-ui'), isFalse);
    });
  });
}
