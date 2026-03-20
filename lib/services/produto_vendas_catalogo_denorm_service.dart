// lib/services/produto_vendas_catalogo_denorm_service.dart
//
// Denormalização: incrementa `vendasCatalogoTotal` nos docs de produto quando
// uma venda do catálogo é concluída. Não altera estoque nem relatórios;
// falhas são apenas logadas (mesmo padrão de sync de venda).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:hive/hive.dart';

import '../core/logger.dart';
import '../models/produto.dart';
import 'firestore_paths.dart';

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
        (item['productId'] ?• item['id'] ?• '').toString().trim();
    final nome = (item['nome'] ?• item['name'] ?• '').toString().trim();
    final slug = (item['slug'] ?• '').toString().trim();
    final qtd =
        (item['quantidade'] as num?)?.toInt() ?• (item['qty'] as int?) ?• 1;
    if (qtd <= 0) continue;
    if (nome.isEmpty && slug.isEmpty && productIdRaw.isEmpty) continue;

    Produto• prod = productIdRaw.isNotEmpty
        • produtosBox.values.firstWhereOrNull(
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
        deltas[productIdRaw] = (deltas[productIdRaw] ?• 0) + qtd;
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
    deltas[id] = (deltas[id] ?• 0) + qtd;
  }

  return deltas;
}

class ProdutoVendasCatalogoDenormService {
  ProdutoVendasCatalogoDenormService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Map<String, dynamic> _incrementPayload(int inc) => <String, dynamic>{
        kVendasCatalogoTotalField: FieldValue.increment(inc),
      };

  /// Tenta `produtos` primeiro (fonte do catálogo público); se o doc não existir,
  /// tenta `estoque_produtos` (onde a baixa de estoque atua).
  static Future<void> _incrementEmProdutoOuEstoque({
    required String lojaId,
    required String docId,
    required int inc,
  }) async {
    if (docId.isEmpty || inc <= 0) return;

    final base = _db.collection('lojas').doc(lojaId);
    final prodRef = base.collection('produtos').doc(docId);
    final estRef = base.collection(FSPaths.estoqueProdutosCol).doc(docId);
    final payload = _incrementPayload(inc);

    try {
      await prodRef.update(payload);
    } catch (e) {
      logD(
        '[VENDAS_CATALOGO_DENORM] produtos/$docId update falhou (${e.runtimeType}); tentando estoque_produtos',
      );
      try {
        await estRef.update(payload);
      } catch (e2, st2) {
        logE(
          '[VENDAS_CATALOGO_DENORM] Falha em produtos e estoque_produtos | loja=$lojaId | doc=$docId',
          error: e2,
          st: st2,
        );
      }
      return;
    }

    // Espelho best-effort (muitas lojas mantêm o mesmo id nas duas coleções).
    try {
      await estRef.update(payload);
    } catch (_) {
      // Doc pode não existir em estoque_produtos — ignorar.
    }
  }

  /// Chamado após baixa de estoque e gravação da venda com sucesso.
  /// Não propaga exceção: não deve falhar o fluxo de venda.
  static Future<void> incrementarAposVendaCatalogo({
    required String lojaId,
    required List<Map<String, dynamic>> items,
    required Box<Produto> produtosBox,
  }) async {
    if (items.isEmpty) return;

    final deltas = buildVendasCatalogoDeltasPorProdutoId(
      items: items,
      produtosBox: produtosBox,
      lojaId: lojaId,
    );
    if (deltas.isEmpty) return;

    try {
      await Future.wait(
        deltas.entries.map(
          (e) => _incrementEmProdutoOuEstoque(
            lojaId: lojaId,
            docId: e.key,
            inc: e.value,
          ),
        ),
      );
    } catch (e, st) {
      logE(
        '[VENDAS_CATALOGO_DENORM] Erro agregado (type=${e.runtimeType})',
        error: e,
        st: st,
      );
    }
  }
}
