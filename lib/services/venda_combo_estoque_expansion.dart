// Expansão de combo e montagem da transação de estoque — mesma regra que
// [VendasService.registrarVendaMulti] (nova venda / PDV). Reutilizado no pós-pagamento do pré-pedido.

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/produto_variacao_extra.dart';
import '../core/strict_product_resolution.dart';
import '../models/produto.dart';
import '../models/venda_item.dart';

/// Expansão de linhas de venda com combo e montagem dos maps para [EstoqueTransactionService.baixarEstoqueTransactionBatch].
class VendaComboEstoqueExpansion {
  VendaComboEstoqueExpansion._();

  /// Converte itens do carrinho / pré-pedido (mapas) para [VendaItem] + seleção de combo por índice,
  /// no mesmo formato da nova venda (`itensComboSelecaoPorIndice` antes de cada `add`).
  static (List<VendaItem> vendaItens, Map<int, List<Map<String, dynamic>>>? comboPorIndice)
      carrinhoMapsParaVendaItensComComboSelecao(List<Map<String, dynamic>> items) {
    final vendaItens = <VendaItem>[];
    final comboPorIndice = <int, List<Map<String, dynamic>>>{};

    for (final raw in items) {
      final nome = (raw['nome'] ?? raw['name'] ?? '').toString().trim();
      final pid = (raw['productId'] ?? raw['id'] ?? raw['produtosId'] ?? '').toString().trim();
      if (nome.isEmpty && pid.isEmpty) continue;

      final qtd = (raw['quantidade'] as num?)?.toInt() ?? (raw['qty'] as num?)?.toInt() ?? 1;
      if (qtd <= 0) continue;

      final sel = raw['itensComboComSelecao'];
      if (sel is List && sel.isNotEmpty) {
        final listaSegura = <Map<String, dynamic>>[];
        for (final e in sel) {
          if (e is Map) {
            listaSegura.add(
              Map<String, dynamic>.from(
                e.map((k, v) => MapEntry(k.toString(), v)),
              ),
            );
          }
        }
        if (listaSegura.isNotEmpty) {
          comboPorIndice[vendaItens.length] = listaSegura;
        }
      }

      vendaItens.add(
        VendaItem(
          produtoNome: nome,
          quantidade: qtd,
          precoUnitario: (raw['preco'] as num?)?.toDouble() ?? (raw['price'] as num?)?.toDouble() ?? 0.0,
          tamanho: (raw['tamanho'] ?? raw['size'] ?? '').toString(),
          cor: (raw['cor'] ?? raw['color'] ?? '').toString(),
          lojaId: '',
          productId: pid.isNotEmpty ? pid : null,
          variacaoExtraResumo: (raw['variacaoExtraResumo'] ?? '').toString(),
          extraValor: (raw['extraValor'] ?? '').toString(),
        ),
      );
    }

    return (vendaItens, comboPorIndice.isEmpty ? null : comboPorIndice);
  }

