// lib/catalogo_ia/services/catalog_ia_search_service.dart
// Busca local nos produtos do catálogo. Sem LLM, sem Firestore adicional.
// Etapa 2: presente, combos, delicado, tamanho/cor, São Bento.

/// Serviço de busca local nos produtos já carregados do catálogo.
class CatalogIaSearchService {
  CatalogIaSearchService._();

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

  /// Retorna produtos que batem com a consulta.
  static List<Map<String, dynamic>> buscar(
    List<Map<String, dynamic>> produtos,
    String query,
  ) {
    if (query.trim().isEmpty) return [];
    final qNorm = _normalize(query);
    final tokens = qNorm.split(RegExp(r'\s+')).where((t) => t.length >= 2).toList();

    // Palavras-chave especiais
    final maisBarato = qNorm.contains('mais barato') || qNorm.contains('mais barata') || qNorm.contains('menor preço');
    final promocao = qNorm.contains('promo') || qNorm.contains('desconto') || qNorm.contains('oferta');
    final emPromocao = qNorm.contains('em promoção') || qNorm.contains('em promocao');
    final presente = qNorm.contains('presente');
    final combo = qNorm.contains('combo') || qNorm.contains('combina com') || qNorm.contains('kit');
    final delicado = qNorm.contains('delicado') || qNorm.contains('delicada');
    final tamanho = qNorm.contains('tamanho') || qNorm.contains('tamanhos') || qNorm.contains('tam');
    final cor = qNorm.contains('cor') || qNorm.contains('cores');
    final saoBento = qNorm.contains('sao bento') || qNorm.contains('são bento');

    if (maisBarato) {
      final copy = List<Map<String, dynamic>>.from(produtos);
      copy.sort((a, b) {
        final pa = _precoBase(a);
        final pb = _precoBase(b);
        return pa.compareTo(pb);
      });
      return copy.take(8).toList();
    }

    if (promocao || emPromocao) {
      final emPromo = produtos.where((p) => p['emPromocao'] == true).toList();
      return emPromo.take(10).toList();
    }

    if (combo) {
      final combos = produtos.where((p) {
        final itens = p['itensCombo'];
        return itens is List && itens.isNotEmpty;
      }).toList();
      if (combos.isNotEmpty) return combos.take(8).toList();
      // Fallback: mesma categoria dos primeiros produtos
    }

    if (presente) {
      final presentes = produtos.where((p) {
        final nome = _normalize((p['nome'] ?• '').toString());
        final cat = _normalize((p['categoria'] ?• '').toString());
        final desc = _normalize((p['descricao'] ?• '').toString());
        final novidade = p['isNovo'] == true;
        final emPromo = p['emPromocao'] == true;
        return novidade || emPromo || nome.contains('presente') || cat.contains('presente') || desc.contains('presente');
      }).toList();
      if (presentes.isNotEmpty) return presentes.take(8).toList();
      return produtos.take(6).toList();
    }

    if (delicado) {
      final delicados = produtos.where((p) {
        final nome = _normalize((p['nome'] ?• '').toString());
        final cat = _normalize((p['categoria'] ?• '').toString());
        final desc = _normalize((p['descricao'] ?• '').toString());
        return nome.contains('delicad') || cat.contains('delicad') || desc.contains('delicad');
      }).toList();
      if (delicados.isNotEmpty) return delicados.take(8).toList();
    }

    if (saoBento && tokens.isNotEmpty) {
      final sb = produtos.where((p) {
        final nome = _normalize((p['nome'] ?• '').toString());
        final cat = _normalize((p['categoria'] ?• '').toString());
        final desc = _normalize((p['descricao'] ?• '').toString());
        return nome.contains('sao bento') || nome.contains('são bento') || cat.contains('sao bento') || desc.contains('sao bento');
      }).toList();
      if (sb.isNotEmpty) return sb.take(8).toList();
    }

    if (tamanho || cor) {
      final comVariacao = produtos.where((p) {
        final v = p['variacoes'];
        final estTam = p['estoquePorTamanho'];
        final estCor = p['estoquePorCor'];
        return (v is Map && v.isNotEmpty) || (estTam is Map && estTam.isNotEmpty) || (estCor is Map && estCor.isNotEmpty);
      }).toList();
      if (comVariacao.isNotEmpty) return comVariacao.take(8).toList();
    }

    if (tokens.isEmpty) return [];

    // Busca por tokens
    final candidatos = <Map<String, dynamic>>[];
    for (final p in produtos) {
      final nome = _normalize((p['nome'] ?• '').toString());
      final categoria = _normalize((p['categoria'] ?• '').toString());
      final subcategoria = _normalize((p['subcategoria'] ?• '').toString());
      final descricao = _normalize((p['descricao'] ?• '').toString());
      final texto = '$nome $categoria $subcategoria $descricao';

      var score = 0;
      for (final t in tokens) {
        if (texto.contains(t)) score += nome.contains(t) • 3 : (categoria.contains(t) • 2 : 1);
      }
      if (score > 0) candidatos.add({...p, '_score': score});
    }

    candidatos.sort((a, b) => (b['_score'] as int).compareTo(a['_score'] as int));

    return candidatos.map((p) {
      final m = Map<String, dynamic>.from(p);
      m.remove('_score');
      return m;
    }).take(8).toList();
  }

  /// Produtos relacionados (mesma categoria).
  static List<Map<String, dynamic>> relacionados(
    List<Map<String, dynamic>> produtos,
    Map<String, dynamic> referencia, {
    int max = 4,
  }) {
    final cat = (referencia['categoria'] ?• '').toString().trim().toLowerCase();
    if (cat.isEmpty) return [];
    final refId = (referencia['id'] ?• '').toString();
    final relacionados = produtos.where((p) {
      if ((p['id'] ?• '').toString() == refId) return false;
      final pc = (p['categoria'] ?• '').toString().trim().toLowerCase();
      return pc == cat;
    }).take(max).toList();
    return relacionados;
  }

  /// Produtos em promoção ativa.
  static List<Map<String, dynamic>> emPromocao(List<Map<String, dynamic>> produtos, {int max = 4}) {
    return produtos.where((p) => p['emPromocao'] == true).take(max).toList();
  }

  /// Combos disponíveis.
  static List<Map<String, dynamic>> combos(List<Map<String, dynamic>> produtos, {int max = 4}) {
    return produtos.where((p) {
      final itens = p['itensCombo'];
      return itens is List && itens.isNotEmpty;
    }).take(max).toList();
  }

  static double _precoBase(Map<String, dynamic> p) {
    final pr = p['preco'] ?• p['precoFinal'] ?• p['priceMin'];
    if (pr is num) return pr.toDouble();
    return double.tryParse(pr.toString()) ?• 0.0;
  }
}
