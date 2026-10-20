// Link público de consulta de pedido (catálogo → WhatsApp → página do pedido).
//
// Formato canônico: `https://app.mastepalm.com.br/pedido/{pedidoId}?loja={lojaId}`.
// A página lê apenas `lojas/{lojaId}/pedido_status_publico/{pedidoId}` (espelho sanitizado),
// então o par loja+pedido precisa ser exato; nenhum dos dois é inferido.

import 'package:master_palm/config/app_urls.dart';

class PublicOrderRef {
  const PublicOrderRef({required this.lojaId, required this.pedidoId});

  final String lojaId;
  final String pedidoId;

  @override
  bool operator ==(Object other) =>
      other is PublicOrderRef &&
      other.lojaId == lojaId &&
      other.pedidoId == pedidoId;

  @override
  int get hashCode => Object.hash(lojaId, pedidoId);

  @override
  String toString() => 'PublicOrderRef($lojaId, $pedidoId)';
}

class PublicOrderLink {
  PublicOrderLink._();

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  static bool isValidId(String? id) => id != null && _idPattern.hasMatch(id);

  /// URL HTTPS clicável no WhatsApp. Lança [ArgumentError] para IDs fora do formato.
  static Uri build({
    required String lojaId,
    required String pedidoId,
    String baseUrl = AppUrls.appWebBase,
  }) {
    final loja = lojaId.trim();
    final pedido = pedidoId.trim();
    if (!isValidId(loja)) {
      throw ArgumentError.value(lojaId, 'lojaId', 'formato inválido');
    }
    if (!isValidId(pedido)) {
      throw ArgumentError.value(pedidoId, 'pedidoId', 'formato inválido');
    }
    final base = Uri.parse(baseUrl);
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      pathSegments: ['pedido', pedido],
      queryParameters: {'loja': loja},
    );
  }

  /// `true` quando o path é `/pedido/{algo}` — rota da página pública do pedido,
  /// mesmo que a referência seja inválida (a página mostra o erro amigável).
  static bool isPublicOrderPath(Uri uri) {
    final s = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    return s.length == 2 && s.first == 'pedido';
  }

  /// Referência válida em `/pedido/{pedidoId}?loja={lojaId}`; `null` caso contrário.
  static PublicOrderRef? parse(Uri uri) {
    if (!isPublicOrderPath(uri)) return null;
    final s = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    final pedidoId = s[1].trim();
    final lojaId = (uri.queryParameters['loja'] ?? '').trim();
    if (!isValidId(pedidoId) || !isValidId(lojaId)) return null;
    return PublicOrderRef(lojaId: lojaId, pedidoId: pedidoId);
  }

  /// Nome da rota reportado ao browser pelo Navigator; com `/` a barra de endereço
  /// perderia o pedido e o refresh abriria a raiz do app.
  static String routeName(Uri uri) =>
      uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
}
