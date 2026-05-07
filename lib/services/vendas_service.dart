// lib/services/vendas_service.dart
//
// Serviço de vendas para a tela "Nova Venda"
// ATUALIZADO: Agora sincroniza estoque no Firestore após baixar variações
import 'package:collection/collection.dart'; // firstWhereOrNull
import 'package:flutter/foundation.dart'; // debugPrint
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
import 'catalogo_web_apos_estoque_service.dart';
import 'combo_kit_stock_service.dart';
import 'estoque_transaction_service.dart';
import 'movimentacao_estoque_service.dart';
import 'venda_combo_estoque_expansion.dart';
import 'venda_custo_mercadoria.dart';

class VendasService {
  // ---------------------------
  // Helpers
  // ---------------------------

  static String _fmt2(double v) => v.toStringAsFixed(2);
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
  }) async {
    if (vendaKey <= 0) return;
    final loja = lojaId.trim();
    if (loja.isEmpty) return;
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
    await crBox.add(
      ContaReceber(
        lojaId: loja,
        clienteNome: venda.clienteNome,
        valor: venda.total,
        dataVencimento: venc,
        dataVenda: venda.data,
        vendaKey: vk,
        observacao: venda.observacao.trim().isEmpty
            ? 'Venda fiada'
            : venda.observacao.trim(),
      ),
    );
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
    void Function(String message)? onSyncError, // 🔹 feedback ao usuário quando sync Firestore falhar
    bool isFiado = false, // 🔹 venda fiada: gera conta a receber
    DateTime? dataVencimentoFiado, // 🔹 vencimento da conta (quando isFiado)
    int quantidadeParcelasFiado = 1, // 🔹 número de parcelas do fiado
    int intervaloParcelasDias = 30, // 🔹 intervalo em dias entre parcelas
    Map<int, List<Map<String, dynamic>>>? itensComboSelecaoPorIndice, // 🔹 seleção do cliente para combos
    void Function(String? numeroSorte)? onNumeroSorteGerado,
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
    final venda = Venda(
      clienteNome: cliente.nome,
      produtosDescricao: "$produtosDescricao\n$formasPagamentoTexto",
      quantidade: itens.length,
      preco: subtotal,
      total: total,
      formasPagamento: formasPagamentoTexto,
      data: DateTime.now(),
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
    );

    // Em edição: reutiliza idFirebase da venda antiga (evita duplicata no Firestore)
    if (idFirebaseToReuse != null && idFirebaseToReuse.isNotEmpty) {
      venda.idFirebase = idFirebaseToReuse;
    }

    debugPrint('💾 [VENDAS-SERVICE] Salvando venda - Dinheiro: R\$ ${_fmt2(dinheiro)}, Pix: R\$ ${_fmt2(pix)}, Cartão: R\$ ${_fmt2(cartao)}, Total: R\$ ${_fmt2(total)}');
    debugPrint('📤 [SYNC-DEBUG] VendasService.salvarVenda → lojaId=$lojaEfetiva | cliente=${cliente.nome} | total=R\$ ${_fmt2(total)}');

    await vendasBox.add(venda);

    // 8.1) se fiado, criar conta a receber (falha = rollback da venda atual)
    if (isFiado && dataVencimentoFiado != null) {
      try {
        final crBoxName = HiveBoxNames.contasReceber(lojaEfetiva);
        final crBox = Hive.isBoxOpen(crBoxName) ? Hive.box<ContaReceber>(crBoxName) : await Hive.openBox<ContaReceber>(crBoxName);
        final qtdParcelas = quantidadeParcelasFiado.clamp(1, 48);
        final intervalo = intervaloParcelasDias.clamp(1, 120);
        final valoresParcelas = _parcelarValores(total, qtdParcelas);
        for (var i = 0; i < qtdParcelas; i++) {
          final venc = dataVencimentoFiado.add(Duration(days: i * intervalo));
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

    // 11) 🎯 Registra participação em campanhas de sorteio (CENTRALIZADO)
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
      final (itensDevolucao, _, _) = VendaComboEstoqueExpansion.expandirCombos(
        itens: venda.itens!,
        produtosBox: produtosBox,
        lojaId: lojaId,
        itensComboSelecaoPorIndice: null,
      );
      final Map<String, ({String? productId, String nomeOriginal, String tam, String cor, String extra, int qtd})> agrupado = {};
      for (final it in itensDevolucao) {
        final pid = (it.productId ?? '').trim().isNotEmpty ? it.productId!.trim() : null;
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
            nomeOriginal: existing.nomeOriginal,
            tam: existing.tam,
            cor: existing.cor,
            extra: existing.extra,
            qtd: existing.qtd + it.quantidade,
          );
        } else {
          agrupado[key] = (
            productId: pid,
            nomeOriginal: nomeOriginal,
            tam: tam,
            cor: cor,
            extra: extra,
            qtd: it.quantidade,
          );
        }
      }
      final itens = agrupado.entries
          .where((e) => e.value.qtd > 0)
          .map((e) => {
                'productId': e.value.productId,
                'nome': e.value.nomeOriginal,
                'quantidade': e.value.qtd,
                'tamanho': e.value.tam,
                'cor': e.value.cor,
                if (e.value.extra.isNotEmpty) 'extraValor': e.value.extra,
              })
          .toList();
      if (itens.isNotEmpty) {
        try {
          final results = await EstoqueTransactionService.devolverEstoqueTransactionBatch(
            lojaId: lojaId,
            itens: itens,
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
          if (results.isNotEmpty) debugPrint('✅ Estoque devolvido (transacional): ${results.length} itens');
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
      final (itensDevolucao, _, _) = VendaComboEstoqueExpansion.expandirCombos(
        itens: venda.itens!,
        produtosBox: produtosBox,
        lojaId: lojaId,
        itensComboSelecaoPorIndice: null,
      );
      final Map<String, ({String? productId, String nomeOriginal, String tam, String cor, String extra, int qtd})> agrupado = {};
      for (final it in itensDevolucao) {
        final pid = (it.productId ?? '').trim().isNotEmpty ? it.productId!.trim() : null;
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
            nomeOriginal: existing.nomeOriginal,
            tam: existing.tam,
            cor: existing.cor,
            extra: existing.extra,
            qtd: existing.qtd + it.quantidade,
          );
        } else {
          agrupado[key] = (
            productId: pid,
            nomeOriginal: nomeOriginal,
            tam: tam,
            cor: cor,
            extra: extra,
            qtd: it.quantidade,
          );
        }
      }
      final itens = agrupado.entries
          .where((e) => e.value.qtd > 0)
          .map((e) => {
                'productId': e.value.productId,
                'nome': e.value.nomeOriginal,
                'quantidade': e.value.qtd,
                'tamanho': e.value.tam,
                'cor': e.value.cor,
                if (e.value.extra.isNotEmpty) 'extraValor': e.value.extra,
              })
          .toList();
      if (itens.isNotEmpty) {
        try {
          final results = await EstoqueTransactionService.devolverEstoqueTransactionBatch(
            lojaId: lojaId,
            itens: itens,
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
    final (itensParaBaixa, produtosEnc, _) =
        VendaComboEstoqueExpansion.expandirCombos(
      itens: venda.itens!,
      produtosBox: produtosBox,
      lojaId: lid,
      itensComboSelecaoPorIndice: null,
    );
    VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
      itensParaEstoque: itensParaBaixa,
      produtosEncontrados: produtosEnc,
    );
    final txItems = VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
      itensParaEstoque: itensParaBaixa,
      produtosEncontrados: produtosEnc,
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
