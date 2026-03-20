import 'package:hive/hive.dart';
import 'package:collection/collection.dart';

import '../core/logger.dart';
import '../core/strict_product_resolution.dart';
import '../models/produto.dart';

/// Expande itens do catálogo para uma lista normalizada de itens de estoque.
/// Resolução: 1) productId, 2) slug, 3) nome. Inclui productId no resultado quando disponível.
List<Map<String, dynamic>> expandirItemsParaEstoque({
  required List<Map<String, dynamic>> items,
  required Box<Produto> produtosBox,
  required String lojaId,
}) {
  final result = <Map<String, dynamic>>[];
  for (final item in items) {
    final productId = (item['productId'] ?? item['id'] ?? '').toString().trim();
    final nome = (item['nome'] ?? item['name'] ?? '').toString().trim();
    final slug = (item['slug'] ?? '').toString().trim();
    final qtd = (item['quantidade'] as num?)?.toInt() ?? (item['qty'] as int?) ?? 1;
    final tamanho = (item['tamanho'] ?? item['size'] ?? '').toString().trim();
    final cor = (item['cor'] ?? item['color'] ?? '').toString().trim();

    if (nome.isEmpty && slug.isEmpty && productId.isEmpty) continue;
    if (qtd <= 0) continue;

    // Ordem: productId → slug → nome
    Produto? prod = productId.isNotEmpty
        ? produtosBox.values.firstWhereOrNull(
            (x) => x.lojaId == lojaId && x.idFirebase.trim() == productId,
          )
        : null;
    if (prod == null && slug.isNotEmpty) {
      prod = produtosBox.values.firstWhereOrNull(
        (x) => x.lojaId == lojaId && x.slug == slug,
      );
      if (prod != null) {
        logW(
          '[CATALOGO_ITEM] Resolução por slug (expandirEstoque) | lojaId=$lojaId | slug=$slug',
          tag: 'PRODUTO_FALLBACK',
        );
      }
    }
    if (prod == null && nome.isNotEmpty) {
      prod = produtosBox.values.firstWhereOrNull(
        (x) =>
            x.lojaId == lojaId &&
            x.nome.trim().toLowerCase() == nome.toLowerCase(),
      );
      if (prod != null) {
        logW(
          '[CATALOGO_ITEM] Resolução por nome (expandirEstoque) | lojaId=$lojaId | nome=$nome',
          tag: 'PRODUTO_FALLBACK',
        );
        reportProductResolvedByName(
          lojaId: lojaId,
          fluxo: 'expandirEstoque_item',
          nome: nome,
          slug: slug.isNotEmpty ? slug : null,
          productIdRecebido: productId.isNotEmpty ? productId : null,
        );
      }
    }
    if (prod == null) continue;

    final listaCombo = (item['itensComboComSelecao'] is List)
        ? (item['itensComboComSelecao'] as List).cast<Map<String, dynamic>>()
        : prod.itensCombo;
    if (prod.ehCombo && listaCombo != null && listaCombo.isNotEmpty) {
      for (final comboItem in listaCombo) {
        final idComp = (comboItem['id'] ?? comboItem['productId'] ?? '').toString().trim();
        final nomeComp = (comboItem['nome'] ?? '').toString();
        final slugComp = (comboItem['slug'] ?? '').toString();
        final qtdComp = (comboItem['quantidade'] is num
                ? (comboItem['quantidade'] as num).toInt()
                : int.tryParse('${comboItem['quantidade']}') ?? 1)
            .clamp(1, 9999);
        final tam = (comboItem['tamanho'] ?? '').toString();
        final corComp = (comboItem['cor'] ?? '').toString();
        final qtdTotal = qtd * qtdComp;
        if (nomeComp.isEmpty || qtdTotal <= 0) continue;

        // Ordem: productId → slug → nome. Logs [COMBO_ID] / [COMBO_FALLBACK] / [COMBO_ITEM].
        Produto? pComp;
        if (idComp.isNotEmpty) {
          pComp = produtosBox.values.firstWhereOrNull(
            (x) => x.lojaId == lojaId && x.idFirebase.trim() == idComp,
          );
          if (pComp != null) {
            logD(
              '[COMBO_ID] [COMBO_ITEM] Item combo por productId | lojaId=$lojaId | productId=$idComp | nome=${pComp.nome}',
            );
          }
        }
        if (pComp == null && slugComp.isNotEmpty) {
          pComp = produtosBox.values.firstWhereOrNull(
            (x) => x.lojaId == lojaId && x.slug.trim() == slugComp,
          );
          if (pComp != null) {
            logD(
              '[COMBO_FALLBACK] [COMBO_ITEM] Item combo por slug | lojaId=$lojaId | slug=$slugComp | nome=$nomeComp',
            );
          }
        }
        if (pComp == null && nomeComp.isNotEmpty) {
          pComp = produtosBox.values.firstWhereOrNull(
            (x) =>
                x.lojaId == lojaId &&
                x.nome.trim().toLowerCase() == nomeComp.trim().toLowerCase(),
          );
          if (pComp != null) {
            logW(
              '[COMBO_FALLBACK] [COMBO_ITEM] Item combo por nome | lojaId=$lojaId | nome=$nomeComp',
              tag: 'COMBO_FALLBACK',
            );
            reportProductResolvedByName(
              lojaId: lojaId,
              fluxo: 'expandirEstoque_combo_item',
              nome: nomeComp,
              slug: slugComp.isNotEmpty ? slugComp : null,
              productIdRecebido: idComp.isNotEmpty ? idComp : null,
            );
          }
        }
        if (pComp == null) continue;

        result.add({
          'nome': pComp.nome,
          'slug': pComp.slug,
          if (pComp.idFirebase.isNotEmpty) 'productId': pComp.idFirebase,
          'quantidade': qtdTotal,
          'tamanho': tam,
          'cor': corComp,
        });
      }
    } else {
      result.add({
        'nome': prod.nome,
        'slug': prod.slug,
        if (prod.idFirebase.isNotEmpty) 'productId': prod.idFirebase,
        'quantidade': qtd,
        'tamanho': tamanho,
        'cor': cor,
      });
    }
  }
  return result;
}

