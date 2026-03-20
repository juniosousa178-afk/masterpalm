// lib/catalogo_ia/services/catalog_ia_service.dart
// Assistente do catálogo: busca local e resposta em texto. Sem LLM.
// Etapa 2: respostas mais úteis, sugestões relacionadas, combos, promoções destacadas.

import 'catalog_ia_search_service.dart';

/// Resposta do assistente do catálogo.
class CatalogIaResposta {
  final String texto;
  final List<Map<String, dynamic>> produtos;
  /// Produtos relacionados (ex.: mesma categoria).
  final List<Map<String, dynamic>> sugestoesRelacionadas;
  /// Produtos em promoção para destacar.
  final List<Map<String, dynamic>> emPromocaoDestaque;
  /// Combos sugeridos.
  final List<Map<String, dynamic>> combosSugeridos;

  const CatalogIaResposta({
    required this.texto,
    this.produtos = const [],
    this.sugestoesRelacionadas = const [],
    this.emPromocaoDestaque = const [],
    this.combosSugeridos = const [],
  });
}

/// Serviço do assistente do catálogo (Etapa 2: busca local + sugestões inteligentes).
class CatalogIaService {
  CatalogIaService._();

  static const _diacritics = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'é': 'e', 'ê': 'e',
    'í': 'i', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ü': 'u',
    'ç': 'c',
  };

  static String _normalize(String s) {
    var r = s.toLowerCase().trim();
    for (final e in _diacritics.entries) {
      r = r.replaceAll(e.key, e.value);
    }
    return r;
  }

  /// Processa pergunta e retorna texto + produtos relacionados + sugestões.
  static CatalogIaResposta responder(
    List<Map<String, dynamic>> produtos,
    String pergunta,
  ) {
    final p = pergunta.trim();
    if (p.isEmpty) {
      return const CatalogIaResposta(texto: 'Digite sua dúvida sobre os produtos.');
    }

    final matches = CatalogIaSearchService.buscar(produtos, p);

    if (matches.isEmpty) {
      return const CatalogIaResposta(
        texto: 'Não encontrei produtos com essa busca. Tente termos como nome, categoria, "mais barato", "em promoção" ou "combo".',
        produtos: [],
      );
    }

    final qNorm = _normalize(p);
    final textoResp = _montarResposta(matches, p, qNorm);
    List<Map<String, dynamic>> sugestoes = [];
    List<Map<String, dynamic>> emPromo = [];
    List<Map<String, dynamic>> combos = [];

    if (matches.length <= 3 && matches.isNotEmpty) {
      sugestoes = CatalogIaSearchService.relacionados(produtos, matches.first, max: 4);
    }
    emPromo = CatalogIaSearchService.emPromocao(produtos, max: 3);
    combos = CatalogIaSearchService.combos(produtos, max: 3);

    return CatalogIaResposta(
      texto: textoResp,
      produtos: matches,
      sugestoesRelacionadas: sugestoes.where((s) => !matches.any((m) => (m['id'] ?• '') == (s['id'] ?• ''))).take(4).toList(),
      emPromocaoDestaque: emPromo.where((e) => !matches.any((m) => (m['id'] ?• '') == (e['id'] ?• ''))).take(3).toList(),
      combosSugeridos: combos.where((c) => !matches.any((m) => (m['id'] ?• '') == (c['id'] ?• ''))).take(3).toList(),
    );
  }

  static String _montarResposta(List<Map<String, dynamic>> matches, String query, String qNorm) {
    final emPromocaoQ = qNorm.contains('promo') || qNorm.contains('desconto') || qNorm.contains('oferta');
    final maisBaratoQ = qNorm.contains('mais barato') || qNorm.contains('menor preço');
    final presenteQ = qNorm.contains('presente');
    final comboQ = qNorm.contains('combo') || qNorm.contains('combina') || qNorm.contains('kit');
    final tamanhoCorQ = qNorm.contains('tamanho') || qNorm.contains('cor');

    if (emPromocaoQ && matches.isNotEmpty) {
      return 'Encontrei ${matches.length} produto(s) em promoção. Confira abaixo.';
    }
    if (maisBaratoQ && matches.isNotEmpty) {
      final primeiro = matches.first;
      final preco = _fmtPreco(primeiro);
      return 'Os mais baratos são: ${matches.take(3).map((p) => (p['nome'] ?• 'Produto').toString()).join(', ')}. O menor preço é $preco.';
    }
    if (presenteQ && matches.isNotEmpty) {
      return 'Ótimas opções de presente: ${matches.take(5).map((p) => (p['nome'] ?• 'Produto').toString()).join(', ')}.';
    }
    if (comboQ && matches.isNotEmpty) {
      return 'Encontrei ${matches.length} combo(s) disponíveis. Confira abaixo.';
    }
    if (tamanhoCorQ && matches.isNotEmpty) {
      return 'Produtos com variações de tamanho e cor: ${matches.take(5).map((p) => (p['nome'] ?• 'Produto').toString()).join(', ')}.';
    }
    if (matches.length == 1) {
      final prod = matches.first;
      final nome = (prod['nome'] ?• 'Produto').toString();
      final preco = _fmtPreco(prod);
      final emPromo = prod['emPromocao'] == true;
      if (emPromo) return 'Encontrei: $nome. $preco – está em promoção!';
      return 'Encontrei: $nome. $preco';
    }
    final nomes = matches.take(5).map((p) => (p['nome'] ?• 'Produto').toString()).join(', ');
    return 'Encontrei ${matches.length} produto(s): $nomes. Confira abaixo.';
  }

  static String _fmtPreco(Map<String, dynamic> p) {
    final pr = p['preco'] ?• p['precoFinal'] ?• p['priceMin'];
    if (pr == null) return '';
    final v = pr is num • pr.toDouble() : double.tryParse(pr.toString());
    if (v == null) return '';
    return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
  }
}
