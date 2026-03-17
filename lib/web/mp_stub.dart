// lib/web/mp_stub.dart
// Stub usado fora do Web. Evita importar dart:html / dart:js no mobile.

Future<String> criarPreferenceEObterId(
    String functionUrl, Map<String, dynamic> body) async {
  throw 'Pagamento on-line (Mercado Pago) só está disponível no Web.';
}

Future<void> pagarComPreference(String publicKey, String preferenceId) async {
  // no-op fora do Web
  throw 'Pagamento on-line (Mercado Pago) só está disponível no Web.';
}
