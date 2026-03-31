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
import 'estoque_transaction_service.dart';
import 'movimentacao_estoque_service.dart';

class VendasService {
  // ---------------------------
  // Helpers
  // ---------------------------

  static String _fmt2(double v) => v.toStringAsFixed(2);

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

  /// Expande itens de combo em itens individuais para baixa de estoque.
  /// Para itens do combo: tenta productId (id/productId no mapa) primeiro, depois nome. Loga [COMBO_MATCH] em fallback por nome.
  /// Retorna (itens expandidos, produtos correspondentes).
  static (List<VendaItem>, List<Produto>) _expandirCombos({
    required List<VendaItem> itens,
    required Box<Produto> produtosBox,
    required String lojaId,
    Map<int, List<Map<String, dynamic>>>? itensComboSelecaoPorIndice,
  }) {
    final itensExpandidos = <VendaItem>[];
    final produtosExpandidos = <Produto>[];

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

      final listaCombo = itensComboSelecaoPorIndice?[idx] ?? p.itensCombo;
      if (p.ehCombo && listaCombo != null && listaCombo.isNotEmpty) {
        // Baixa a quantidade do kit no estoque (linha do combo) e de cada componente.
        itensExpandidos.add(it);
        produtosExpandidos.add(p);

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

          // Ordem explícita: productId → slug → nome. Logs [COMBO_ID] / [COMBO_FALLBACK] / [COMBO_ITEM].
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
          itensExpandidos.add(VendaItem(
            produtoNome: pComp.nome,
            quantidade: qtdTotal,
            precoUnitario: 0,
            tamanho: tam,
            cor: cor,
            productId: pComp.idFirebase.trim().isNotEmpty ? pComp.idFirebase : null,
          ));
          produtosExpandidos.add(pComp);
        }
      } else {
        itensExpandidos.add(it);
        produtosExpandidos.add(p);
      }
    }
    return (itensExpandidos, produtosExpandidos);
  }

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
    final (itensParaEstoque, produtosEncontrados) = _expandirCombos(
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

    // 3) baixa estoque via transação Firestore (OBRIGATÓRIO - sem fallback Hive)
    // Usa itensParaEstoque (combos já expandidos) para dar baixa em cada produto individual
    // Exige tamanho/cor quando o produto tem estoque por variação para baixa correta no Firestore
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
    }

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
      });
    }

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

    // 4) subtotal / total
    final subtotal = itens.fold<double>(
      0.0,
      (acc, it) => acc + (it.precoUnitario * it.quantidade),
    );
    final total = subtotal * (1 - descontoPct / 100) + frete;

    // 5) custo e taxas (usa itens originais para preço, itensParaEstoque para custo)
    int totalUnidades = 0;
    double custoProdutos = 0.0;
    for (var i = 0; i < itensParaEstoque.length; i++) {
      final it = itensParaEstoque[i];
      final p = produtosEncontrados[i];
      totalUnidades += it.quantidade;
      custoProdutos += (p.custoReal * it.quantidade);
    }
    final taxas = (3.50 * totalUnidades) + (0.15 * custoProdutos);

    // 6) se nenhum pagamento foi informado e não for fiado, joga tudo em dinheiro
    if (!isFiado && dinheiro == 0 && pix == 0 && cartao == 0) {
      dinheiro = total;
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
        final conta = ContaReceber(
          lojaId: lojaEfetiva,
          clienteNome: cliente.nome,
          valor: total,
          dataVencimento: dataVencimentoFiado,
          dataVenda: venda.data,
          vendaKey: venda.key is int ? venda.key as int : 0,
          observacao: observacao.trim().isEmpty ? 'Venda fiada' : observacao.trim(),
        );
        await crBox.add(conta);
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
    if (venda.itens != null && venda.itens!.isNotEmpty) {
      final (itensDevolucao, _) = _expandirCombos(
        itens: venda.itens!,
        produtosBox: produtosBox,
        lojaId: lojaId,
        itensComboSelecaoPorIndice: null,
      );
      final Map<String, ({String? productId, String nomeOriginal, String tam, String cor, int qtd})> agrupado = {};
      for (final it in itensDevolucao) {
        final pid = (it.productId ?? '').trim().isNotEmpty ? it.productId!.trim() : null;
        final nomeLower = it.produtoNome.trim().toLowerCase();
        final nomeOriginal = it.produtoNome.trim();
        final tam = it.tamanho.trim();
        final cor = it.cor.trim();
        final key = '${pid ?? ''}\x00$nomeLower\x00$tam\x00$cor';
        final existing = agrupado[key];
        if (existing != null) {
          agrupado[key] = (productId: existing.productId, nomeOriginal: existing.nomeOriginal, tam: existing.tam, cor: existing.cor, qtd: existing.qtd + it.quantidade);
        } else {
          agrupado[key] = (productId: pid, nomeOriginal: nomeOriginal, tam: tam, cor: cor, qtd: it.quantidade);
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
              })
          .toList();
      if (itens.isNotEmpty) {
        try {
          final results = await EstoqueTransactionService.devolverEstoqueTransactionBatch(
            lojaId: lojaId,
            itens: itens,
            vendaIdParaIdempotencia: vendaId,
          );
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

  /// Executa devolução de estoque e exclusão do Firestore.
  /// Usado pelo SoftDeleteService quando a exclusão se torna definitiva após 30 s.
  /// Não altera vendasBox nem clientesBox (venda já está na lixeira).
  static Future<void> executarExclusaoPermanente({
    required Venda venda,
    required Box<Produto> produtosBox,
    required String lojaId,
  }) async {
    // 1. Devolver produtos ao estoque (transacional, idempotente)
    final vendaId = (venda.idFirebase ?? '').trim().isNotEmpty
        ? venda.idFirebase!.trim()
        : 'hive_${venda.key}';
    if (venda.itens != null && venda.itens!.isNotEmpty) {
      final (itensDevolucao, _) = _expandirCombos(
        itens: venda.itens!,
        produtosBox: produtosBox,
        lojaId: lojaId,
        itensComboSelecaoPorIndice: null,
      );
      final Map<String, ({String? productId, String nomeOriginal, String tam, String cor, int qtd})> agrupado = {};
      for (final it in itensDevolucao) {
        final pid = (it.productId ?? '').trim().isNotEmpty ? it.productId!.trim() : null;
        final nomeLower = it.produtoNome.trim().toLowerCase();
        final nomeOriginal = it.produtoNome.trim();
        final tam = it.tamanho.trim();
        final cor = it.cor.trim();
        final key = '${pid ?? ''}\x00$nomeLower\x00$tam\x00$cor';
        final existing = agrupado[key];
        if (existing != null) {
          agrupado[key] = (productId: existing.productId, nomeOriginal: existing.nomeOriginal, tam: existing.tam, cor: existing.cor, qtd: existing.qtd + it.quantidade);
        } else {
          agrupado[key] = (productId: pid, nomeOriginal: nomeOriginal, tam: tam, cor: cor, qtd: it.quantidade);
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
              })
          .toList();
      if (itens.isNotEmpty) {
        try {
          final results = await EstoqueTransactionService.devolverEstoqueTransactionBatch(
            lojaId: lojaId,
            itens: itens,
            vendaIdParaIdempotencia: vendaId,
          );
          for (final r in results) {
            await EstoqueTransactionService.atualizarHiveAposTransacao(
              produtosBox: produtosBox,
              lojaId: lojaId,
              result: r,
            );
          }
        } catch (_) {}
      }
    } else {
      try {
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
            for (final r in results) {
              await EstoqueTransactionService.atualizarHiveAposTransacao(
                produtosBox: produtosBox,
                lojaId: lojaId,
                result: r,
              );
            }
          } catch (_) {}
        }
      } catch (_) {}
    }
    // 2. Deletar do Firestore
    if (venda.idFirebase != null && venda.idFirebase!.isNotEmpty) {
      await VendasFirestoreService.deleteVenda(venda.idFirebase!, lojaId: lojaId);
    }
  }
}
