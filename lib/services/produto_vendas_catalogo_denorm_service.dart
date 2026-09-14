// lib/services/produto_vendas_catalogo_denorm_service.dart
//
// Denormalização: incrementa `vendasCatalogoTotal` nos docs de produto quando
// uma venda do catálogo é concluída. Não altera estoque nem relatórios;
// falhas são apenas logadas (mesmo padrão de sync de venda).

import 'package:collection/collection.dart';
import 'package:hive/hive.dart';

import '../core/logger.dart';
import '../models/produto.dart';

/// Campo canônico usado pelo ranking "Mais vendidos" no catálogo público.
const String kVendasCatalogoTotalField = 'vendasCatalogoTotal';

/// Agrupa quantidades vendidas por documento de produto (id Firestore / idFirebase).
///
/// Regras:
/// - **Combo**: uma linha no carrinho incrementa o doc do **combo** (não os itens internos),
///   alinhado ao que o cliente "comprou" no catálogo.
/// - **Simples**: incrementa o produto resolvido (productId → slug → nome no Hive).
/// - Se houver `productId` na linha mas o produto não estiver no Hive, ainda assim
///   contabiliza por esse id (ex.: dispositivo sem cache local completo).
Map<String, int> buildVendasCatalogoDeltasPorProdutoId({
  required List<Map<String, dynamic>> items,
  required Box<Produto> produtosBox,
  required String lojaId,
}) {
  final deltas = <String, int>{};

  for (final item in items) {
    final productIdRaw =
        (item['productId'] ?? item['id'] ?? '').toString().trim();
    final nome = (item['nome'] ?? item['name'] ?? '').toString().trim();
    final slug = (item['slug'] ?? '').toString().trim();
    final qtd =
        (item['quantidade'] as num?)?.toInt() ?? (item['qty'] as int?) ?? 1;
    if (qtd <= 0) continue;
    if (nome.isEmpty && slug.isEmpty && productIdRaw.isEmpty) continue;

    Produto? prod = productIdRaw.isNotEmpty
        ? produtosBox.values.firstWhereOrNull(
            (x) => x.lojaId == lojaId && x.idFirebase.trim() == productIdRaw,
          )
        : null;
    if (prod == null && slug.isNotEmpty) {
      prod = produtosBox.values.firstWhereOrNull(
        (x) => x.lojaId == lojaId && x.slug == slug,
      );
    }
    if (prod == null && nome.isNotEmpty) {
      prod = produtosBox.values.firstWhereOrNull(
        (x) =>
            x.lojaId == lojaId &&
            x.nome.trim().toLowerCase() == nome.toLowerCase(),
      );
    }

    if (prod == null) {
      if (productIdRaw.isNotEmpty) {
        deltas[productIdRaw] = (deltas[productIdRaw] ?? 0) + qtd;
      } else {
        logW(
          '[VENDAS_CATALOGO_DENORM] Sem productId e sem match Hive; linha ignorada | loja=$lojaId | nome=$nome',
        );
      }
      continue;
    }

    final id = prod.idFirebase.trim();
    if (id.isEmpty) {
      logW(
        '[VENDAS_CATALOGO_DENORM] Produto sem idFirebase; não é possível incrementar | loja=$lojaId | nome=${prod.nome}',
      );
      continue;
    }

    // Combo: contabiliza o pacote vendido no catálogo, não os componentes.
    deltas[id] = (deltas[id] ?? 0) + qtd;
  }

  return deltas;
}

class ProdutoVendasCatalogoDenormService {
  ProdutoVendasCatalogoDenormService._();

  /// Compatibilidade dos chamadores: a contagem agora pertence à baixa do pedido
  /// persistido no backend. Repetir um efeito secundário não incrementa estoque/live.
  static Future<void> incrementarAposVendaCatalogo({
    required String lojaId,
    required List<Map<String, dynamic>> items,
    required Box<Produto> produtosBox,
  }) async {}
}
