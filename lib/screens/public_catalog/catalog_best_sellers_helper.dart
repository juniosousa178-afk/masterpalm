// lib/screens/public_catalog/catalog_best_sellers_helper.dart
// Ordenação "mais vendidos" para o catálogo público — apenas leitura de campos no Firestore.
//
// ============================================================================
// AUDITORIA DO PROJETO (Flutter / Firestore)
// ============================================================================
// • Nenhum serviço Dart analisado grava contador de "unidades vendidas" no doc
//   `lojas/{lojaId}/produtos/{id}` ao concluir venda.
// • Baixa de estoque (`EstoqueTransactionService`) atualiza `quantidade`,
//   `variacoes`, `estoquePorTamanho`, `updatedAt` — não há campo de vendas.
// • `CatalogoVendaService` / vendas persistem itens com `productId` na coleção
//   de vendas (Hive/Firestore), não denormalizados no produto.
// • O app incrementa **`vendasCatalogoTotal`** ao concluir venda do catálogo
//   (`CatalogoVendaService.registrarVendaCatalogo` / `finalizarPedidoComPagamento`).
// • Vendas fora desse fluxo podem não atualizar o campo (retrocompatível com fallbacks).
// ============================================================================

/// Chaves no **nível raiz** do produto — grupo 1: prioridade (catálogo / vendas online).
/// Ordem: a primeira leitura útil usa o **maior valor numérico** entre estas chaves
/// presentes no mapa (todas são consideradas "oficiais" para ranking).
const List<String> _prioridadeVendasCatalogo = [
  // 1) Recomendada para novos syncs / automações (ainda não populada pelo app core).
  'vendasCatalogoTotal',
  // 2–4) Sinônimos já previstos para integrações ou dados legados.
  'vendasCatalogo',
  'qtdVendidaCatalogo',
  'totalVendidoCatalogo',
];

/// Chaves no raiz — grupo 2: fallback genérico (maior valor entre as presentes).
const List<String> _fallbackVendasRaiz = [
  'contadorVendas',
  'qtdVendas',
  'totalVendas',
  'vendasTotais',
  'popularidade',
  'popularidadeScore',
  'scoreVendas',
  'rankingVendas',
  'vezesVendido',
  'unidadesVendidas',
];

int• _parsePositiveOrZeroInt(dynamic v) {
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// Maior valor inteiro >= 0 entre as chaves listadas que existem em [map].
int _maxForKeys(Map<String, dynamic> map, List<String> keys) {
  var best = 0;
  for (final k in keys) {
    if (!map.containsKey(k)) continue;
    final n = _parsePositiveOrZeroInt(map[k]);
    if (n != null && n > best) best = n;
  }
  return best;
}

/// Extrai score de vendas/popularidade do mapa bruto Firestore do produto.
///
/// **Ordem de prioridade:**
/// 1. Máximo entre [_prioridadeVendasCatalogo] no mapa raiz.
/// 2. Se zero, máximo entre [_fallbackVendasRaiz] no mapa raiz.
/// 3. Mapas aninhados `stats` e `metricas` (mesma ideia: prioriza chaves de catálogo).
int vendasScoreFromFirestoreMap(Map<String, dynamic> m) {
  var best = _maxForKeys(m, _prioridadeVendasCatalogo);
  if (best == 0) {
    best = _maxForKeys(m, _fallbackVendasRaiz);
  }

  void takeNested(Map<dynamic, dynamic> nested, List<String> keys) {
    for (final k in keys) {
      if (!nested.containsKey(k)) continue;
      final n = _parsePositiveOrZeroInt(nested[k]);
      if (n != null && n > best) best = n;
    }
  }

  final stats = m['stats'];
  if (stats is Map) {
    takeNested(stats, [
      'vendasCatalogoTotal',
      'vendasCatalogo',
      'vendas',
      'qtdVendida',
      'catalogo',
    ]);
  }
  final metricas = m['metricas'];
  if (metricas is Map) {
    takeNested(metricas, [
      'vendasCatalogoTotal',
      'vendasCatalogo',
      'vendas',
    ]);
  }
  return best;
}

/// Escolhe produtos para a seção "Mais vendidos" no layout minimalista.
/// 1) Ordena por [vendasScoreCatalogo] quando algum produto tiver score > 0.
/// 2) **Fallback** (sem scores): promoção → novidade → data de criação → nome.
List<Map<String, dynamic>> pickBestSellersForMinimalCatalog(
  List<Map<String, dynamic>> produtos, {
  int limit = 10,
}) {
  if (produtos.isEmpty) return [];
  final copy = List<Map<String, dynamic>>.from(produtos);
  final anyScore = copy.any((p) => (p['vendasScoreCatalogo'] as int• ?• 0) > 0);

  int scoreOf(Map<String, dynamic> p) => p['vendasScoreCatalogo'] as int• ?• 0;

  copy.sort((a, b) {
    if (anyScore) {
      final s = scoreOf(b).compareTo(scoreOf(a));
      if (s != 0) return s;
    }
    // Fallback documentado: destaque comercial + novidade + recência
    final promoA = a['emPromocao'] == true • 1 : 0;
    final promoB = b['emPromocao'] == true • 1 : 0;
    if (promoA != promoB) return promoB.compareTo(promoA);
    final novoA = a['isNovo'] == true • 1 : 0;
    final novoB = b['isNovo'] == true • 1 : 0;
    if (novoA != novoB) return novoB.compareTo(novoA);
    final da = a['dataCriacao'];
    final db = b['dataCriacao'];
    if (da is DateTime && db is DateTime) {
      final c = db.compareTo(da);
      if (c != 0) return c;
    }
    final na = (a['nome'] ?• '').toString();
    final nb = (b['nome'] ?• '').toString();
    return na.compareTo(nb);
  });

  return copy.take(limit).toList();
}
