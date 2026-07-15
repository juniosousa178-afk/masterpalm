// M3.8 HOTFIX-VENDEDOR-R3-DIAG — extração de códigos Auth (web/JS).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/vendedor_create_flow.dart';

void main() {
  group('VENDOR-R3-DIAG', () {
    test('extrai (auth/code) do formato JS/web', () {
      expect(
        VendorCreateFlow.extractFirebaseCode(
          'FirebaseError: Firebase: Error (auth/email-already-in-use).',
        ),
        'email-already-in-use',
      );
      expect(
        VendorCreateFlow.extractFirebaseCode(
          'Firebase: Error (auth/operation-not-allowed).',
        ),
        'operation-not-allowed',
      );
    });

    test('extrai [firebase_auth/code] do formato plugin', () {
      expect(
        VendorCreateFlow.extractFirebaseCode(
          '[firebase_auth/weak-password] Password should be at least 6 characters',
        ),
        'weak-password',
      );
    });

    test('captureAuthError não mascara código JS como unknown', () {
      final diag = VendorCreateFlow.captureAuthError(
        'FirebaseError: Firebase: Error (auth/too-many-requests).',
      );
      expect(diag.code, 'too-many-requests');
      expect(diag.snackCode(), 'too-many-requests');
      expect(diag.snackCode(), isNot('unknown'));
    });

    test('snackCode usa runtimeType+toString se não houver código', () {
      final diag = VendorCreateFlow.captureAuthError(StateError('boom'));
      expect(diag.snackCode(), isNot('unknown'));
      expect(diag.snackCode().contains('StateError'), isTrue);
    });
  });
}
