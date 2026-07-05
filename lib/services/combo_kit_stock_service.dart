// Ajuste do estoque do produto "combo" ao máximo de kits montáveis após baixa nos componentes.

import 'dart:math' show min;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/dart_error_unwrap.dart';
import '../core/logger.dart';
import '../core/produto_variacao_extra.dart';
import '../models/produto.dart';
import 'estoque_transaction_service.dart';
import 'produto_exclusao_tombstone_service.dart';
import 'produtos_firestore_service.dart';
import 'sync_queue_service.dart';
import 'venda_estoque_remoto_prep_service.dart';

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

    final ajustesRemotos = <Map<String, dynamic>>[];
    final combosSomenteHive = <({Produto combo, int k, int qtdAnterior, int delta})>[];

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

      final existeRemoto =
          await VendaEstoqueRemotoPrepService.produtoExisteNoEstoqueRemoto(
        lojaId: lojaId,
        produto: combo,
      );
      if (existeRemoto) {
        ajustesRemotos.add({
          'nome': combo.nome,
          'quantidade': delta,
          'tamanho': '',
          'cor': '',
          if (combo.idFirebase.trim().isNotEmpty) 'productId': combo.idFirebase,
          if (combo.slug.trim().isNotEmpty) 'slug': combo.slug,
        });
      } else {
        combosSomenteHive.add((
          combo: combo,
          k: k,
          qtdAnterior: combo.quantidade,
          delta: delta,
        ));
      }
    }

    final results = <EstoqueTransactionResult>[];

    for (final item in combosSomenteHive) {
      final r = await _aplicarTetoLocalComboSomenteHive(
        lojaId: lojaId,
        combo: item.combo,
        tetoK: item.k,
        quantidadeAnterior: item.qtdAnterior,
        delta: item.delta,
      );
      if (r != null) results.add(r);
    }

    if (ajustesRemotos.isEmpty) return results;

    final remotos = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
      lojaId: lojaId,
      itens: ajustesRemotos,
    );
    results.addAll(remotos);

    for (final result in remotos) {
      await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: produtosBox,
        lojaId: lojaId,
        result: result,
      );
    }
    await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(
      lojaId,
      remotos,
    );
    return results;
  }

  /// Recalcula teto absoluto no Hive e enfileira sync eventual (combo ausente na nuvem).
  static Future<EstoqueTransactionResult?> _aplicarTetoLocalComboSomenteHive({
    required String lojaId,
    required Produto combo,
    required int tetoK,
    required int quantidadeAnterior,
    required int delta,
  }) async {
    final docId = combo.idFirebase.trim();
    await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);
    if (docId.isNotEmpty &&
        await ProdutoExclusaoTombstoneService.isProdutoBloqueadoRemoto(
          lojaId: lojaId,
          estoqueDocId: docId,
        )) {
      logW(
        '[COMBO_CONVERGE] tombstone — não ressuscita combo $docId',
        tag: 'COMBO_TETO',
      );
      return null;
    }

    debugPrint(
      '[COMBO_CAP_LOCAL] ${combo.nome}: $quantidadeAnterior → teto K=$tetoK '
      '(somente Hive; sync eventual)',
    );

    combo.quantidade = tetoK;
    combo.updatedAt = DateTime.now();
    await combo.save();

    await _enfileirarConvergenciaComboEventual(lojaId: lojaId, combo: combo);

    return EstoqueTransactionResult(
      produtoId: docId.isNotEmpty ? docId : combo.slug.trim(),
      produtoNome: combo.nome,
      produtoSlug: combo.slug.trim().isEmpty ? null : combo.slug.trim(),
      quantidadeDebitada: delta,
      quantidadeTotalAtualizada: tetoK,
      ajusteCapComboSomenteHive: true,
      quantidadeComboAntesAjusteLocal: quantidadeAnterior,
    );
  }

  /// Sync eventual via pipeline existente; falha vira fila [SyncQueueService].
  static Future<void> _enfileirarConvergenciaComboEventual({
    required String lojaId,
    required Produto combo,
  }) async {
    final hook = debugEnfileirarConvergenciaComboOverride;
    if (hook != null) {
      await hook(lojaId: lojaId, combo: combo);
      return;
    }
    try {
      await ProdutosFirestoreService.syncProdutoComStatus(
        combo,
        lojaId: lojaId,
        enqueueOnFailure: true,
        bumpHiveTimestamp: false,
        writeOrigin: 'combo_cap_pos_venda',
      );
    } catch (e, st) {
      logW(
        '[COMBO_CONVERGE] falha sync imediato — tentando fila | $e',
        tag: 'COMBO_TETO',
      );
      assert(() {
        debugPrint('[COMBO_CONVERGE] st=$st');
        return true;
      }());
      final key = combo.key;
      final boxName = combo.box?.name;
      if (key == null || boxName == null) return;
      final parsedKey = key is int ? key : int.tryParse(key.toString());
      if (parsedKey == null) return;
      await SyncQueueService.enqueue(
        type: SyncOperationType.upsertProduto,
        lojaId: lojaId,
        boxName: boxName,
        entityKey: parsedKey,
        lastError: formatDartErrorForUser(e),
      );
    }
  }

  /// Rollback pré-Hive: restaura quantidade local de combos ajustados só no Hive.
  static Future<void> reverterAjusteCapComboSomenteHive({
    required String lojaId,
    required Box<Produto> produtosBox,
    required List<EstoqueTransactionResult> results,
  }) async {
    for (final r in results) {
      if (!r.ajusteCapComboSomenteHive) continue;
      final qtdAnt = r.quantidadeComboAntesAjusteLocal;
      if (qtdAnt == null) continue;
      final pid = r.produtoId.trim();
      Produto? combo;
      if (pid.isNotEmpty) {
        combo = produtosBox.values.firstWhereOrNull(
          (p) => p.lojaId == lojaId && p.idFirebase.trim() == pid,
        );
      }
      combo ??= produtosBox.values.firstWhereOrNull(
        (p) =>
            p.lojaId == lojaId &&
            p.nome.trim().toLowerCase() == r.produtoNome.trim().toLowerCase(),
      );
      if (combo == null) continue;
      combo.quantidade = qtdAnt;
      await combo.save();
      debugPrint(
        '[COMBO_CAP_LOCAL] rollback ${combo.nome}: restaurado para $qtdAnt',
      );
    }
  }

  @visibleForTesting
  static Future<void> Function({
    required String lojaId,
    required Produto combo,
  })? debugEnfileirarConvergenciaComboOverride;

  /// Teto do SKU combo após baixa dos componentes — **manutenção secundária**.
  ///
  /// A baixa principal da venda já foi commitada em transação anterior; falha aqui
  /// (combo só-local, pendente de sync, not-found, etc.) não deve impedir [vendasBox.add].
  static Future<List<EstoqueTransactionResult>>
      aplicarTetoEstoqueComboAposBaixaSemAbortarVenda({
    required String lojaId,
    required Box<Produto> produtosBox,
    Set<String>? produtoIdsDebitadosNaVenda,
  }) async {
    try {
      return await aplicarTetoEstoqueComboAposBaixa(
        lojaId: lojaId,
        produtosBox: produtosBox,
        produtoIdsDebitadosNaVenda: produtoIdsDebitadosNaVenda,
      );
    } catch (e, st) {
      final detalhe = formatDartErrorForUser(e);
      debugPrint(
        '[COMBO_TETO] ⚠️ Ajuste pós-venda ignorado (venda principal mantida): $detalhe',
      );
      logW(
        '[COMBO_TETO] Ajuste ignorado após baixa principal | lojaId=$lojaId | $detalhe',
        tag: 'VENDA',
      );
      assert(() {
        debugPrint('[COMBO_TETO] st=$st');
        return true;
      }());
      return [];
    }
  }

  /// Classifica falhas típicas do ajuste de teto (manutenção, não venda principal).
  @visibleForTesting
  static bool isFalhaSecundariaManutencaoTetoCombo(Object e) {
    final msg = formatDartErrorForUser(e).toLowerCase();
    if (msg.contains('nuvem')) return true;
    if (msg.contains('sincroniz') || msg.contains('sincron')) return true;
    if (msg.contains('not-found') || msg.contains('not found')) return true;
    if (msg.contains('não encontrado no estoque da nuvem')) return true;
    if (msg.contains('não encontrado no servidor')) return true;
    if (msg.contains('documento válido de estoque')) return true;
    return false;
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
