// lib/utils/mp_checkout_error_messages.dart
//
// Mensagens amigáveis para códigos de erro do backend (Cloud Functions MP da loja).
// Não altera contratos — só mapeia [code] conhecido para texto ao usuário.

/// Se [errJson] tiver `code` reconhecido, retorna mensagem operacional; senão null
/// (o chamador segue com `error` genérico ou fallback).
String? userMessageForMpCheckoutErrorJson(Map<String, dynamic>? errJson) {
  if (errJson == null) return null;
  final code = errJson['code']?.toString();
  if (code == 'MP_LOJA_TOKEN_REQUIRED') {
    return 'O Mercado Pago desta loja ainda não foi configurado. '
        'Quem administra a loja precisa informar o Access Token de produção em '
        'Configurações de pagamentos para habilitar o checkout.';
  }
  if (code == 'PIX_CPF_INVALID') {
    return 'CPF inválido para gerar o PIX. Confira os 11 dígitos no checkout e tente novamente.';
  }
  return null;
}