  /// Expande itens de combo em linhas para baixa de estoque (kit + componentes).
  /// Mesma lógica que a antiga [VendasService._expandirCombos].
  ///
  /// [linhaContaCustoMercadoria] — por linha expandida: `false` no cabeçalho do kit quando há
  /// filhos (custo só dos componentes); `true` nos componentes e em produto simples / combo sem receita.
  static (List<VendaItem>, List<Produto>, List<bool>) expandirCombos({
    required List<VendaItem> itens,
    required Box<Produto> produtosBox,
    required String lojaId,
    Map<int, List<Map<String, dynamic>>>? itensComboSelecaoPorIndice,
  }) {
    final itensExpandidos = <VendaItem>[];
    final produtosExpandidos = <Produto>[];
    final linhaContaCustoMercadoria = <bool>[];

    for (var idx = 0; idx < itens.length; idx++) {
      final it = itens[idx];
      Produto? p;
      final pid = (it.productId ?? '').trim();
      if (pid.isNotEmpty) {
        p = produtosBox.values.firstWhereOrNull(
          (prod) => prod.lojaId == lojaId && prod.idFirebase.trim() == pid,
        );
        if (p != null) {
          debugPrint('[VENDA_ITEM_ID] [DUPLICAR_VENDA] Produto principal por productId | lojaId=$lojaId | productId=$pid');
        }
      }
      if (p == null) {
        p = produtosBox.values.firstWhereOrNull(
          (prod) =>
              prod.lojaId == lojaId &&
              prod.nome.trim().toLowerCase() == it.produtoNome.trim().toLowerCase(),
        );
        if (p != null) {
          debugPrint('[VENDA_ITEM_FALLBACK] [COMBO_MATCH] Produto principal por nome | lojaId=$lojaId | nome=${it.produtoNome}');
          reportProductResolvedByName(
            lojaId: lojaId,
            fluxo: '_expandirCombos_principal',
            nome: it.produtoNome,
            slug: null,
            productIdRecebido: pid.isEmpty ? null : pid,
          );
        }
      }
      if (p == null) {
        throw Exception('Produto não encontrado no estoque: ${it.produtoNome}');
      }
      it.custoUnitario = p.custoUnitarioVariacao(
        it.tamanho,
        it.cor,
        it.extraValor,
      );

      final selecaoNoMapa = itensComboSelecaoPorIndice?[idx];
      final listaCombo = selecaoNoMapa ?? p.itensCombo;
      if (p.ehCombo && listaCombo != null && listaCombo.isNotEmpty) {
        final semSelecaoPersistida =
            selecaoNoMapa == null || selecaoNoMapa.isEmpty;
        if (semSelecaoPersistida) {
          debugPrint(
            '[COMBO_ESTOQUE_FALLBACK] Receita do cadastro (sem itensComboComSelecao válido no índice) | '
            'lojaId=$lojaId | idx=$idx | combo="${p.nome}"',
          );
        }
        itensExpandidos.add(it);
        produtosExpandidos.add(p);
        linhaContaCustoMercadoria.add(false);

        for (final comboItem in listaCombo) {
          final idComp = (comboItem['id'] ?? comboItem['productId'] ?? '').toString().trim();
          final slugComp = (comboItem['slug'] ?? '').toString().trim();
          final nomeComp = (comboItem['nome'] ?? '').toString();
          final qtdComp = ((comboItem['quantidade']) is num
                  ? (comboItem['quantidade'] as num).toInt()
                  : int.tryParse('${comboItem['quantidade']}') ?? 1)
              .clamp(1, 9999);
          final tam = (comboItem['tamanho'] ?? '').toString();
          final cor = (comboItem['cor'] ?? '').toString();
          final qtdTotal = it.quantidade * qtdComp;
          if (nomeComp.isEmpty || qtdTotal <= 0) continue;

          Produto? pComp;
          if (idComp.isNotEmpty) {
            pComp = produtosBox.values.firstWhereOrNull(
              (prod) => prod.lojaId == lojaId && prod.idFirebase.trim() == idComp,
            );
            if (pComp != null) {
              debugPrint('[COMBO_ID] [COMBO_ITEM] Item combo por productId | lojaId=$lojaId | productId=$idComp | nome=${pComp.nome}');
            }
          }
          if (pComp == null && slugComp.isNotEmpty) {
            pComp = produtosBox.values.firstWhereOrNull(
              (prod) => prod.lojaId == lojaId && prod.slug.trim() == slugComp,
            );
            if (pComp != null) {
              debugPrint('[COMBO_FALLBACK] [COMBO_ITEM] Item combo por slug | lojaId=$lojaId | slug=$slugComp | nome=$nomeComp');
            }
          }
          if (pComp == null && nomeComp.isNotEmpty) {
            pComp = produtosBox.values.firstWhereOrNull(
              (prod) =>
                  prod.lojaId == lojaId &&
                  prod.nome.trim().toLowerCase() == nomeComp.trim().toLowerCase(),
            );
            if (pComp != null) {
              debugPrint('[COMBO_FALLBACK] [COMBO_ITEM] Item combo por nome | lojaId=$lojaId | nome=$nomeComp');
              reportProductResolvedByName(
                lojaId: lojaId,
                fluxo: '_expandirCombos_item',
                nome: nomeComp,
                slug: slugComp.isEmpty ? null : slugComp,
                productIdRecebido: idComp.isEmpty ? null : idComp,
              );
            }
          }
          if (pComp == null) {
            throw Exception('Produto do combo não encontrado: $nomeComp (productId=$idComp, slug=$slugComp)');
          }
          final extraTrim = (comboItem['extraValor'] ?? '').toString().trim();
          final corKey = cor.trim().isEmpty ? 'sem-cor' : cor.trim();
          final tamKey = tam.trim().isEmpty ? 'sem-tamanho' : tam.trim();
          final tipoExtra = ProdutoVariacaoExtra.tipoParaCelula(
            pComp.variacoesExtraTipo,
            tamKey,
            corKey,
            extraTrim,
          );
          final resumoExtra = extraTrim.isNotEmpty
              ? ProdutoVariacaoExtra.textoResumoExtra(
                  extraTipo: tipoExtra,
                  extraValor: extraTrim,
                )
              : '';

          itensExpandidos.add(
            VendaItem(
              produtoNome: pComp.nome,
              quantidade: qtdTotal,
              precoUnitario: 0,
              tamanho: tam,
              cor: cor,
              productId: pComp.idFirebase.trim().isNotEmpty ? pComp.idFirebase : null,
              variacaoExtraResumo: resumoExtra,
              extraValor: extraTrim,
              custoUnitario:
                  pComp.custoUnitarioVariacao(tam, cor, extraTrim),
            ),
          );
          produtosExpandidos.add(pComp);
          linhaContaCustoMercadoria.add(true);
        }
      } else {
        itensExpandidos.add(it);
        produtosExpandidos.add(p);
        linhaContaCustoMercadoria.add(true);
      }
    }
    return (itensExpandidos, produtosExpandidos, linhaContaCustoMercadoria);
  }

