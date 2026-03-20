// lib/services/catalog_share_service.dart
// Serviço central para montar mensagem e URL de compartilhamento (WhatsApp, copiar).
// Preserva ref, indicacao e vendedor; usa URL canônica do catálogo.

/// Serviço central de compartilhamento do catálogo (produto, catálogo, campanha).
class CatalogShareService {
  CatalogShareService._();

  /// Monta a URL final do catálogo com ref e indicacao quando informados.
  /// [baseUrl] ex.: https://app.mastepalm.com.br/loja/loja_123
  static String buildUrlWithParams(
    String baseUrl, {
    String? ref,
    String? indicacao,
    String? produto,
  }) {
    String url = baseUrl.trim();
    if (url.isEmpty) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final query = <String, String>{};
    if (uri.queryParameters.isNotEmpty) {
      query.addAll(uri.queryParameters);
    }
    if (ref != null && ref.trim().isNotEmpty) {
      query['ref'] = ref.trim();
    }
    if (indicacao != null && indicacao.trim().isNotEmpty) {
      query['indicacao'] = indicacao.trim();
    }
    if (produto != null && produto.trim().isNotEmpty) {
      query['produto'] = produto.trim();
    }
    if (query.isEmpty) return url;
    final newUri = uri.replace(queryParameters: query);
    return newUri.toString();
  }

  /// Monta mensagem pronta para compartilhar um produto no WhatsApp.
  /// [nome] obrigatório. [precoTexto] ex.: "R\$ 49,90" ou "R\$ 20,00 a R\$ 30,00".
  /// [descricaoCurta] opcional; se vazia, não inclui. [url] URL final (já com ref/indicacao se aplicável).
  static String buildProductShareMessage({
    required String nome,
    required String precoTexto,
    String? descricaoCurta,
    required String url,
    String? fraseFinal,
  }) {
    final nomeTrim = nome.trim();
    final preco = precoTexto.trim();
    final urlTrim = url.trim();
    final parts = <String>[];
    if (nomeTrim.isNotEmpty) {
      parts.add('Confira: $nomeTrim');
      if (preco.isNotEmpty) parts.add(' - $preco');
      parts.add('.');
    } else if (preco.isNotEmpty) {
      parts.add('Confira este produto - $preco.');
    } else {
      parts.add('Confira este produto.');
    }
    if (descricaoCurta != null && descricaoCurta.trim().isNotEmpty) {
      final d = descricaoCurta.trim();
      if (d.length > 120) {
        parts.add(' ${d.substring(0, 117)}…');
      } else {
        parts.add(' $d');
      }
    }
    parts.add('\n\n');
    if (urlTrim.isNotEmpty) parts.add(urlTrim);
    if (fraseFinal != null && fraseFinal.trim().isNotEmpty) {
      parts.add('\n\n');
      parts.add(fraseFinal.trim());
    }
    return parts.join();
  }

  /// Monta mensagem para compartilhar o catálogo completo.
  static String buildCatalogShareMessage({
    required String url,
    String? mensagemPersonalizada,
  }) {
    final urlTrim = url.trim();
    if (mensagemPersonalizada != null && mensagemPersonalizada.trim().isNotEmpty) {
      return '${mensagemPersonalizada.trim()}\n\n$urlTrim';
    }
    return 'Olá! Dá uma olhada no nosso catálogo:\n\n$urlTrim';
  }

  /// Monta mensagem para compartilhar uma campanha (nome + link).
  static String buildCampaignShareMessage({
    required String nomeCampanha,
    String? descricao,
    required String url,
  }) {
    final parts = <String>['Confira a campanha: ${nomeCampanha.trim()}.'];
    if (descricao != null && descricao.trim().isNotEmpty) {
      parts.add(' ${descricao.trim()}');
    }
    parts.add('\n\n$url');
    return parts.join();
  }

  /// Retorna o texto codificado para uso em wa.me/?text=
  static String encodeForWhatsApp(String message) {
    return Uri.encodeComponent(message);
  }
}


