// lib/web/mp_web.dart
// Implementação agnóstica: usa a ponte Web (condicional) em vez de html/js diretos.

import 'dart:convert';
import 'platform_stub.dart' if (dart.library.html) 'platform_web.dart';

Future<void> _ensureSdkLoaded() async {
  if (Web.hasElById('mp-sdk')) return;
  await Web.loadScript(
    id: 'mp-sdk',
    src: 'https://sdk.mercadopago.com/js/v2',
  );
}

/// Faz POST para sua Function HTTPS e extrai o "preferenceId".
Future<String> criarPreferenceEObterId(
  String functionUrl,
  Map<String, dynamic> body,
) async {
  final txt = await Web.httpPostJson(functionUrl, jsonEncode(body));
  final re = RegExp(r'"preferenceId"\s*:\s*"([^"]+)"');
  final m = re.firstMatch(txt);
  if (m == null) {
    throw 'Retorno inválido da função: $txt';
  }
  return m.group(1)!;
}

/// Abre o Checkout Pro usando a preference id.
Future<void> pagarComPreference(
  String publicKey,
  String preferenceId,
) async {
  await _ensureSdkLoaded();

  // Cria a instância e abre o checkout (via eval para simplicidade)
  Web.callJs('eval', [
    '(new MercadoPago("$publicKey")).checkout({ preference: { id: "$preferenceId" }, autoOpen: true })'
  ]);
}
