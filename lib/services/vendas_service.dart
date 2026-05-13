// lib/services/vendas_service.dart
//
// Serviço de vendas para a tela "Nova Venda"
// ATUALIZADO: Agora sincroniza estoque no Firestore após baixar variações
import 'package:collection/collection.dart'; // firstWhereOrNull
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:hive/hive.dart';

import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';
import '../models/conta_receber.dart';
import '../core/hive_box_names.dart';
import '../core/strict_product_resolution.dart';
import '../utils/text_utils.dart';
import '../services/campaign_engine_service.dart'; // 🎯 integração com campanhas/sorteio (centralizado)
import '../services/clientes_firestore_service.dart'; // 🔹 sincronização de clientes
import '../services/vendas_firestore_service.dart'; // 🔹 sincronização com Firestore
import 'contas_receber_firestore_service.dart';
import 'catalogo_web_apos_estoque_service.dart';
import 'combo_kit_stock_service.dart';
import 'estoque_transaction_service.dart';
import 'movimentacao_estoque_service.dart';
import 'venda_combo_estoque_expansion.dart';
import 'venda_custo_mercadoria.dart';

/// Dados congelados da venda original antes de [VendasService.desfazerVenda] na edição.
/// Não altera typeIds Hive — só transporta cópias em memória.
class EdicaoVendaRollbackSnapshot {
  EdicaoVendaRollbackSnapshot({
    required this.lojaId,
    required this.itens,
    required this.clienteNome,
    this.clienteIdRef,
    this.itensComboSelecaoJson,
    required this.dinheiro,
    required this.pix,
    required this.cartao,
    required this.frete,
    required this.descontoPct,
    required this.observacao,
    required this.vendedor,
    required this.dataHora,
    this.idFirebase,
    required this.isFiado,
    required this.quantidadeParcelasFiado,
    required this.intervaloParcelasDias,
    this.parcelasDataVencimentoFiadoPreservadas,
  });

  final String lojaId;
  final List<VendaItem> itens;
  final String clienteNome;
  final String? clienteIdRef;
  final String? itensComboSelecaoJson;
  final double dinheiro;
  final double pix;
  final double cartao;
  final double frete;
  final double descontoPct;
  final String observacao;
  final String vendedor;
  final DateTime dataHora;
  final String? idFirebase;
  final bool isFiado;
  final int quantidadeParcelasFiado;
  final int intervaloParcelasDias;
  final List<DateTime>? parcelasDataVencimentoFiadoPreservadas;
}

class VendasService {
  // ---------------------------
  // Helpers
  // ---------------------------

  static String _fmt2(double v) => v.toStringAsFixed(2);

  static VendaItem _cloneVendaItemParaRollback(VendaItem i, String lojaId) {
    return VendaItem(
      produtoNome: i.produtoNome,
      quantidade: i.quantidade,
      precoUnitario: i.precoUnitario,
      tamanho: i.tamanho,
      lojaId: i.lojaId.trim().isNotEmpty ? i.lojaId : lojaId,
      cor: i.cor,
      productId: i.productId,
      variacaoExtraResumo: i.variacaoExtraResumo,
      extraValor: i.extraValor,
      custoUnitario: i.custoUnitario,
      origemCustoItem: i.origemCustoItem,
    );
  }

  static List<VendaItem> _itensRollbackLegadoSemLista(Venda v, String lojaId) {
    String nomeProd = '';
    var qtdLegado = v.quantidade;
    var precoLegado = v.preco;
    try {
      final linhas = v.produtosDescricao.split('\n');
      final linha = linhas.isNotEmpty ? linhas.first.trim() : '';
      if (linha.isEmpty) {
        nomeProd = 'Produto';
      } else {
        nomeProd = linha;
        final idxX = linha.indexOf(' x ');
        if (idxX >= 0) {
          final rest = linha.substring(idxX + 3);
          final idxDelim = rest.indexOf(' - R\$');
          nomeProd = idxDelim >= 0 ? rest.substring(0, idxDelim).trim() : rest.trim();
          final qtdStr = linha.substring(0, idxX).trim();
          qtdLegado = int.tryParse(qtdStr) ?? v.quantidade;
        }
      }
    } catch (_) {
      nomeProd = v.produtosDescricao.trim().isNotEmpty
          ? v.produtosDescricao.split('\n').first.trim()
          : 'Produto';
    }
    return [
      VendaItem(
        produtoNome: nomeProd,
        quantidade: qtdLegado < 1 ? 1 : qtdLegado,
        precoUnitario: precoLegado,
        tamanho: v.tamanho,
        lojaId: lojaId,
        cor: '',
        extraValor: '',
        variacaoExtraResumo: '',
      ),
    ];
  }

  static List<VendaItem> clonarItensOuLegadoParaRollback(Venda v, String lojaId) {
    if (v.itens != null && v.itens!.isNotEmpty) {
      return v.itens!.map((e) => _cloneVendaItemParaRollback(e, lojaId)).toList();
    }
    return _itensRollbackLegadoSemLista(v, lojaId);
  }

  /// Captura estado da venda antes de [desfazerVenda] (incl. parcelas fiado no Hive).
  static Future<EdicaoVendaRollbackSnapshot> capturarSnapshotEdicaoVenda({
    required Venda venda,
    required String lojaId,
  }) async {
    final lid = lojaId.trim();
    if (lid.isEmpty) {
      throw ArgumentError('lojaId obrigatório para snapshot de edição');
    }
    final itens = clonarItensOuLegadoParaRollback(venda, lid);
    final fiadoPorTexto =
        venda.formasPagamento.toLowerCase().contains('fiado');
    final vk = venda.key is int ? venda.key as int : 0;
    final contasLinked = <ContaReceber>[];
    if (vk > 0) {
      try {
        final crName = HiveBoxNames.contasReceber(lid);
        final crBox = Hive.isBoxOpen(crName)
            ? Hive.box<ContaReceber>(crName)
            : await Hive.openBox<ContaReceber>(crName);
        for (final c in crBox.values) {
          if (c.lojaId == lid && c.vendaKey == vk) {
            contasLinked.add(c);
          }
        }
      } catch (_) {}
    }
    contasLinked.sort((a, b) => a.parcelaNumero.compareTo(b.parcelaNumero));

    final usarFiado = contasLinked.isNotEmpty || fiadoPorTexto;
    List<DateTime>? parcelasPreservadas;
    var qtdParc = 1;
    var intervalo = 30;

    if (usarFiado && contasLinked.isNotEmpty) {
      var totPar = 1;
      for (final c in contasLinked) {
        if (c.parcelaTotal > totPar) totPar = c.parcelaTotal;
      }
      qtdParc = totPar.clamp(1, 48);
      final esperado =
          <int>{for (var i = 1; i <= qtdParc; i++) i};
      final porNumero = <int, ContaReceber>{};
      for (final c in contasLinked) {
        porNumero[c.parcelaNumero] = c;
      }
      if (porNumero.length == qtdParc &&
          esperado.difference(porNumero.keys.toSet()).isEmpty) {
        parcelasPreservadas = List.generate(
          qtdParc,
          (i) {
            final dt = porNumero[i + 1]!.dataVencimento;
            return DateTime(dt.year, dt.month, dt.day);
          },
        );
        if (parcelasPreservadas.length >= 2) {
          final gap =
              parcelasPreservadas[1].difference(parcelasPreservadas[0]).inDays;
          if (gap > 0 && gap <= 120) {
            intervalo = gap;
          }
        }
      } else {
        parcelasPreservadas = [
          for (final c in contasLinked)
            DateTime(
              c.dataVencimento.year,
              c.dataVencimento.month,
              c.dataVencimento.day,
            ),
        ];
        qtdParc = parcelasPreservadas.length.clamp(1, 48);
        if (parcelasPreservadas.length >= 2) {
          final gap =
              parcelasPreservadas[1].difference(parcelasPreservadas[0]).inDays;
          if (gap > 0 && gap <= 120) {
            intervalo = gap;
          }
        }
      }
    } else if (usarFiado && contasLinked.isEmpty) {
      final match = RegExp(
        r'Vencimento:\s*(\d{2})/(\d{2})/(\d{4})',
        caseSensitive: false,
      ).firstMatch(venda.formasPagamento);
      if (match != null) {
        final venc = DateTime(
          int.parse(match.group(3)!),
          int.parse(match.group(2)!),
          int.parse(match.group(1)!),
        );
        parcelasPreservadas = [DateTime(venc.year, venc.month, venc.day)];
        qtdParc = 1;
      }
    }

    return EdicaoVendaRollbackSnapshot(
      lojaId: lid,
      itens: itens,
      clienteNome: venda.clienteNome,
      clienteIdRef: venda.clienteId,
      itensComboSelecaoJson: venda.itensComboSelecaoJson,
      dinheiro: venda.pagamentoDinheiro,
      pix: venda.pagamentoPix,
      cartao: venda.pagamentoCartao,
      frete: venda.frete,
      descontoPct: venda.desconto,
      observacao: venda.observacao,
      vendedor: venda.vendedor,
      dataHora: venda.data,
      idFirebase: venda.idFirebase,
      isFiado: usarFiado,
      quantidadeParcelasFiado: qtdParc,
      intervaloParcelasDias: intervalo,
      parcelasDataVencimentoFiadoPreservadas: parcelasPreservadas,
    );
  }

