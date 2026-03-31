// Ajuste do estoque do produto "combo" ao máximo de kits montáveis após baixa nos componentes.

import 'dart:math' show min;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/produto.dart';
import 'estoque_transaction_service.dart';

/// Após venda de componentes avulsos (ou combo), garante que a quantidade do SKU combo
/// não exceda o que os componentes ainda permitem montar.
class ComboKitStockService {
  static Produto? _resolverComponente(
    Map<String, dynamic> comboItem,
    Box<Produto> produtosBox,
    String lojaId,
  ) {
    final idComp =
        (comboItem['id'] ?? comboItem['productId'] ?? '').toString().trim();
    final slugComp = (comboItem['slug'] ?? '').toString().trim();
    final nomeComp = (comboItem['nome'] ?? '').toString();

    Produto? pComp;
    if (idComp.isNotEmpty) {
      pComp = produtosBox.values.firstWhereOrNull(
        (prod) => prod.lojaId == lojaId && prod.idFirebase.trim() == idComp,
      );
    }
    if (pComp == null && slugComp.isNotEmpty) {
      pComp = produtosBox.values.firstWhereOrNull(
        (prod) => prod.lojaId == lojaId && prod.slug.trim() == slugComp,
      );
    }
    if (pComp == null && nomeComp.isNotEmpty) {
      pComp = produtosBox.values.firstWhereOrNull(
        (prod) =>
            prod.lojaId == lojaId &&
            prod.nome.trim().toLowerCase() == nomeComp.trim().toLowerCase(),
      );
    }
    return pComp;
  }

  /// Estoque disponível na linha da receita (alinhado a [Produto.obterEstoqueVariacao] / total).
  static int estoqueDisponivelLinha(
    Produto p,
    String tam,
    String cor,
    String extra,
  ) {
    final ex = extra.trim();
    final t = tam.trim();
    final c = cor.trim();

    if (p.temVariacaoSoloCor && c.isNotEmpty) {
      return p.obterEstoqueVariacao('', c, ex);
    }
    if (p.usaVariacoes && (t.isNotEmpty || c.isNotEmpty)) {
      final tamKey = t.isEmpty ? '' : t;
      final corKey = c.isEmpty ? 'sem-cor' : c;
      return p.obterEstoqueVariacao(tamKey, corKey, ex);
    }
    if (p.estoquePorTamanho.isNotEmpty && t.isNotEmpty) {
      return p.estoquePorTamanho[t] ?? 0;
    }
    return p.quantidade;
  }

  /// Quantos kits completos ainda dá para montar com o estoque atual dos componentes.
  static int maxKitsMontaveis(
    Produto combo,
    Box<Produto> produtosBox,
    String lojaId,
  ) {
    final lista = combo.itensCombo;
    if (lista == null || lista.isEmpty) {
      return 999999;
    }

    int? maxKits;
    for (final comboItem in lista) {
      final pComp = _resolverComponente(comboItem, produtosBox, lojaId);
      if (pComp == null) {
        return 0;
      }
      final qtdNec = ((comboItem['quantidade']) is num
              ? (comboItem['quantidade'] as num).toInt()
              : int.tryParse('${comboItem['quantidade']}') ?? 1)
          .clamp(1, 9999);
      final tam = (comboItem['tamanho'] ?? '').toString();
      final cor = (comboItem['cor'] ?? '').toString();
      final ex = (comboItem['extraValor'] ?? '').toString();
      final avail = estoqueDisponivelLinha(pComp, tam, cor, ex);
      final kits = avail ~/ qtdNec;
      final prev = maxKits;
      maxKits = prev == null ? kits : min(prev, kits);
    }
    return maxKits ?? 0;
  }

  /// Reduz [Produto.quantidade] dos combos cujo teto [K] ficou abaixo do cadastrado.
  static Future<List<EstoqueTransactionResult>> aplicarTetoEstoqueComboAposBaixa({
    required String lojaId,
    required Box<Produto> produtosBox,
  }) async {
    final ajustes = <Map<String, dynamic>>[];

    for (final combo in produtosBox.values) {
      if (combo.lojaId != lojaId || !combo.ehCombo) continue;

      if (combo.usaVariacoes ||
          combo.estoquePorTamanho.isNotEmpty) {
        continue;
      }

      final k = maxKitsMontaveis(combo, produtosBox, lojaId);
      if (combo.quantidade <= k) continue;

      final delta = combo.quantidade - k;
      if (delta <= 0) continue;

      debugPrint(
        '[COMBO_CAP] ${combo.nome}: quantidade combo=${combo.quantidade} → teto montável K=$k '
        '(baixa adicional de $delta no SKU combo)',
      );

      ajustes.add({
        'nome': combo.nome,
        'quantidade': delta,
        'tamanho': '',
        'cor': '',
        if (combo.idFirebase.trim().isNotEmpty) 'productId': combo.idFirebase,
        if (combo.slug.trim().isNotEmpty) 'slug': combo.slug,
      });
    }

    if (ajustes.isEmpty) return [];

    final results = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
      lojaId: lojaId,
      itens: ajustes,
    );

    for (final result in results) {
      await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: produtosBox,
        lojaId: lojaId,
        result: result,
      );
    }
    await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(
      lojaId,
      results,
    );
    return results;
  }

  /// Após devolução de componentes (ou combo), sobe [Produto.quantidade] do SKU combo até o teto [K]
  /// montável — espelho inverso de [aplicarTetoEstoqueComboAposBaixa].
  static Future<List<EstoqueTransactionResult>> aplicarPisoEstoqueComboAposDevolucao({
    required String lojaId,
    required Box<Produto> produtosBox,
  }) async {
    final ajustes = <Map<String, dynamic>>[];

    for (final combo in produtosBox.values) {
      if (combo.lojaId != lojaId || !combo.ehCombo) continue;

      if (combo.usaVariacoes || combo.estoquePorTamanho.isNotEmpty) {
        continue;
      }

      final k = maxKitsMontaveis(combo, produtosBox, lojaId);
      if (combo.quantidade >= k) continue;

      final delta = k - combo.quantidade;
      if (delta <= 0) continue;

      debugPrint(
        '[COMBO_PISO] ${combo.nome}: quantidade combo=${combo.quantidade} → teto montável K=$k '
        '(crédito de $delta no SKU combo)',
      );

      ajustes.add({
        'nome': combo.nome,
        'quantidade': delta,
        'tamanho': '',
        'cor': '',
        if (combo.idFirebase.trim().isNotEmpty) 'productId': combo.idFirebase,
        if (combo.slug.trim().isNotEmpty) 'slug': combo.slug,
      });
    }

    if (ajustes.isEmpty) return [];

    final results = await EstoqueTransactionService.devolverEstoqueTransactionBatch(
      lojaId: lojaId,
      itens: ajustes,
      vendaIdParaIdempotencia: null,
    );

    for (final result in results) {
      await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: produtosBox,
        lojaId: lojaId,
        result: result,
      );
    }
    return results;
  }
}
