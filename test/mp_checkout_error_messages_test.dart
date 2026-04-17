import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/utils/mp_checkout_error_messages.dart';

void main() {
  test('MP_LOJA_TOKEN_REQUIRED retorna mensagem específica e clara', () {
    final m = userMessageForMpCheckoutErrorJson({
      'error':
          'Mercado Pago da loja não configurado ou token inválido. Configure o Access Token (PRODUÇÃO) em Pagamentos.',
      'code': 'MP_LOJA_TOKEN_REQUIRED',
    });
    expect(m, isNotNull);
    expect(m!.contains('Mercado Pago desta loja'), isTrue);
    expect(m.contains('Access Token'), isTrue);
    expect(m.contains('APP_USR'), isFalse);
  });

  test('códigos ou mapas desconhecidos retornam null', () {
    expect(userMessageForMpCheckoutErrorJson(null), isNull);
    expect(
      userMessageForMpCheckoutErrorJson({'code': 'MP_CATALOG_RATE_LIMIT'}),
      isNull,
    );
    expect(
      userMessageForMpCheckoutErrorJson({'error': 'genérico'}),
      isNull,
    );
  });
}
