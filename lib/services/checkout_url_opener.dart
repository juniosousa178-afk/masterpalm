import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import 'checkout_url_opener_web_assign_stub.dart'
    if (dart.library.html) 'checkout_url_opener_web_assign.dart' as web_nav;

/// Valida URL de checkout MP: não nula, não vazia, URI http(s) com host.
/// Apenas https (alinhado a MP). Falha visível — sem fallback silencioso.
Uri validateCheckoutHttpsUri(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) {
    throw const CheckoutUrlValidationException(
      'Não foi possível obter o link de pagamento.',
    );
  }
  final uri = Uri.tryParse(s);
  if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
    throw const CheckoutUrlValidationException(
      'Não foi possível obter o link de pagamento.',
    );
  }
  if (uri.scheme.toLowerCase() != 'https') {
    throw const CheckoutUrlValidationException(
      'Não foi possível obter o link de pagamento.',
    );
  }
  return uri;
}

class CheckoutUrlValidationException implements Exception {
  const CheckoutUrlValidationException(this.message);
  final String message;

  @override
  String toString() => 'Exception: $message';
}

/// Abre a URL de checkout. Testes injectam [RecordingCheckoutUrlOpener].
abstract class CheckoutUrlOpener {
  Future<void> open(Uri url);
}

/// Produção: Web = same-tab `location.assign`; nativo = `launchUrl` externo.
class PlatformCheckoutUrlOpener implements CheckoutUrlOpener {
  PlatformCheckoutUrlOpener({
    bool? isWeb,
    void Function(String url)? webAssign,
    Future<bool> Function(Uri url)? nativeLaunch,
  })  : _isWeb = isWeb ?? kIsWeb,
        _webAssign = webAssign ?? web_nav.assignCheckoutLocation,
        _nativeLaunch = nativeLaunch;

  final bool _isWeb;
  final void Function(String url) _webAssign;
  final Future<bool> Function(Uri url)? _nativeLaunch;

  bool get isWeb => _isWeb;

  @override
  Future<void> open(Uri url) async {
    final validated = validateCheckoutHttpsUri(url.toString());
    if (_isWeb) {
      _webAssign(validated.toString());
      return;
    }
    final launch = _nativeLaunch ??
        ((Uri u) => launchUrl(u, mode: LaunchMode.externalApplication));
    final ok = await launch(validated);
    if (!ok) {
      throw Exception('Não foi possível abrir o Mercado Pago.');
    }
  }
}