  /// Após falha ao salvar edição: remove venda órfã com o mesmo [idFirebase] (se houver) e
  /// recria a venda original via [registrarVendaMulti] (nova baixa de estoque — coerente com [desfazerVenda]).
  static Future<bool> tentarRestaurarVendaOriginalAposFalhaEdicao({
    required EdicaoVendaRollbackSnapshot snap,
    required Box<Produto> produtosBox,
    required Box<Cliente> clientesBox,
    required Box<Venda> vendasBox,
    Cliente? clienteHint,
    void Function(String message)? onSyncError,
  }) async {
    try {
      final targetId = (snap.idFirebase ?? '').trim();
      if (targetId.isNotEmpty) {
        final orphans = vendasBox.values
            .where((x) => (x.idFirebase ?? '').trim() == targetId)
            .toList();
        for (final orphan in orphans) {
          await desfazerVenda(
            produtosBox: produtosBox,
            clientesBox: clientesBox,
            vendasBox: vendasBox,
            venda: orphan,
          );
        }
      }

      Cliente? clienteExistente;
      if (clienteHint != null &&
          clienteHint.nome.trim().toLowerCase() ==
              snap.clienteNome.trim().toLowerCase()) {
        clienteExistente = clienteHint;
      }
      final idRef = snap.clienteIdRef?.trim();
      if (clienteExistente == null && idRef != null && idRef.isNotEmpty) {
        clienteExistente = clientesBox.values.firstWhereOrNull(
          (c) =>
              c.lojaId == snap.lojaId &&
              (c.key?.toString() == idRef || c.idFirebase == idRef),
        );
      }
      clienteExistente ??= clientesBox.values.firstWhereOrNull(
        (c) =>
            c.lojaId == snap.lojaId &&
            c.nome.trim().toLowerCase() ==
                snap.clienteNome.trim().toLowerCase(),
      );

      final comboMap =
          VendaComboEstoqueExpansion.parseItensComboSelecaoPorIndiceJson(
        snap.itensComboSelecaoJson,
      );

      DateTime? dataVencimentoFiadoArg;
      List<DateTime>? parcelasArg = snap.parcelasDataVencimentoFiadoPreservadas;
      if (snap.isFiado) {
        if (parcelasArg != null &&
            parcelasArg.length == snap.quantidadeParcelasFiado) {
          final d0 = parcelasArg.first;
          dataVencimentoFiadoArg = DateTime(d0.year, d0.month, d0.day);
        } else {
          final base = DateTime(
            snap.dataHora.year,
            snap.dataHora.month,
            snap.dataHora.day,
          );
          dataVencimentoFiadoArg =
              base.add(Duration(days: snap.intervaloParcelasDias));
          parcelasArg = null;
        }
      } else {
        dataVencimentoFiadoArg = null;
        parcelasArg = null;
      }

      await registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: snap.clienteNome,
        itens: snap.itens,
        dinheiro: snap.dinheiro,
        pix: snap.pix,
        cartao: snap.cartao,
        vendedor: snap.vendedor,
        observacao: snap.observacao,
        frete: snap.frete,
        descontoPct: snap.descontoPct,
        lojaId: snap.lojaId,
        clienteExistente: clienteExistente,
        idFirebaseToReuse: snap.idFirebase,
        dataHoraVenda: snap.dataHora,
        onSyncError: onSyncError,
        isFiado: snap.isFiado,
        dataVencimentoFiado: dataVencimentoFiadoArg,
        quantidadeParcelasFiado: snap.quantidadeParcelasFiado,
        intervaloParcelasDias: snap.intervaloParcelasDias,
        parcelasDataVencimentoFiadoPreservadas: parcelasArg,
        itensComboSelecaoPorIndice: comboMap,
        suprimirCampanhaSorteio: true,
      );
      return true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '[EDICAO-VENDA-ROLLBACK] Falha ao restaurar venda original: $e',
        );
        debugPrint('$st');
      }
      return false;
    }
  }
  static List<double> _parcelarValores(double total, int parcelas) {
    final qtd = parcelas.clamp(1, 48);
    final totalCentavos = (total * 100).round();
    final base = totalCentavos ~/ qtd;
    final resto = totalCentavos % qtd;
    return List<double>.generate(
      qtd,
      (i) => (base + (i < resto ? 1 : 0)) / 100.0,
    );
  }

  static double _resolverCustoItem(Produto produto, VendaItem item) {
    final custoVariacao = produto.custoUnitarioVariacao(
      item.tamanho,
      item.cor,
      item.extraValor,
    );
    if (custoVariacao > 0) return custoVariacao;
    if (produto.custoReal > 0) return produto.custoReal;
    return custoVariacao;
  }

  /// Remove contas a receber criadas para esta venda (mesmo [vendaKey] Hive).
  static Future<void> removerContasReceberVinculadasAVenda({
    required String lojaId,
    required int vendaKey,
    String? vendaFirebaseId,
  }) async {
    if (vendaKey <= 0) return;
    final loja = lojaId.trim();
    if (loja.isEmpty) return;
    try {
      await ContasReceberFirestoreService.marcarContasDaVendaComoCanceladasOuExcluidas(
        lojaId: loja,
        vendaKey: vendaKey,
        vendaFirebaseId: vendaFirebaseId,
      );
    } catch (e) {
      debugPrint('[VENDAS-SERVICE] marcar contas FS excluídas: $e');
    }
    try {
      final crBoxName = HiveBoxNames.contasReceber(loja);
      final crBox = Hive.isBoxOpen(crBoxName)
          ? Hive.box<ContaReceber>(crBoxName)
          : await Hive.openBox<ContaReceber>(crBoxName);
      final keysToDelete = <dynamic>[];
      for (final k in crBox.keys) {
        final c = crBox.get(k);
        if (c != null && c.lojaId == loja && c.vendaKey == vendaKey) {
          keysToDelete.add(k);
        }
      }
      for (final k in keysToDelete) {
        await crBox.delete(k);
      }
    } catch (e) {
      debugPrint(
        '[VENDAS-SERVICE] removerContasReceberVinculadasAVenda: $e',
      );
    }
  }

  /// Após desfazer exclusão de venda fiada: recria 1 título com o total (parcelas múltiplas viram um resumo).
  static Future<void> recriarContaReceberFiadoAposUndoSeAplicavel({
    required Venda venda,
    required String lojaId,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) return;
    if (!venda.formasPagamento.toLowerCase().contains('fiado')) return;
    final vk = venda.key is int ? venda.key as int : 0;
    if (vk <= 0) return;
    final match = RegExp(
      r'Vencimento:\s*(\d{2})/(\d{2})/(\d{4})',
      caseSensitive: false,
    ).firstMatch(venda.formasPagamento);
    late DateTime venc;
    if (match != null) {
      venc = DateTime(
        int.parse(match.group(3)!),
        int.parse(match.group(2)!),
        int.parse(match.group(1)!),
      );
    } else {
      venc = DateTime.now().add(const Duration(days: 30));
    }
    final crBoxName = HiveBoxNames.contasReceber(loja);
    final crBox = Hive.isBoxOpen(crBoxName)
        ? Hive.box<ContaReceber>(crBoxName)
        : await Hive.openBox<ContaReceber>(crBoxName);
    final novaConta = ContaReceber(
      lojaId: loja,
      clienteNome: venda.clienteNome,
      valor: venda.total,
      dataVencimento: venc,
      dataVenda: venda.data,
      vendaKey: vk,
      observacao: venda.observacao.trim().isEmpty
          ? 'Venda fiada'
          : venda.observacao.trim(),
    );
    await crBox.add(novaConta);
    try {
      await ContasReceberFirestoreService.upsertConta(
        conta: novaConta,
        lojaId: loja,
        vendaFirebaseId: (venda.idFirebase ?? '').trim().isEmpty
            ? null
            : venda.idFirebase!.trim(),
        formaOrigem: 'sync_hive',
      );
    } catch (e) {
      debugPrint('[VENDAS-SERVICE] upsert conta FS após undo: $e');
    }
  }

  /// Procura o produto no estoque por productId (preferencial), slug ou nome.
  /// Ordem: 1) productId/idFirebase, 2) slug, 3) nome.
  /// Loga [PRODUTO_FALLBACK] quando resolver por slug ou nome (observabilidade).
  static Produto? encontrarProdutoNoEstoque({
    required Box<Produto> produtosBox,
    String? productId,
    String? slug,
    String? nome,
    String? lojaId,
  }) {
    final idTrim = productId?.trim();
    final lowSlug = slug?.trim().toLowerCase();
    final lowNome = nome?.trim().toLowerCase();

    Iterable<Produto> lista = produtosBox.values;
    if (lojaId != null && lojaId.isNotEmpty) {
      lista = lista.where((p) => p.lojaId == lojaId);
    }

    // 1) productId / idFirebase
    if (idTrim != null && idTrim.isNotEmpty) {
      final p = lista.firstWhereOrNull(
        (prod) => prod.idFirebase.trim() == idTrim,
      );
      if (p != null) return p;
    }

    // 2) slug
    if (lowSlug != null && lowSlug.isNotEmpty) {
      final p = lista.firstWhereOrNull(
        (prod) => (prod.slug).trim().toLowerCase() == lowSlug,
      );
      if (p != null) {
        debugPrint(
          '[PRODUTO_FALLBACK] Resolução por slug | lojaId=$lojaId | slug=$lowSlug | nome=${p.nome} | productId=${p.idFirebase}',
        );
        return p;
      }
    }

    // 3) nome
    if (lowNome != null && lowNome.isNotEmpty) {
      final matches = lista.where(
        (prod) => prod.nome.trim().toLowerCase() == lowNome,
      ).toList();
      if (matches.length == 1) {
        debugPrint(
          '[PRODUTO_FALLBACK] Resolução por nome | lojaId=$lojaId | nome=$lowNome | productId=${matches.single.idFirebase} | matches=1',
        );
        reportProductResolvedByName(
          lojaId: lojaId ?? '',
          fluxo: 'encontrarProdutoNoEstoque',
          nome: lowNome,
          slug: lowSlug,
          productIdRecebido: idTrim,
        );
        return matches.single;
      }
      if (matches.length > 1) {
        debugPrint(
          '[PRODUTO_FALLBACK] Nome ambíguo | lojaId=$lojaId | nome=$lowNome | matches=${matches.length}',
        );
        reportProductResolvedByName(
          lojaId: lojaId ?? '',
          fluxo: 'encontrarProdutoNoEstoque_ambiguo',
          nome: lowNome,
          slug: lowSlug,
          productIdRecebido: idTrim,
        );
        return matches.first;
      }
    }

    return null;
  }

  static bool _vendaPareceIncluirKitOuComboReceita({
    required List<VendaItem> itens,
    required Box<Produto> produtosBox,
    required String lojaId,
  }) {
    for (final it in itens) {
      final p = encontrarProdutoNoEstoque(
        produtosBox: produtosBox,
        productId: it.productId,
        nome: it.produtoNome,
        lojaId: lojaId,
      );
      if (p == null) continue;
      if (p.ehCombo ||
          p.temComboConfigEfetivo ||
          (p.itensCombo != null && p.itensCombo!.isNotEmpty)) {
        return true;
      }
    }
    return false;
  }

  /// Mapas para [EstoqueTransactionService.devolverEstoqueTransactionBatch]: só **componentes**;
  /// nunca o produto kit virtual (cabeçalho com `linhaContaCustoMercadoria == false` ou `ehCombo`).
  static List<Map<String, dynamic>> _montarItensFirestoreDevolucaoAgrupados({
    required Venda venda,
    required Box<Produto> produtosBox,
    required String lojaId,
    required String vendaIdLog,
  }) {
    final itensVenda = venda.itens;
    if (itensVenda == null || itensVenda.isEmpty) return [];

    final rawJson = venda.itensComboSelecaoJson;
    final selecaoPersistida =
        VendaComboEstoqueExpansion.parseItensComboSelecaoPorIndiceJson(
      rawJson,
    );
    final snapKeys = selecaoPersistida?.keys.toList() ?? <int>[];
    final jsonVazio = rawJson == null || rawJson.trim().isEmpty;
    debugPrint(
      '[COMBO-DEVOLUCAO] vendaId=$vendaIdLog json_vazio=$jsonVazio keys=$snapKeys',
    );
    if (!jsonVazio && selecaoPersistida == null) {
      debugPrint(
        '[COMBO-DEVOLUCAO] vendaId=$vendaIdLog aviso=json_presente_mas_parse_falhou',
      );
    }

    final (itensDevolucao, produtosEnc, linhaFlags) =
        VendaComboEstoqueExpansion.expandirCombos(
      itens: itensVenda,
      produtosBox: produtosBox,
      lojaId: lojaId,
      itensComboSelecaoPorIndice: selecaoPersistida,
    );

    final Map<String,
            ({
              String? productId,
              String? slug,
              String nomeOriginal,
              String tam,
              String cor,
              String extra,
              int qtd
            })>
        agrupado = {};

    for (var i = 0; i < itensDevolucao.length; i++) {
      if (i >= linhaFlags.length || i >= produtosEnc.length) break;
      if (!linhaFlags[i]) {
        debugPrint(
          '[COMBO-DEVOLUCAO] vendaId=$vendaIdLog item=$i tipo=cabecalho_kit_skip nome=${itensDevolucao[i].produtoNome}',
        );
        continue;
      }
      if (produtosEnc[i].ehCombo) {
        debugPrint(
          '[COMBO-DEVOLUCAO] vendaId=$vendaIdLog item=$i tipo=produto_combo_skip nome=${produtosEnc[i].nome}',
        );
        continue;
      }
      final it = itensDevolucao[i];
      final pComp = produtosEnc[i];
      final pidLog =
          (it.productId ?? '').trim().isNotEmpty ? it.productId!.trim() : pComp.idFirebase.trim();
      debugPrint(
        '[COMBO-DEVOLUCAO] vendaId=$vendaIdLog item=$i tipo=componente produtoId=$pidLog nome=${it.produtoNome} qtd=${it.quantidade}',
      );
      final pid =
          (it.productId ?? '').trim().isNotEmpty ? it.productId!.trim() : null;
      final slugComp = pComp.slug.trim().isNotEmpty ? pComp.slug.trim() : null;
      final nomeLower = it.produtoNome.trim().toLowerCase();
      final nomeOriginal = it.produtoNome.trim();
      final tam = it.tamanho.trim();
      final cor = it.cor.trim();
      final extra = it.extraValor.trim();
      final key = '${pid ?? ''}\x00$nomeLower\x00$tam\x00$cor\x00$extra';
      final existing = agrupado[key];
      if (existing != null) {
        agrupado[key] = (
          productId: existing.productId,
          slug: existing.slug ?? slugComp,
          nomeOriginal: existing.nomeOriginal,
          tam: existing.tam,
          cor: existing.cor,
          extra: existing.extra,
          qtd: existing.qtd + it.quantidade,
        );
      } else {
        agrupado[key] = (
          productId: pid,
          slug: slugComp,
          nomeOriginal: nomeOriginal,
          tam: tam,
          cor: cor,
          extra: extra,
          qtd: it.quantidade,
        );
      }
    }

    final maps = agrupado.entries
        .where((e) => e.value.qtd > 0)
        .map(
          (e) => {
            'productId': e.value.productId,
            if (e.value.slug != null && e.value.slug!.trim().isNotEmpty)
              'slug': e.value.slug!.trim(),
            'nome': e.value.nomeOriginal,
            'quantidade': e.value.qtd,
            'tamanho': e.value.tam,
            'cor': e.value.cor,
            if (e.value.extra.isNotEmpty) 'extraValor': e.value.extra,
          },
        )
        .toList();

    debugPrint(
      '[COMBO-DEVOLUCAO] vendaId=$vendaIdLog componentes_count=${maps.length}',
    );

    if (maps.isEmpty &&
        _vendaPareceIncluirKitOuComboReceita(
          itens: itensVenda,
          produtosBox: produtosBox,
          lojaId: lojaId,
        )) {
      debugPrint(
        '[COMBO-DEVOLUCAO] sem_componentes motivo=expansao_filtrou_tudo_ou_receita_indisponivel vendaId=$vendaIdLog',
      );
      throw StateError(
        'Devolução de estoque do kit: não há linhas de componentes para devolver. '
        'Sincronize o app ou verifique se a receita do combo ainda existe no cadastro.',
      );
    }

    return maps;
  }

  /// Logs [COMBO-DEVOLUCAO-ITEM] / [COMBO-DEVOLUCAO-RESULT]; falha se `count==0` sem idempotência prévia.
  static Future<List<EstoqueTransactionResult>> _devolverEstoqueComLogsCombo({
    required String lojaId,
    required String vendaId,
    required List<Map<String, dynamic>> itens,
  }) async {
    for (final m in itens) {
      debugPrint(
        '[COMBO-DEVOLUCAO-ITEM] productId=${m['productId']} slug=${m['slug']} nome=${m['nome']} qtd=${m['quantidade']}',
      );
    }
    final results = await EstoqueTransactionService.devolverEstoqueTransactionBatch(
      lojaId: lojaId,
      itens: itens,
      vendaIdParaIdempotencia: vendaId,
    );
    final ids = results.map((r) => r.produtoId).join(',');
    debugPrint(
      '[COMBO-DEVOLUCAO-RESULT] vendaId=$vendaId count=${results.length} ids=$ids',
    );
    if (results.isEmpty && itens.isNotEmpty) {
      final ja = await EstoqueTransactionService.devolucaoVendaJaAplicada(
        lojaId,
        vendaId,
      );
      if (!ja) {
        throw StateError(
          '[COMBO-DEVOLUCAO-RESULT] count=0 com itens=${itens.length} e sem idempotência local — devolução não aplicada.',
        );
      }
    }
    return results;
  }

  /// Garante e retorna o cliente (cria se não existir), respeitando a loja.
  /// Se [clienteExistente] for fornecido, usa esse cliente (evita matching errado).
  static Cliente _getOrCreateCliente({
    required Box<Cliente> clientesBox,
    required Box<Venda> vendasBox,
    required String clienteNome,
    required String lojaId,
    Cliente? clienteExistente, // Cliente já identificado (ex: da Nova Venda)
  }) {
    if (clienteExistente != null) {
      // ignore: experimental_member_use
      clienteExistente.historico ??= HiveList(vendasBox);
      return clienteExistente;
    }

    final lower = clienteNome.trim().toLowerCase();

    final existente = clientesBox.values.firstWhereOrNull(
      (c) =>
          c.lojaId == lojaId &&
          c.nome.trim().toLowerCase() == lower,
    );

    if (existente != null) {
      // ignore: experimental_member_use
      existente.historico ??= HiveList(vendasBox);
      return existente;
    }

    final novo = Cliente(
      nome: capitalizeWords(clienteNome.trim()),
      telefone: '',
      instagram: '',
      cep: '',
      cidade: '',
      lojaId: lojaId,
      historico: HiveList(vendasBox), // ignore: experimental_member_use
    );
    clientesBox.add(novo);
    return novo;
  }

  // ---------------------------
  // Registrar venda de 1 item
  // ---------------------------

  static Future<Venda> registrarVenda({
    required Box<Produto> produtosBox,
    required Box<Cliente> clientesBox,
    required Box<Venda> vendasBox,
    required String clienteNome,
    required Produto produto,
    int quantidade = 1,
    String tamanho = '',
    String cor = '',
    String formaPagamento = 'dinheiro',
    double dinheiro = 0.0,
    double pix = 0.0,
    double cartao = 0.0,
    String vendedor = 'App',
    String observacao = '',
    double frete = 0.0,
    double descontoPct = 0.0,
    String? lojaId, // 🔹 multi-loja
  }) {
    final item = VendaItem(
      produtoNome: produto.nome,
      quantidade: quantidade,
      precoUnitario: produto.precoFinal,
      tamanho: tamanho,
      cor: cor,
      productId: produto.idFirebase.trim().isNotEmpty ? produto.idFirebase : null,
      custoUnitario: produto.custoUnitarioVariacao(tamanho, cor),
    );

    if (dinheiro == 0 && pix == 0 && cartao == 0) {
      final totalPrevisto =
          (produto.precoFinal * quantidade) * (1 - descontoPct / 100) + frete;
      switch (formaPagamento.toLowerCase()) {
        case 'pix':
          pix = totalPrevisto;
          break;
        case 'cartao':
        case 'cartão':
          cartao = totalPrevisto;
          break;
        default:
          dinheiro = totalPrevisto;
      }
    }

    return registrarVendaMulti(
      produtosBox: produtosBox,
      clientesBox: clientesBox,
      vendasBox: vendasBox,
      clienteNome: clienteNome,
      itens: [item],
      dinheiro: dinheiro,
      pix: pix,
      cartao: cartao,
      vendedor: vendedor,
      observacao: observacao,
      frete: frete,
      descontoPct: descontoPct,
      lojaId: lojaId, // 🔹 repassa
    );
  }

  // ---------------------------
  // Registrar venda multi-itens
  // ---------------------------

  static Future<Venda> registrarVendaMulti({
    required Box<Produto> produtosBox,
    required Box<Cliente> clientesBox,
    required Box<Venda> vendasBox,
    required String clienteNome,
    required List<VendaItem> itens,
    double dinheiro = 0.0,
    double pix = 0.0,
    double cartao = 0.0,
    String vendedor = 'App',
    String observacao = '',
    double frete = 0.0,
    double descontoPct = 0.0,
    String? lojaId, // 🔹 multi-loja
    Cliente? clienteExistente, // 🔹 quando já identificado (evita matching errado)
    String? idFirebaseToReuse, // 🔹 em edição: reutiliza o id da venda antiga (evita duplicata)
    /// Edição: preserva data/hora original da venda (relatórios e fiado). Null = venda nova (usa agora).
    DateTime? dataHoraVenda,
    void Function(String message)? onSyncError, // 🔹 feedback ao usuário quando sync Firestore falhar
    bool isFiado = false, // 🔹 venda fiada: gera conta a receber
    DateTime? dataVencimentoFiado, // 🔹 vencimento da conta (quando isFiado)
    int quantidadeParcelasFiado = 1, // 🔹 número de parcelas do fiado
    int intervaloParcelasDias = 30, // 🔹 intervalo em dias entre parcelas
    /// Edição de venda fiada: reutiliza vencimentos exatos (uma data por parcela), evitando recalendarizar.
    List<DateTime>? parcelasDataVencimentoFiadoPreservadas,
    Map<int, List<Map<String, dynamic>>>? itensComboSelecaoPorIndice, // 🔹 seleção do cliente para combos
    void Function(String? numeroSorte)? onNumeroSorteGerado,
    /// Rollback pós-edição: evita novo número de sorteio ao recriar a venda original.
    bool suprimirCampanhaSorteio = false,
  }) async {
    if (itens.isEmpty) {
      throw Exception('Nenhum item informado.');
    }

    if (lojaId == null || lojaId.trim().isEmpty) {
      throw ArgumentError('lojaId é obrigatório para registrar venda multi-loja');
    }
    final String lojaEfetiva = lojaId.trim();

    // 1) expande combos e encontra produtos (para baixa de estoque)
    final (itensParaEstoque, produtosEncontrados, linhaContaCustoMercadoria) =
        VendaComboEstoqueExpansion.expandirCombos(
      itens: itens,
      produtosBox: produtosBox,
      lojaId: lojaEfetiva,
      itensComboSelecaoPorIndice: itensComboSelecaoPorIndice,
    );

    // 2) cliente
    final cliente = _getOrCreateCliente(
      clientesBox: clientesBox,
      vendasBox: vendasBox,
      clienteNome: clienteNome,
      lojaId: lojaEfetiva,
      clienteExistente: clienteExistente,
    );

    final explicitExp = List<bool>.generate(
      itensParaEstoque.length,
      (i) => itensParaEstoque[i].custoUnitario != null,
    );
    for (var i = 0; i < itensParaEstoque.length; i++) {
      final itemExp = itensParaEstoque[i];
      final pExp = produtosEncontrados[i];
      itemExp.custoUnitario = _resolverCustoItem(pExp, itemExp);
    }
    final explicitOrig = List<bool>.generate(
      itens.length,
      (i) => itens[i].custoUnitario != null,
    );
    final produtosLinhaOriginal = <Produto>[];
    for (var k = 0; k < itens.length; k++) {
      final itemOriginal = itens[k];
      final pLocal = encontrarProdutoNoEstoque(
        produtosBox: produtosBox,
        productId: itemOriginal.productId,
        nome: itemOriginal.produtoNome,
        lojaId: lojaEfetiva,
      );
      produtosLinhaOriginal.add(pLocal ?? Produto.vazio());
      if (pLocal != null) {
        itemOriginal.custoUnitario = _resolverCustoItem(pLocal, itemOriginal);
      }
    }

    // 3) baixa estoque via transação Firestore (OBRIGATÓRIO - sem fallback Hive)
    // Usa itensParaEstoque (combos já expandidos) para dar baixa em cada produto individual
    // Exige tamanho/cor quando o produto tem estoque por variação para baixa correta no Firestore
    VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
      itensParaEstoque: itensParaEstoque,
      produtosEncontrados: produtosEncontrados,
    );

    final txItems = VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
      itensParaEstoque: itensParaEstoque,
      produtosEncontrados: produtosEncontrados,
    );

    final txResults = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
      lojaId: lojaEfetiva,
      itens: txItems,
    );

    await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(lojaEfetiva, txResults);

    for (final result in txResults) {
      await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: produtosBox,
        lojaId: lojaEfetiva,
        result: result,
      );
    }

    final txResultsComboCap =
        await ComboKitStockService.aplicarTetoEstoqueComboAposBaixa(
      lojaId: lojaEfetiva,
      produtosBox: produtosBox,
      produtoIdsDebitadosNaVenda:
          ComboKitStockService.produtoIdsDeResultadosBaixa(txResults),
    );

    await CatalogoWebAposEstoqueService.sincronizarAposResultadosTransacao(
      lojaId: lojaEfetiva,
      produtosBox: produtosBox,
      resultadosPrincipais: txResults,
      resultadosComboExtra: txResultsComboCap,
    );

    // 3.1) Histórico de movimentação – registra saída por item (não bloqueia)
    for (final result in txResults) {
      MovimentacaoEstoqueService.registrar(
        lojaId: lojaEfetiva,
        produtoId: result.produtoId,
        produtoNome: result.produtoNome,
        tipo: 'saida',
        quantidade: result.quantidadeDebitada,
        motivo: 'Venda',
        usuario: vendedor,
      ).catchError((_) {});
    }
    for (final result in txResultsComboCap) {
      MovimentacaoEstoqueService.registrar(
        lojaId: lojaEfetiva,
        produtoId: result.produtoId,
        produtoNome: result.produtoNome,
        tipo: 'saida',
        quantidade: result.quantidadeDebitada,
        motivo: 'Venda (ajuste kit combo)',
        usuario: vendedor,
      ).catchError((_) {});
    }

    // 4) subtotal / total
    final subtotal = itens.fold<double>(
      0.0,
      (acc, it) => acc + (it.precoUnitario * it.quantidade),
    );
    final total = subtotal * (1 - descontoPct / 100) + frete;

    // 5) custo de mercadoria (custo real) e taxa legado APK — separados; combo = só componentes
    final custoProdutos = VendaCustoMercadoria.somarCustoReal(
      itens: itensParaEstoque,
      produtos: produtosEncontrados,
      linhaContaCustoMercadoria: linhaContaCustoMercadoria,
    );
    VendaCustoMercadoria.aplicarRastreioOrigemAposSomarCustoReal(
      itens: itensParaEstoque,
      produtos: produtosEncontrados,
      linhaContaCustoMercadoria: linhaContaCustoMercadoria,
      tinhaCustoUnitarioExplicitoAntesDoResolver: explicitExp,
    );
    VendaCustoMercadoria.aplicarRastreioOrigemAposSomarCustoReal(
      itens: itens,
      produtos: produtosLinhaOriginal,
      linhaContaCustoMercadoria: List<bool>.filled(itens.length, true),
      tinhaCustoUnitarioExplicitoAntesDoResolver: explicitOrig,
    );
    final origensAtivas = <String?>[];
    for (var i = 0; i < itensParaEstoque.length; i++) {
      if (linhaContaCustoMercadoria[i]) {
        origensAtivas.add(itensParaEstoque[i].origemCustoItem);
      }
    }
    final origemCustoVenda = VendaCustoMercadoria.agregarOrigemCustoVenda(
      custoProdutos: custoProdutos,
      origensLinhasAtivas: origensAtivas,
    );
    final totalUnidades = VendaCustoMercadoria.unidadesMercadoria(
      itens: itensParaEstoque,
      linhaContaCustoMercadoria: linhaContaCustoMercadoria,
    );
    final taxas = VendaCustoMercadoria.taxasLegadoVendaApk(
      custoMercadoria: custoProdutos,
      unidadesMercadoria: totalUnidades,
    );

    // 6) se nenhum pagamento foi informado e não for fiado, joga tudo em dinheiro
    if (!isFiado && dinheiro == 0 && pix == 0 && cartao == 0) {
      dinheiro = total;
    }
    // Fiado: não compõe dinheiro/pix/cartão na venda até o recebimento em contas a receber.
    if (isFiado) {
      dinheiro = 0;
      pix = 0;
      cartao = 0;
    }

    // 7) textos
    final linhas = itens.map((it) {
      final variacoes = <String>[];
      if (it.tamanho.isNotEmpty) variacoes.add('Tam: ${it.tamanho}');
      if (it.cor.isNotEmpty) variacoes.add('Cor: ${it.cor}');
      if (it.variacaoExtraResumo.isNotEmpty) {
        variacoes.add(it.variacaoExtraResumo);
      }
      final variacoesStr = variacoes.isNotEmpty ? ' (${variacoes.join(', ')})' : '';
      return "${it.quantidade} x ${it.produtoNome}$variacoesStr - R\$ ${_fmt2(it.precoUnitario)}";
    }).join('\n');

    final produtosDescricao = "$linhas\n"
        "Frete: R\$ ${_fmt2(frete)}\n"
        "Desconto: ${descontoPct.toStringAsFixed(0)}%\n"
        "Total: R\$ ${_fmt2(total)}";

    final vencStr = dataVencimentoFiado != null
        ? 'Vencimento: ${dataVencimentoFiado.day.toString().padLeft(2, '0')}/${dataVencimentoFiado.month.toString().padLeft(2, '0')}/${dataVencimentoFiado.year}'
        : '';
    final formasPagamentoTexto = isFiado
        ? 'Fiado - R\$ ${_fmt2(total)}. $vencStr'
        : [
            if (dinheiro > 0) "Pagamento Dinheiro: R\$ ${_fmt2(dinheiro)}",
            if (pix > 0) "Pagamento Pix: R\$ ${_fmt2(pix)}",
            if (cartao > 0) "Pagamento Cartão: R\$ ${_fmt2(cartao)}",
          ].join('\n');

    // 8) cria venda (com todos os itens + clienteId estável)
    final dataRegistro = dataHoraVenda ?? DateTime.now();
    final venda = Venda(
      clienteNome: cliente.nome,
      produtosDescricao: "$produtosDescricao\n$formasPagamentoTexto",
      quantidade: itens.length,
      preco: subtotal,
      total: total,
      formasPagamento: formasPagamentoTexto,
      data: dataRegistro,
      tamanho: '',
      vendedor: vendedor,
      frete: frete,
      desconto: descontoPct,
      observacao: observacao.trim(),
      itens: itens,
      pagamentoDinheiro: dinheiro,
      pagamentoPix: pix,
      pagamentoCartao: cartao,
      taxas: taxas,
      custoProdutos: custoProdutos,
      descontoValor: subtotal * (descontoPct / 100),
      lojaId: lojaEfetiva,
      clienteId: cliente.key?.toString() ?? cliente.idFirebase,
      origemCusto: origemCustoVenda,
      itensComboSelecaoJson:
          VendaComboEstoqueExpansion.serializeItensComboSelecaoPorIndice(
        itensComboSelecaoPorIndice,
      ),
    );

    // Em edição: reutiliza idFirebase da venda antiga (evita duplicata no Firestore)
    if (idFirebaseToReuse != null && idFirebaseToReuse.isNotEmpty) {
      venda.idFirebase = idFirebaseToReuse;
    }

    debugPrint('💾 [VENDAS-SERVICE] Salvando venda - Dinheiro: R\$ ${_fmt2(dinheiro)}, Pix: R\$ ${_fmt2(pix)}, Cartão: R\$ ${_fmt2(cartao)}, Total: R\$ ${_fmt2(total)}');
    debugPrint('📤 [SYNC-DEBUG] VendasService.salvarVenda → lojaId=$lojaEfetiva | cliente=${cliente.nome} | total=R\$ ${_fmt2(total)}');

    await vendasBox.add(venda);

    final vIdSnapshot = (venda.idFirebase ?? '').trim().isNotEmpty
        ? venda.idFirebase!.trim()
        : 'hive_${venda.key}';
    final snapRaw = venda.itensComboSelecaoJson;
    final snapKeys =
        VendaComboEstoqueExpansion.parseItensComboSelecaoPorIndiceJson(snapRaw)
                ?.keys
                .toList() ??
            <int>[];
    final snapVazio = snapRaw == null || snapRaw.trim().isEmpty;
    debugPrint(
      '[COMBO-SNAPSHOT-SAVE] vendaId=$vIdSnapshot json_vazio=$snapVazio keys=$snapKeys',
    );

    // 8.1) se fiado, criar conta a receber (falha = rollback da venda atual)
    final contasFiadoCriadas = <ContaReceber>[];
    if (isFiado && dataVencimentoFiado != null) {
      try {
        final crBoxName = HiveBoxNames.contasReceber(lojaEfetiva);
        final crBox = Hive.isBoxOpen(crBoxName) ? Hive.box<ContaReceber>(crBoxName) : await Hive.openBox<ContaReceber>(crBoxName);
        final qtdParcelas = quantidadeParcelasFiado.clamp(1, 48);
        final intervalo = intervaloParcelasDias.clamp(1, 120);
        final valoresParcelas = _parcelarValores(total, qtdParcelas);
        final preservadas = parcelasDataVencimentoFiadoPreservadas;
        final usarPreservadas =
            preservadas != null && preservadas.length == qtdParcelas;
        for (var i = 0; i < qtdParcelas; i++) {
          final DateTime venc;
          if (usarPreservadas) {
            final d = preservadas[i];
            venc = DateTime(d.year, d.month, d.day);
          } else {
            venc = dataVencimentoFiado.add(Duration(days: i * intervalo));
          }
          final conta = ContaReceber(
            lojaId: lojaEfetiva,
            clienteNome: cliente.nome,
            valor: valoresParcelas[i],
            dataVencimento: venc,
            dataVenda: venda.data,
            vendaKey: venda.key is int ? venda.key as int : 0,
            observacao: qtdParcelas > 1
                ? 'Parcela ${i + 1}/$qtdParcelas${observacao.trim().isNotEmpty ? ' - ${observacao.trim()}' : ''}'
                : (observacao.trim().isEmpty ? 'Venda fiada' : observacao.trim()),
            parcelaNumero: i + 1,
            parcelaTotal: qtdParcelas,
          );
          await crBox.add(conta);
          contasFiadoCriadas.add(conta);
        }
      } catch (e) {
        debugPrint('⚠️ [VENDAS-SERVICE] Erro ao criar conta a receber (type=${e.runtimeType})');
        onSyncError?.call('Erro ao criar conta a receber. A venda fiada não foi registrada. Tente novamente.');
        await vendasBox.delete(venda.key);
        rethrow;
      }
    }

    // 9) histórico do cliente
    // ignore: experimental_member_use
    cliente.historico ??= HiveList(vendasBox);
    cliente.historico!.add(venda);
    await cliente.save();

    // 9.1) sincroniza cliente com Firestore
    try {
      await ClientesFirestoreService.syncCliente(cliente, lojaId: lojaEfetiva);
    } catch (e) {
      debugPrint('⚠️ Erro ao sincronizar cliente com Firestore (type=${e.runtimeType})');
      onSyncError?.call('Cliente não sincronizado. Verifique a conexão.');
    }

    // 10) sincroniza venda com Firestore
    try {
      final ok = await VendasFirestoreService.syncVenda(venda, lojaId: lojaEfetiva);
      if (!ok) {
        debugPrint('⚠️ [VENDAS-SERVICE] Venda não sincronizada com Firestore (lojaId=$lojaEfetiva, key=${venda.key})');
        onSyncError?.call('Venda salva localmente, mas não sincronizou na nuvem. Verifique a conexão ou tente sincronizar novamente.');
      }
    } catch (e) {
      debugPrint('⚠️ Erro inesperado ao sincronizar venda com Firestore (type=${e.runtimeType})');
      onSyncError?.call('Venda salva localmente, mas não sincronizou na nuvem. Verifique a conexão ou tente sincronizar novamente.');
    }

    if (contasFiadoCriadas.isNotEmpty) {
      try {
        await ContasReceberFirestoreService.upsertContasDeVendaFiada(
          contas: contasFiadoCriadas,
          lojaId: lojaEfetiva,
          vendaFirebaseId: (venda.idFirebase ?? '').trim().isEmpty
              ? null
              : venda.idFirebase!.trim(),
        );
      } catch (e) {
        debugPrint(
          '⚠️ [VENDAS-SERVICE] Espelho Firestore contas a receber (fiado) falhou (type=${e.runtimeType})',
        );
      }
    }

    // 12) 🎯 Registra participação em campanhas de sorteio (CENTRALIZADO)
    if (!suprimirCampanhaSorteio) {
      try {
        final resultado = await CampaignEngineService.onVendaConcluida(
          lojaId: lojaEfetiva,
          venda: venda,
          vendaId: venda.key?.toString(),
          clienteNome: cliente.nome,
          clienteId: cliente.key?.toString(),
          telefone: cliente.telefone, // 🔥 Adicionado para WhatsApp
          email: cliente.email,       // 🔥 Adicionado para Email
          valorTotal: total,
          origem: 'manual',
          nomeLoja: lojaEfetiva,
        );

        if (resultado.sucesso) {
          debugPrint('🎫 [VENDA-MANUAL] Número da sorte gerado: ${resultado.numero}');
          onNumeroSorteGerado?.call(resultado.numero);
        } else if (resultado.erro != null) {
          debugPrint('ℹ️ [VENDA-MANUAL] Campanha: ${resultado.erro}');
        }
      } catch (e) {
        debugPrint('⚠️ [VENDA-MANUAL] Campanha/sorteio: ${e.runtimeType}');
      }
    }

    return venda;
  }

  // ---------------------------
  // Desfazer venda
  // ---------------------------

  static Future<void> desfazerVenda({
    required Box<Produto> produtosBox,
    required Box<Cliente> clientesBox,
    required Box<Venda> vendasBox,
    required Venda venda,
  }) async {
    // Evitar fallback 'default': usar loja da venda ou do nome da box (vendas_lojaId).
    String lojaId = (venda.lojaId ?? '').trim().isNotEmpty
        ? venda.lojaId!.trim()
        : (vendasBox.name.startsWith('vendas_') ? vendasBox.name.substring(7) : '');
    if (lojaId.isEmpty) {
      return; // Não desfazer sem loja definida (evita operar na loja errada).
    }

    // devolve estoque (transacional, idempotente)
    final vendaId = (venda.idFirebase ?? '').trim().isNotEmpty
        ? venda.idFirebase!.trim()
        : 'hive_${venda.key}';
    var devolucaoResults = <EstoqueTransactionResult>[];
    if (venda.itens != null && venda.itens!.isNotEmpty) {
      final itens = _montarItensFirestoreDevolucaoAgrupados(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
        vendaIdLog: vendaId,
      );
      if (itens.isNotEmpty) {
        try {
          final results = await _devolverEstoqueComLogsCombo(
            lojaId: lojaId,
            vendaId: vendaId,
            itens: itens,
          );
          devolucaoResults = results;
          for (final r in results) {
            await EstoqueTransactionService.atualizarHiveAposTransacao(
              produtosBox: produtosBox,
              lojaId: lojaId,
              result: r,
            );
          }
          if (results.isNotEmpty) {
            debugPrint('✅ Estoque devolvido (transacional): ${results.length} itens');
          }
        } catch (e, st) {
          debugPrint(
            '[DESFAZER-VENDA] Falha na devolução de estoque — venda NÃO removida (Firestore/Hive intactos). Erro: $e',
          );
          Error.throwWithStackTrace(e, st);
        }
      }
    } else {
      // 🔹 fallback para vendas antigas sem lista de itens
      final itensFallback = <Map<String, dynamic>>[];
      final linhas = venda.produtosDescricao.split('\n');
      for (var linha in linhas) {
        try {
          if (!linha.contains(' x ')) continue;
          final partes = linha.split(' x ');
          if (partes.length < 2) continue;
          final qtd = int.tryParse(partes[0].trim()) ?? 1;
          if (qtd <= 0) continue;
          final restante = partes[1].split(' - R\$');
          var nome = restante.isNotEmpty ? restante.first.trim() : '';
          if (nome.isEmpty) continue;
          if (nome.contains(' - ')) nome = nome.split(' - ').first.trim();
          if (nome.isEmpty) continue;
          itensFallback.add({'nome': nome, 'quantidade': qtd});
        } catch (_) {}
      }
      if (itensFallback.isNotEmpty) {
        try {
          final results = await EstoqueTransactionService.devolverEstoqueTransactionBatch(
            lojaId: lojaId,
            itens: itensFallback,
            vendaIdParaIdempotencia: vendaId,
          );
          devolucaoResults = results;
          for (final r in results) {
            await EstoqueTransactionService.atualizarHiveAposTransacao(
              produtosBox: produtosBox,
              lojaId: lojaId,
              result: r,
            );
          }
          if (results.isNotEmpty) debugPrint('✅ Estoque devolvido (fallback): ${results.length} itens');
        } catch (e, st) {
          debugPrint(
            '[DESFAZER-VENDA] Falha na devolução (fallback vendas antigas) — venda NÃO removida. Erro: $e',
          );
          Error.throwWithStackTrace(e, st);
        }
      }
    }

    var pisoResults = <EstoqueTransactionResult>[];
    try {
      pisoResults =
          await ComboKitStockService.aplicarPisoEstoqueComboAposDevolucao(
        lojaId: lojaId,
        produtosBox: produtosBox,
      );
      for (final r in pisoResults) {
        final q = r.quantidadeDebitada.abs();
        if (q <= 0) continue;
        MovimentacaoEstoqueService.registrar(
          lojaId: lojaId,
          produtoId: r.produtoId,
          produtoNome: r.produtoNome,
          tipo: 'entrada',
          quantidade: q,
          motivo: 'Devolução (ajuste kit combo)',
          usuario: 'App',
          vendaId: vendaId,
        ).catchError((_) {});
      }
    } catch (e) {
      debugPrint(
        '⚠️ [COMBO_PISO] Falha ao sincronizar estoque do combo após devolução: $e',
      );
    }

    await CatalogoWebAposEstoqueService.sincronizarAposResultadosTransacao(
      lojaId: lojaId,
      produtosBox: produtosBox,
      resultadosPrincipais: devolucaoResults,
      resultadosComboExtra: pisoResults,
    );

    final vendaHiveKey = venda.key is int ? venda.key as int : 0;
    if (vendaHiveKey > 0) {
      await removerContasReceberVinculadasAVenda(
        lojaId: lojaId,
        vendaKey: vendaHiveKey,
        vendaFirebaseId: (venda.idFirebase ?? '').trim().isEmpty
            ? null
            : venda.idFirebase!.trim(),
      );
    }

    // remove do histórico (apenas se cliente existir na box - evita erro em vendas catálogo sem cliente)
    final Cliente? cliente = clientesBox.values.firstWhereOrNull(
      (c) =>
          c.lojaId == venda.lojaId &&
          c.nome == venda.clienteNome,
    );

    if (cliente != null && cliente.historico != null) {
      cliente.historico!.removeWhere(
        (h) => identical(h, venda) || h.key == venda.key,
      );
      await cliente.save();

      // ✅ SINCRONIZAR cliente atualizado com Firestore
      try {
        await ClientesFirestoreService.syncCliente(cliente, lojaId: lojaId);
      } catch (e) {
        debugPrint('⚠️ Erro ao sincronizar cliente com Firestore (type=${e.runtimeType})');
      }
    }

    // ✅ DELETAR do Firestore (estoque_vendas) para não voltar na sync
    try {
      if (venda.idFirebase != null && venda.idFirebase!.isNotEmpty) {
        await VendasFirestoreService.deleteVenda(venda.idFirebase!, lojaId: lojaId);
        debugPrint('✅ Venda deletada do Firestore: ${venda.idFirebase}');
      } else {
        debugPrint('⚠️ Venda sem idFirebase, não pode deletar do Firestore');
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao deletar venda do Firestore (type=${e.runtimeType})');
    }

    // Deletar do Hive (local)
    await venda.delete();
  }

  /// Devolve estoque ao remover venda (soft delete imediato ou exclusão permanente).
  /// Idempotente por vendaId em [EstoqueTransactionService.devolverEstoqueTransactionBatch].
  static Future<void> devolverEstoqueParaVendaRemovida({
    required Venda venda,
    required Box<Produto> produtosBox,
    required String lojaId,
  }) async {
    final vendaId = (venda.idFirebase ?? '').trim().isNotEmpty
        ? venda.idFirebase!.trim()
        : 'hive_${venda.key}';
    debugPrint('[VENDA_DELETE] devolucao_estoque_inicio vendaId=$vendaId');

    var devolucaoResultsExclusao = <EstoqueTransactionResult>[];
    if (venda.itens != null && venda.itens!.isNotEmpty) {
      final itens = _montarItensFirestoreDevolucaoAgrupados(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
        vendaIdLog: vendaId,
      );
      if (itens.isNotEmpty) {
        try {
          final results = await _devolverEstoqueComLogsCombo(
            lojaId: lojaId,
            vendaId: vendaId,
            itens: itens,
          );
          devolucaoResultsExclusao = results;
          for (final r in results) {
            await EstoqueTransactionService.atualizarHiveAposTransacao(
              produtosBox: produtosBox,
              lojaId: lojaId,
              result: r,
            );
          }
        } catch (e, st) {
          debugPrint(
            '[VENDA_DELETE] devolucao_estoque_falhou vendaId=$vendaId erro=$e',
          );
          debugPrint(
            '[VENDA_DELETE] exclusao_abortada_por_estoque (lote itens)',
          );
          Error.throwWithStackTrace(e, st);
        }
      }
    } else {
      final itensFallback = <Map<String, dynamic>>[];
      final linhas = venda.produtosDescricao.split('\n');
      for (var linha in linhas) {
        if (!linha.contains(' x ')) continue;
        final partes = linha.split(' x ');
        if (partes.length < 2) continue;
        final qtd = int.tryParse(partes[0].trim()) ?? 1;
        var nome = partes[1].split(' - R\$').first.trim();
        if (nome.contains(' - ')) nome = nome.split(' - ').first.trim();
        if (nome.isEmpty) continue;
        itensFallback.add({'nome': nome, 'quantidade': qtd});
      }
      if (itensFallback.isNotEmpty) {
        try {
          final results = await EstoqueTransactionService.devolverEstoqueTransactionBatch(
            lojaId: lojaId,
            itens: itensFallback,
            vendaIdParaIdempotencia: vendaId,
          );
          devolucaoResultsExclusao = results;
          for (final r in results) {
            await EstoqueTransactionService.atualizarHiveAposTransacao(
              produtosBox: produtosBox,
              lojaId: lojaId,
              result: r,
            );
          }
        } catch (e, st) {
          debugPrint(
            '[VENDA_DELETE] devolucao_estoque_falhou vendaId=$vendaId erro=$e',
          );
          debugPrint(
            '[VENDA_DELETE] exclusao_abortada_por_estoque (fallback texto)',
          );
          Error.throwWithStackTrace(e, st);
        }
      }
    }

    var pisoResultsExclusao = <EstoqueTransactionResult>[];
    try {
      pisoResultsExclusao =
          await ComboKitStockService.aplicarPisoEstoqueComboAposDevolucao(
        lojaId: lojaId,
        produtosBox: produtosBox,
      );
      for (final r in pisoResultsExclusao) {
        final q = r.quantidadeDebitada.abs();
        if (q <= 0) continue;
        await MovimentacaoEstoqueService.registrar(
          lojaId: lojaId,
          produtoId: r.produtoId,
          produtoNome: r.produtoNome,
          tipo: 'entrada',
          quantidade: q,
          motivo: 'Devolução (ajuste kit combo)',
          usuario: 'App',
          vendaId: vendaId,
        );
      }
    } catch (e, st) {
      debugPrint(
        '[VENDA_DELETE] devolucao_estoque_falhou vendaId=$vendaId (piso combo / mov.) erro=$e',
      );
      debugPrint('[VENDA_DELETE] exclusao_abortada_por_estoque');
      Error.throwWithStackTrace(e, st);
    }

    try {
      await CatalogoWebAposEstoqueService.sincronizarAposResultadosTransacao(
        lojaId: lojaId,
        produtosBox: produtosBox,
        resultadosPrincipais: devolucaoResultsExclusao,
        resultadosComboExtra: pisoResultsExclusao,
      );
    } catch (e, st) {
      debugPrint(
        '[VENDA_DELETE] catalogo_pos_estoque_falhou vendaId=$vendaId erro=$e — exclusao_abortada',
      );
      Error.throwWithStackTrace(e, st);
    }

    debugPrint('[VENDA_DELETE] devolucao_estoque_sucesso vendaId=$vendaId');
  }

  /// Reaplica baixa de estoque após desfazer exclusão (devolução já tinha sido feita no soft delete).
  static Future<void> reaplicarBaixaEstoquePosUndoExclusaoVenda({
    required Venda venda,
    required Box<Produto> produtosBox,
    required String lojaId,
  }) async {
    final lid = lojaId.trim();
    if (lid.isEmpty) return;
    if (venda.itens == null || venda.itens!.isEmpty) {
      debugPrint('[VENDA_UNDO] Sem itens estruturados; não reaplica baixa automática');
      return;
    }
    final selecaoUndo =
        VendaComboEstoqueExpansion.parseItensComboSelecaoPorIndiceJson(
      venda.itensComboSelecaoJson,
    );
    if (selecaoUndo != null) {
      debugPrint(
        '[COMBO-DEVOLUCAO] vendaId=${(venda.idFirebase ?? '').trim().isNotEmpty ? venda.idFirebase! : 'hive_${venda.key}'} undo_baixa fonte=itensComboSelecaoJson',
      );
    }
    final (itensParaBaixa, produtosEnc, linhaFlags) =
        VendaComboEstoqueExpansion.expandirCombos(
      itens: venda.itens!,
      produtosBox: produtosBox,
      lojaId: lid,
      itensComboSelecaoPorIndice: selecaoUndo,
    );
    final itensS = <VendaItem>[];
    final prodS = <Produto>[];
    for (var i = 0; i < itensParaBaixa.length; i++) {
      if (i >= linhaFlags.length || i >= produtosEnc.length) break;
      if (!linhaFlags[i]) continue;
      if (produtosEnc[i].ehCombo) continue;
      itensS.add(itensParaBaixa[i]);
      prodS.add(produtosEnc[i]);
    }
    VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
      itensParaEstoque: itensS,
      produtosEncontrados: prodS,
    );
    final txItems = VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
      itensParaEstoque: itensS,
      produtosEncontrados: prodS,
    );
    if (txItems.isEmpty) return;

    final txResults = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
      lojaId: lid,
      itens: txItems,
    );
    await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(lid, txResults);
    for (final result in txResults) {
      await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: produtosBox,
        lojaId: lid,
        result: result,
      );
    }
    final txCap = await ComboKitStockService.aplicarTetoEstoqueComboAposBaixa(
      lojaId: lid,
      produtosBox: produtosBox,
      produtoIdsDebitadosNaVenda:
          ComboKitStockService.produtoIdsDeResultadosBaixa(txResults),
    );
    await CatalogoWebAposEstoqueService.sincronizarAposResultadosTransacao(
      lojaId: lid,
      produtosBox: produtosBox,
      resultadosPrincipais: txResults,
      resultadosComboExtra: txCap,
    );
  }

  /// Executa devolução de estoque e exclusão do Firestore.
  /// Usado pelo SoftDeleteService quando a exclusão se torna definitiva após 5 s.
  /// Não altera vendasBox nem clientesBox (venda já está na lixeira).
  ///
  /// Se a devolução de estoque (incl. ajuste piso combo) falhar, propaga erro:
  /// a exclusão definitiva deve ser abortada pelo chamador — não apagar Firestore
  /// com estoque inconsistente.
  static Future<void> executarExclusaoPermanente({
    required Venda venda,
    required Box<Produto> produtosBox,
    required String lojaId,
  }) async {
    final vendaId = (venda.idFirebase ?? '').trim().isNotEmpty
        ? venda.idFirebase!.trim()
        : 'hive_${venda.key}';
    if (!await EstoqueTransactionService.devolucaoVendaJaAplicada(lojaId, vendaId)) {
      await devolverEstoqueParaVendaRemovida(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
      );
    } else {
      debugPrint(
        '[VENDA_DELETE] devolucao_ja_aplicada_skip_permanente vendaId=$vendaId',
      );
    }

    if (venda.idFirebase != null && venda.idFirebase!.isNotEmpty) {
      await VendasFirestoreService.deleteVenda(venda.idFirebase!, lojaId: lojaId);
    }
  }
}