  /// Mesmas validações que [VendasService.registrarVendaMulti] antes da transação.
  static void validarExpansaoParaBaixaFirestore({
    required List<VendaItem> itensParaEstoque,
    required List<Produto> produtosEncontrados,
  }) {
    for (var i = 0; i < itensParaEstoque.length; i++) {
      final it = itensParaEstoque[i];
      final p = produtosEncontrados[i];
      if (p.temVariacaoSoloCor && it.cor.trim().isEmpty) {
        throw Exception(
          'O produto "${it.produtoNome}" possui variação de cor. '
          'Clique em "Selecionar" e escolha a cor.',
        );
      }
      if (p.temVariacaoTamanhoECor && (it.tamanho.trim().isEmpty || it.cor.trim().isEmpty)) {
        throw Exception(
          'O produto "${it.produtoNome}" possui variações (tamanho + cor). '
          'Clique em "Selecionar" e escolha tamanho e cor.',
        );
      }
      if ((p.temVariacaoSoloTamanho || p.estoquePorTamanho.isNotEmpty) && it.tamanho.trim().isEmpty) {
        throw Exception(
          'O produto "${it.produtoNome}" possui variação de tamanho. '
          'Clique em "Selecionar" e escolha o tamanho (ex.: P, M, G).',
        );
      }
      final opcoesExtra = ProdutoVariacaoExtra.opcoesExtraPara(
        p.variacoes,
        it.tamanho.trim(),
        it.cor.trim(),
      );
      if (opcoesExtra.isNotEmpty && it.extraValor.trim().isEmpty) {
        throw Exception(
          'O produto "${it.produtoNome}" exige personalização (ex.: letra). '
          'Abra o combo na venda e selecione a opção, ou refaça a linha do kit.',
        );
      }
    }
  }

  /// Maps para [EstoqueTransactionService.baixarEstoqueTransactionBatch] (inclui [extraValor] quando preenchido).
  static List<Map<String, dynamic>> montarTxItemsParaBaixaEstoque({
    required List<VendaItem> itensParaEstoque,
    required List<Produto> produtosEncontrados,
  }) {
    final txItems = <Map<String, dynamic>>[];
    for (var i = 0; i < itensParaEstoque.length; i++) {
      final it = itensParaEstoque[i];
      final p = produtosEncontrados[i];
      txItems.add({
        'nome': it.produtoNome,
        'slug': p.slug,
        'productId': p.idFirebase.isNotEmpty ? p.idFirebase : null,
        'quantidade': it.quantidade,
        'tamanho': it.tamanho.trim(),
        'cor': it.cor.trim(),
        if (it.extraValor.trim().isNotEmpty) 'extraValor': it.extraValor.trim(),
      });
    }
    return txItems;
  }

  /// Persistência em [Venda.itensComboSelecaoJson] (Hive/Firestore).
  static String? serializeItensComboSelecaoPorIndice(
    Map<int, List<Map<String, dynamic>>>? m,
  ) {
    if (m == null || m.isEmpty) return null;
    final jsonMap = <String, dynamic>{};
    for (final e in m.entries) {
      if (e.value.isEmpty) continue;
      jsonMap['${e.key}'] = e.value;
    }
    if (jsonMap.isEmpty) return null;
    try {
      return jsonEncode(jsonMap);
    } catch (_) {
      return null;
    }
  }

  /// Leitura de [Venda.itensComboSelecaoJson] para o mesmo mapa usado em [expandirCombos].
  static Map<int, List<Map<String, dynamic>>>? parseItensComboSelecaoPorIndiceJson(
    String? raw,
  ) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final out = <int, List<Map<String, dynamic>>>{};
      for (final e in decoded.entries) {
        final idx = int.tryParse(e.key.toString());
        if (idx == null) continue;
        final list = e.value;
        if (list is! List) continue;
        final segura = <Map<String, dynamic>>[];
        for (final item in list) {
          if (item is Map) {
            segura.add(
              Map<String, dynamic>.from(
                item.map((k, v) => MapEntry(k.toString(), v)),
              ),
            );
          }
        }
        if (segura.isNotEmpty) out[idx] = segura;
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }
}
