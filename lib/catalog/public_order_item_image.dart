// Foto do item no espelho público do pedido (`pedido_status_publico`).
// Gravada pelo servidor (`functions/src/publicOrderItemImages.js`) a partir do produto
// publicado da própria loja; aqui só se valida antes de exibir ou copiar.

const String kPublicOrderItemImageField = 'imagem';

const int _maxImageUrlLength = 2048;
final RegExp _unsafeUrlChars = RegExp('[\\s"\'<>\\\\`\\x00-\\x1f\\x7f]');

/// URL https absoluta, sem credenciais nem caracteres de escape; senão `null`.
String? publicOrderItemImageUrl(Object? raw) {
  if (raw is! String) return null;
  final url = raw.trim();
  if (url.isEmpty ||
      url.length > _maxImageUrlLength ||
      _unsafeUrlChars.hasMatch(url)) {
    return null;
  }
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return url;
}
