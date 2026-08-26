import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/checkout_url_opener.dart';

void main() {
  group('validateCheckoutHttpsUri', () {
    test('aceita https com host', () {
      final uri = validateCheckoutHttpsUri(
        'https://www.mercadopago.com.br/checkout/v1/redirect?pref_id=fake',
      );
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
    });

    test('rejeita null, vazio, http e URI inválida', () {
      expect(
        () => validateCheckoutHttpsUri(null),
        throwsA(isA<CheckoutUrlValidationException>()),
      );
      expect(
        () => validateCheckoutHttpsUri('  '),
        throwsA(isA<CheckoutUrlValidationException>()),
      );
      expect(
        () => validateCheckoutHttpsUri('not a url'),
        throwsA(isA<CheckoutUrlValidationException>()),
      );
      expect(
        () => validateCheckoutHttpsUri('http://localhost/checkout'),
        throwsA(isA<CheckoutUrlValidationException>()),
      );
    });
  });

  group('PlatformCheckoutUrlOpener', () {
    test('Web chama assign same-tab e não launch nativo', () async {
      var assign = 0;
      var native = 0;
      final opener = PlatformCheckoutUrlOpener(
        isWeb: true,
        webAssign: (_) => assign++,
        nativeLaunch: (_) async {
          native++;
          return true;
        },
      );
      await opener.open(
        Uri.parse('https://www.mercadopago.com.br/checkout/fake'),
      );
      expect(assign, 1);
      expect(native, 0);
    });

    test('nativo chama launch e não assign Web', () async {
      var assign = 0;
      var native = 0;
      final opener = PlatformCheckoutUrlOpener(
        isWeb: false,
        webAssign: (_) => assign++,
        nativeLaunch: (_) async {
          native++;
          return true;
        },
      );
      await opener.open(
        Uri.parse('https://www.mercadopago.com.br/checkout/fake'),
      );
      expect(native, 1);
      expect(assign, 0);
    });

    test('launch nativo false lança erro visível', () async {
      final opener = PlatformCheckoutUrlOpener(
        isWeb: false,
        nativeLaunch: (_) async => false,
      );
      await expectLater(
        opener.open(Uri.parse('https://www.mercadopago.com.br/checkout/fake')),
        throwsA(
          predicate<Object>(
            (e) =>
                e.toString().contains('Não foi possível abrir o Mercado Pago'),
          ),
        ),
      );
    });
  });
}
