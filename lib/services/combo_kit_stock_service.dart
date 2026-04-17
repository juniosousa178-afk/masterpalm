// Ajuste do estoque do produto "combo" ao máximo de kits montáveis após baixa nos componentes.

import 'dart:math' show min;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/produto_variacao_extra.dart';
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

  /// Estoque **total** disponível do produto filho (soma de todas as variações / tamanhos / quantidade simples).
  /// Usado para saber quantos kits o combo ainda permite montar, sem depender de tamanho/cor da receita fixa.
  static int estoqueTotalDisponivelProduto(Produto p) {
    if (p.usaVariacoes && p.variacoes != null && p.variacoes!.isNotEmpty) {
      var total = 0;
      for (final mapaTamanho in p.variacoes!.values) {
        if (mapaTamanho is! Map) continue;
        for (final cell in mapaTamanho.values) {
          total += ProdutoVariacaoExtra.somarCelula(cell);
        }
      }
      return total;
    }
    if (p.estoquePorTamanho.isNotEmpty) {
      return p.estoquePorTamanho.values.fold<int>(0, (a, b) => a + b);
    }
    return p.quantidade;
  }

  /// Quantos kits completos ainda dá para montar com o estoque atual dos componentes.
  ///
  /// **Somente combo legado** com receita fixa em [Produto.itensCombo]. Combos com
  /// [Produto.temComboConfigEfetivo] não usam este teto (ajuste pós-baixa é ignorado para eles).
  ///
  /// Regra: para cada item da receita, `capacidade = piso(estoque total do filho / qtd exigida)`;
  /// o resultado é o **mínimo** entre as capacidades (gargalo).
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
      final totalDisponivel = estoqueTotalDisponivelProduto(pComp);
      final kits = totalDisponivel ~/ qtdNec;
      final prev = maxKits;
      maxKits = prev == null ? kits : min(prev, kits);
    }
    return maxKits ?? 0;
  }

  /// ProductIds debitados na transação (para filtrar combos afetados).
  static Set<String> produtoIdsDeResultadosBaixa(List<EstoqueTransactionResult> results) {
    return {
      for (final r in results)
        if (r.produtoId.trim().isNotEmpty) r.produtoId.trim(),
    };
  }

  /// Combos da loja cujo SKU **ou** algum filho da receita (`id` / `productId`) está em [debitedIds].
  static List<Produto> combosAfetadosPorProductIdsDebitados({
    required String lojaId,
    required Box<Produto> produtosBox,
    required Set<String> debitedIds,
  }) {
    if (debitedIds.isEmpty) return [];
    final out = <Produto>[];
    for (final combo in produtosBox.values) {
      if (combo.lojaId != lojaId || !combo.ehCombo) continue;
      if (combo.usaVariacoes || combo.estoquePorTamanho.isNotEmpty) continue;

      final sku = combo.idFirebase.trim();
      if (sku.isNotEmpty && debitedIds.contains(sku)) {
        out.add(combo);
        continue;
      }

      final lista = combo.itensCombo;
      if (lista == null) continue;
      for (final item in lista) {
        final cid = (item['id'] ?? item['productId'] ?? '').toString().trim();
        if (cid.isNotEmpty && debitedIds.contains(cid)) {
          out.add(combo);
          break;
        }
      }
    }
    return out;
  }

  /// Reduz [Produto.quantidade] dos combos cujo teto [K] ficou abaixo do cadastrado.
  ///
  /// Se [produtoIdsDebitadosNaVenda] for `null`, percorre todos os combos elegíveis da loja (legado).
  /// Se for não vazio, ajusta **apenas** combos cujo SKU ou receita referencia algum desses ids — evita
  /// trabalho quando a baixa é de produto que não entra em combo. Se não houver combo correspondente,
  /// não aplica teto (comportamento esperado para venda avulsa sem vínculo).
  static Future<List<EstoqueTransactionResult>> aplicarTetoEstoqueComboAposBaixa({
    required String lojaId,
    required Box<Produto> produtosBox,
    Set<String>? produtoIdsDebitadosNaVenda,
  }) async {
    final debitedNorm = produtoIdsDebitadosNaVenda
        ?.map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    late final Iterable<Produto> combosAlvo;
    if (debitedNorm == null) {
      combosAlvo = produtosBox.values;
    } else if (debitedNorm.isEmpty) {
      debugPrint('[COMBO_TETO] produtoIdsDebitadosNaVenda vazio; sem ajuste de teto.');
      return [];
    } else {
      final filtrados = combosAfetadosPorProductIdsDebitados(
        lojaId: lojaId,
        produtosBox: produtosBox,
        debitedIds: debitedNorm,
      );
      if (filtrados.isEmpty) {
        debugPrint(
          '[COMBO_TETO] Nenhum combo referencia os productIds baixados (${debitedNorm.length} id(s)); sem ajuste de teto.',
        );
        return [];
      }
      combosAlvo = filtrados;
    }

    final ajustes = <Map<String, dynamic>>[];

    for (final combo in combosAlvo) {
      if (combo.lojaId != lojaId || !combo.ehCombo) continue;

      if (combo.usaVariacoes ||
          combo.estoquePorTamanho.isNotEmpty) {
        continue;
      }

      // Combo configurável: teto por receita fixa em [itensCombo] não reflete a montagem real.
      if (combo.temComboConfigEfetivo) {
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
  ///
  /// Se [produtoIdsQueAfetamCombo] for `null`, percorre todos os combos elegíveis (legado).
  /// Se for não vazio, ajusta apenas combos cuja receita ou SKU referencia algum desses ids.
  static Future<List<EstoqueTransactionResult>> aplicarPisoEstoqueComboAposDevolucao({
    required String lojaId,
    required Box<Produto> produtosBox,
    Set<String>? produtoIdsQueAfetamCombo,
  }) async {
    final norm = produtoIdsQueAfetamCombo
        ?.map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    late final Iterable<Produto> combosAlvo;
    if (norm == null) {
      combosAlvo = produtosBox.values;
    } else if (norm.isEmpty) {
      debugPrint('[COMBO_PISO] produtoIdsQueAfetamCombo vazio; sem ajuste de piso.');
      return [];
    } else {
      final filtrados = combosAfetadosPorProductIdsDebitados(
        lojaId: lojaId,
        produtosBox: produtosBox,
        debitedIds: norm,
      );
      if (filtrados.isEmpty) {
        debugPrint(
          '[COMBO_PISO] Nenhum combo referencia os productIds (${norm.length} id(s)); sem ajuste de piso.',
        );
        return [];
      }
      combosAlvo = filtrados;
    }

    final ajustes = <Map<String, dynamic>>[];

    for (final combo in combosAlvo) {
      if (combo.lojaId != lojaId || !combo.ehCombo) continue;

      if (combo.usaVariacoes || combo.estoquePorTamanho.isNotEmpty) {
        continue;
      }

      if (combo.temComboConfigEfetivo) {
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
