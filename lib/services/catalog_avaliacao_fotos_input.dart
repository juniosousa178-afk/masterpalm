// Ponto único para entrada de fotos nas avaliações do catálogo.
// Hoje: texto com URLs separadas por vírgula (compatível com o formulário atual).
// Futuro: trocar [parseUrlsFromFormText] por upload via Firebase Storage e manter
// o retorno como List<String> de URLs públicas — o fluxo do serviço não precisa mudar.

class CatalogAvaliacaoFotosInput {
  CatalogAvaliacaoFotosInput._();

  /// Parse do campo de texto do formulário (vírgulas, como já usado).
  static List<String> parseUrlsFromFormText(String raw) {
    if (raw.trim().isEmpty) return [];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  // Futuro: substituir ou complementar por upload real.
  // static Future<List<String>> uploadAndGetUrls({
  //   required String lojaId,
  //   required List<XFile> files,
  // }) async { ... }
}
