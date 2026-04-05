// lib/services/catalogo_venda_service.dart
//
// Serviço para registrar vendas vindas do catálogo público
// Integra com o sistema de relatórios existente
//
// ATUALIZADO: Agora usa EstoqueService para controle centralizado de estoque

import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/hive_box_names.dart';
import '../core/logger.dart';
import '../core/produto_variacao_extra.dart';
import '../core/mp_venda_identity.dart';
import '../core/strict_product_resolution.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import '../repositories/pedido_repository.dart';
import 'vendas_firestore_service.dart';
import 'clientes_firestore_service.dart';
import 'firestore_paths.dart';
import 'pedido_collection_resolver.dart';
import 'vendas_service.dart';
import 'campaign_engine_service.dart'; // 🎯 Integração com campanhas de sorteio
import 'combo_kit_stock_service.dart';
import 'estoque_transaction_service.dart';
import 'notificacao_vendas_service.dart';
import 'catalogo_web_apos_estoque_service.dart';
import 'catalogo_venda_helpers.dart';
import 'catalogo_venda_item_resolver.dart';
import 'produto_vendas_catalogo_denorm_service.dart';
import 'venda_custo_mercadoria.dart';

/// Serviço para registrar vendas vindas do catálogo público
/// Integra com o sistema de relatórios existente
///
/// ⚠️ IMPORTANTE: Vendas via gateway/marketplace só são finalizadas após
/// confirmação do pagamento. Antes disso, ficam como "pedido pendente"
/// sem baixar estoque, sem ir para histórico e sem aparecer em relatórios.
class CatalogoVendaService {
  static final PedidoRepository _pedidoRepository = PedidoRepository();

  /// Expande itens de combo em itens individuais para baixa de estoque.
  /// Resolução: 1) productId, 2) slug, 3) nome. Inclui productId no resultado quando disponível.
  static List<Map<String, dynamic>> _expandirItemsParaEstoque({
    required List<Map<String, dynamic>> items,
    required Box<Produto> produtosBox,
    required String lojaId,
  }) {
    return expandirItemsParaEstoque(
      items: items,
      produtosBox: produtosBox,
      lojaId: lojaId,
    );
  }
  /// Cria um pedido pendente do catálogo (SEM baixar estoque, SEM histórico)
  /// O pedido só será convertido em venda após confirmação do pagamento
  ///
  /// [lojaId] - ID da loja
  /// [customer] - Dados do cliente (nome, email, telefone, endereço)
  /// [items] - Lista de itens do carrinho [{'name': '', 'qty': 1, 'price': 0.0, 'productId': ''}]
  /// [entrega] - Dados da entrega (nome, valor, freteGratis, tipo)
  /// [pagamento] - Forma de pagamento (PIX, Cartão, etc)
  /// [observacao] - Observações adicionais
  /// [cupomCodigo] - Código do cupom aplicado (opcional)
  /// [desconto] - Valor do desconto aplicado (opcional)
  ///
  /// Retorna o ID do pedido pendente criado
  static Future<String?> criarPedidoPendente({
    required String lojaId,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> entrega,
    required String pagamento,
    String observacao = '',
    String? cupomCodigo,
    String? cupomFreteCodigo,
    double desconto = 0.0,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    String? premioRoletaDescricao,
    // ✅ NOVO: Tracking de vendedor para comissão
    String? vendedorUid,
    String? vendedorEmail,
    String? vendedorNome,
    String? trackingId,
  }) async {
    try {
      // 1. Calcular totais (aplica desconto PIX quando pagamento é PIX)
      double subtotal = 0.0;
      final isPix = pagamento.toUpperCase() == 'PIX';
      for (final item in items) {
        final qty = (item['quantidade'] as int?) ?? (item['qty'] as int?) ?? 1;  // ✅ CORRIGIDO
        final price = (item['preco'] as num?)?.toDouble() ?? (item['price'] as num?)?.toDouble() ?? 0.0;  // ✅ CORRIGIDO
        final pctPix = (item['percentualDescontoPix'] as num?)?.toDouble() ?? 0.0;
        final precoEfetivo = (isPix && pctPix > 0) ? price * (1 - pctPix / 100) : price;
        subtotal += precoEfetivo * qty;
      }

      final freteGratis = entrega['freteGratis'] == true;
      final freteValor = (entrega['valor'] as num?)?.toDouble() ?? 0.0;
      final total = subtotal + (freteGratis ? 0 : freteValor) - desconto;

      // 2. Validar estoque (SEM baixar). Resolução: 1) productId, 2) slug, 3) nome
      final produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
      final itemsComProductId = <Map<String, dynamic>>[];

      for (final item in items) {
        final productId = (item['productId'] ?? item['id'] ?? '').toString().trim();
        final nome = (item['nome'] ?? item['name'] ?? '').toString();
        final slug = (item['slug'] ?? '').toString();
        final qtd = (item['quantidade'] as int?) ?? (item['qty'] as int?) ?? 1;
        final tamanho = (item['tamanho'] ?? item['size'] ?? '').toString().trim();
        final cor = (item['cor'] ?? item['color'] ?? '').toString().trim();

        var produto = VendasService.encontrarProdutoNoEstoque(
          produtosBox: produtosBox,
          productId: productId.isNotEmpty ? productId : null,
          slug: slug.isNotEmpty ? slug : null,
          nome: nome.isNotEmpty ? nome : null,
          lojaId: lojaId,
        );

        String? resolvedProductId;

        if (produto == null) {
          logW('⚠️ [CATALOGO_ITEM] Produto não encontrado no Hive, buscando no Firestore: nome=$nome slug=$slug productId=$productId');

          DocumentSnapshot? produtoDoc;
          bool matchedByNome = false;

          // 1) Tentar por productId (doc id) primeiro
          if (productId.isNotEmpty) {
            final ref = FirebaseFirestore.instance
                .collection('lojas')
                .doc(lojaId)
                .collection('estoque_produtos')
                .doc(productId);
            final snap = await ref.get();
            if (snap.exists) {
              produtoDoc = snap;
            }
            if (produtoDoc == null) {
              final refProd = FirebaseFirestore.instance
                  .collection('lojas')
                  .doc(lojaId)
                  .collection('produtos')
                  .doc(productId);
              final snapProd = await refProd.get();
              if (snapProd.exists) produtoDoc = snapProd;
            }
          }

          // 2) Fallback: buscar por slug/nome
          if (produtoDoc == null) {
            final QuerySnapshot produtosSnapshot = await FirebaseFirestore.instance
                .collection('lojas')
                .doc(lojaId)
                .collection('produtos')
                .get();

            for (final doc in produtosSnapshot.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final docSlug = (data['slug'] ?? '').toString().trim().toLowerCase();
              final docNome = (data['nome'] ?? '').toString().trim().toLowerCase();

              final slugMatch = slug.isNotEmpty && docSlug == slug.trim().toLowerCase();
              final nomeMatch = nome.isNotEmpty && docNome == nome.trim().toLowerCase();
              if (slugMatch || nomeMatch) {
                produtoDoc = doc;
                matchedByNome = nomeMatch;
                logW('[CATALOGO_ITEM] Resolução por slug/nome no Firestore | lojaId=$lojaId | nome=$nome', tag: 'PRODUTO_FALLBACK');
                break;
              }
            }
          }
          if (produtoDoc != null && matchedByNome) {
            reportProductResolvedByName(
              lojaId: lojaId,
              fluxo: 'registrarVendaMulti_firestore_fallback',
              nome: nome,
              slug: slug.isNotEmpty ? slug : null,
              productIdRecebido: productId.isNotEmpty ? productId : null,
            );
          }

          if (produtoDoc == null) {
            throw Exception('Produto não encontrado no estoque: $nome. Verifique se o produto existe no cadastro.');
          }
          resolvedProductId = produtoDoc.id;

          final produtoData = produtoDoc.data() as Map<String, dynamic>;

          // 🔹 Validar estoque com variações do Firestore
          final variacoesData = produtoData['variacoes'] as Map<String, dynamic>?;
          final estoquePorTamanhoData = produtoData['estoquePorTamanho'] as Map<String, dynamic>?;

          // 🚨 VALIDAÇÃO: Se produto tem variações, EXIGIR tamanho E cor
          if (variacoesData != null && variacoesData.isNotEmpty && (tamanho.isEmpty || cor.isEmpty)) {
            throw Exception(
              'ERRO: O produto "$nome" possui variações de tamanho e cor. '
              'É obrigatório informar TAMANHO e COR na venda. '
              'Tamanho recebido: "${tamanho.isEmpty ? "VAZIO" : tamanho}", '
              'Cor recebida: "${cor.isEmpty ? "VAZIO" : cor}". '
              'Verifique se o site está capturando corretamente a cor selecionada.'
            );
          }

          int qtdDisponivel;
          if (variacoesData != null && variacoesData.isNotEmpty && tamanho.isNotEmpty && cor.isNotEmpty) {
            // Produto com variações (tamanho + cor); célula pode ser int ou mapa (letras).
            final mapaTamanho = variacoesData[tamanho] as Map<String, dynamic>?;
            final cell = mapaTamanho?[cor];
            final extraTrim =
                (item['extraValor'] ?? item['variacaoExtra'] ?? '').toString().trim();
            qtdDisponivel =
                ProdutoVariacaoExtra.estoqueDisponivelParaCelula(cell, extraTrim);

            if (qtdDisponivel < qtd) {
              throw Exception('Estoque insuficiente para "$nome" no tamanho $tamanho - cor $cor (solicitado: $qtd, disponível: $qtdDisponivel)');
            }
          } else if (estoquePorTamanhoData != null && estoquePorTamanhoData.isNotEmpty && tamanho.isNotEmpty) {
            // Produto apenas com tamanhos
            qtdDisponivel = ProdutoVariacaoExtra.valorFirestoreComoInt(
              estoquePorTamanhoData[tamanho],
            );

            if (qtdDisponivel < qtd) {
              throw Exception('Estoque insuficiente para "$nome" no tamanho $tamanho (solicitado: $qtd, disponível: $qtdDisponivel)');
            }
          } else {
            // Produto sem grades
            qtdDisponivel = (produtoData['quantidade'] as num?)?.toInt() ?? 0;

            if (qtdDisponivel < qtd) {
              throw Exception('Estoque insuficiente para "$nome" (solicitado: $qtd, disponível: $qtdDisponivel)');
            }
          }
        } else {
          resolvedProductId = produto.idFirebase;
          // 🔹 Validar estoque do produto encontrado no Hive com variações
          int qtdDisponivel;

          // 🚨 VALIDAÇÃO: Se produto tem variações, EXIGIR tamanho E cor
          if (produto.usaVariacoes && (tamanho.isEmpty || cor.isEmpty)) {
            throw Exception(
              'ERRO: O produto "$nome" possui variações de tamanho e cor. '
              'É obrigatório informar TAMANHO e COR na venda. '
              'Tamanho recebido: "${tamanho.isEmpty ? "VAZIO" : tamanho}", '
              'Cor recebida: "${cor.isEmpty ? "VAZIO" : cor}". '
              'Verifique se o site está capturando corretamente a cor selecionada.'
            );
          }

          if (produto.usaVariacoes && tamanho.isNotEmpty && cor.isNotEmpty) {
            // Produto com variações (tamanho + cor); personalização opcional em extraValor.
            final extraTrim =
                (item['extraValor'] ?? item['variacaoExtra'] ?? '').toString().trim();
            qtdDisponivel = produto.obterEstoqueVariacao(tamanho, cor, extraTrim);

            if (qtdDisponivel < qtd) {
              throw Exception('Estoque insuficiente para "$nome" no tamanho $tamanho - cor $cor (solicitado: $qtd, disponível: $qtdDisponivel)');
            }
          } else if (produto.estoquePorTamanho.isNotEmpty && tamanho.isNotEmpty) {
            // Produto apenas com tamanhos
            qtdDisponivel = produto.estoquePorTamanho[tamanho] ?? 0;

            if (qtdDisponivel < qtd) {
              throw Exception('Estoque insuficiente para "$nome" no tamanho $tamanho (solicitado: $qtd, disponível: $qtdDisponivel)');
            }
          } else {
            // Produto sem grades
            qtdDisponivel = produto.quantidade;

            if (qtdDisponivel < qtd) {
              throw Exception('Estoque insuficiente para "$nome" (solicitado: $qtd, disponível: $qtdDisponivel)');
            }
          }
        }
        final itemPayload = Map<String, dynamic>.from(item);
        if (resolvedProductId.isNotEmpty) {
          itemPayload['productId'] = resolvedProductId;
        }
        itemsComProductId.add(itemPayload);
      }

      // 3. Salvar APENAS como pedido pendente no Firestore (SEM baixar estoque, SEM venda)
      final pedidoRef = await _pedidoRepository.createPedido(
        flowType: PedidoFlowType.pedidosPendentes,
        lojaId: lojaId,
        data: {
        'tipo': 'catalogo_web',
        'lojaId': lojaId,
        'cliente': {
          'nome': customer['nome'],
          'email': customer['email'],
          'telefone': customer['telefone'],
          'endereco': customer['endereco'],
          'enderecoFormatado': customer['enderecoFormatado'],
        },
        'itens': itemsComProductId
            .map((item) {
              final price = (item['preco'] ?? item['price'] ?? 0.0) as num;
              final qty = (item['quantidade'] ?? item['qty'] ?? 1) as int;
              final pctPix = (item['percentualDescontoPix'] as num?)?.toDouble() ?? 0.0;
              final precoEfetivo = (isPix && pctPix > 0)
                  ? (price.toDouble() * (1 - pctPix / 100))
                  : price.toDouble();
              return {
                'nome': item['nome'] ?? item['name'] ?? '',
                'slug': item['slug'] ?? '',
                if (item['productId'] != null && (item['productId'] as String).isNotEmpty) 'productId': item['productId'],
                'quantidade': qty,
                'precoUnitario': precoEfetivo,
                'tamanho': item['tamanho'] ?? item['size'] ?? '',
                'cor': item['cor'] ?? item['color'] ?? '',
                'imageUrl': item['imageUrl'] ?? item['url_foto'] ?? '',
                'total': precoEfetivo * qty,
              };
            })
            .toList(),
        'subtotal': subtotal,
        'frete': {
          'nome': entrega['nome'],
          'valor': freteValor,
          'gratis': freteGratis,
          'tipo': entrega['tipo'],
        },
        'cupom': cupomCodigo != null
            ? {
                'codigo': cupomCodigo,
                'desconto': desconto,
              }
            : null,
        'cupomFrete': cupomFreteCodigo != null && cupomFreteCodigo.isNotEmpty
            ? {'codigo': cupomFreteCodigo}
            : null,
        'cupomRoleta': cupomRoletaCodigo != null
            ? {
                'codigo': cupomRoletaCodigo,
                'desconto': cupomRoletaDesconto,
              }
            : null,
        'premioRoleta': premioRoletaDescricao != null || cupomRoletaCodigo != null
            ? {
                'descricao': premioRoletaDescricao ?? '',
                'tipo': determinarTipoPremio(premioRoletaDescricao, cupomRoletaCodigo, cupomRoletaDesconto),
                'valor': cupomRoletaDesconto ?? 0.0,
                'codigo': cupomRoletaCodigo,
                'status': 'pendente',
                'dataGanho': FieldValue.serverTimestamp(),
                'dataAtivacao': null,
                'valido': false,
              }
            : null,
        'total': total,
        'desconto': desconto,
        'pagamento': pagamento,
        'observacao': observacao,
        'dataHora': FieldValue.serverTimestamp(),
        'status': 'aguardando_pagamento', // Status inicial
        'estoqueBaixado': false, // Controle: estoque ainda não foi baixado
        'vendaRegistrada': false, // Controle: venda ainda não foi registrada
        // ✅ NOVO: Tracking de vendedor para comissão
        'origem': 'catalogo',
        'vendedorUid': vendedorUid,
        'vendedorEmail': vendedorEmail,
        'vendedorNome': vendedorNome,
        'trackingId': trackingId,
        },
      );

      logD('✅ Pedido pendente criado: ${pedidoRef.id} (aguardando pagamento)');
      if (vendedorUid != null) {
        logD('   📊 Tracking: vendedor=$vendedorNome ($vendedorUid)');
      }

      // 🎉 Notificar admin sobre o novo pedido (com entusiasmo!)
      final clienteNome = (customer['nome'] ?? customer['name'] ?? '').toString();
      await NotificacaoVendasService().notificarAdminNovaVenda(
        storeId: lojaId,
        pedidoId: pedidoRef.id,
        clienteNome: clienteNome.isNotEmpty ? clienteNome : 'Cliente',
        valorTotal: total,
        origem: 'catalogo_web',
        vendedorNome: vendedorNome,
        pagamentoConfirmado: false,
      );

      return pedidoRef.id;
    } catch (e, st) {
      logE('❌ Erro ao criar pedido pendente (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  /// Registra uma venda do catálogo público no sistema de relatórios
  /// ⚠️ DEPRECATED: Use criarPedidoPendente() + finalizarPedidoComPagamento() para vendas via gateway
  /// Este método mantido para compatibilidade com vendas locais (APK)
  ///
  /// [lojaId] - ID da loja
  /// [customer] - Dados do cliente (nome, email, telefone, endereço)
  /// [items] - Lista de itens do carrinho [{'name': '', 'qty': 1, 'price': 0.0, 'productId': ''}]
  /// [entrega] - Dados da entrega (nome, valor, freteGratis, tipo)
  /// [pagamento] - Forma de pagamento (PIX, Cartão, etc)
  /// [observacao] - Observações adicionais
  /// [cupomCodigo] - Código do cupom aplicado (opcional)
  /// [desconto] - Valor do desconto aplicado (opcional)
  ///
  /// Retorna o ID da venda criada
  static Future<String?> registrarVendaCatalogo({
    required String lojaId,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> entrega,
    required String pagamento,
    String observacao = '',
    String? cupomCodigo,
    String? cupomFreteCodigo,
    double desconto = 0.0,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    String? premioRoletaDescricao,
    // ✅ NOVO: Tracking de vendedor para comissão
    String? vendedorUid,
    String? vendedorEmail,
    String? vendedorNome,
    String? trackingId,
    /// ✅ Total e subtotal já calculados (ex: do pre_pedido) — usa em vez de recalcular
    double? totalOverride,
    double? subtotalOverride,
    /// Quando false, NÃO baixa estoque (baixa ficará a cargo do PosPagamentoService).
    /// Usar ao confirmar pre_pedido manualmente para evitar dupla baixa.
    bool baixarEstoque = true,
  }) async {
    try {
      // 1. Calcular totais (aplica desconto PIX quando pagamento é PIX)
      double subtotal = 0.0;
      final isPix = pagamento.toUpperCase() == 'PIX';
      if (subtotalOverride != null && subtotalOverride >= 0) {
        subtotal = subtotalOverride;
      } else {
        for (final item in items) {
          final qty = (item['quantidade'] as int?) ?? (item['qty'] as int?) ?? 1;
          final price = (item['preco'] as num?)?.toDouble() ?? (item['price'] as num?)?.toDouble() ?? 0.0;
          final pctPix = (item['percentualDescontoPix'] as num?)?.toDouble() ?? 0.0;
          // ✅ Se precoUnitario já vier como preco (do pre_pedido), preco já é efetivo
          final precoEfetivo = (isPix && pctPix > 0) ? price * (1 - pctPix / 100) : price;
          subtotal += precoEfetivo * qty;
        }
      }

      final freteGratis = entrega['freteGratis'] == true;
      final freteValor = (entrega['valor'] as num?)?.toDouble() ?? 0.0;
      final total = totalOverride ?? (subtotal + (freteGratis ? 0 : freteValor) - desconto);

      // 2. Criar/Buscar cliente
      final clienteBox = await Hive.openBox<Cliente>(HiveBoxNames.clientes(lojaId));
      Cliente? cliente;

      // Buscar cliente existente pelo email ou telefone
      final telefone = (customer['telefone'] ?? '').toString().trim();
      final email = (customer['email'] ?? '').toString().trim();

      for (final c in clienteBox.values) {
        if (c.lojaId == lojaId) {
          if ((email.isNotEmpty && c.email == email) ||
              (telefone.isNotEmpty && c.telefone == telefone)) {
            cliente = c;
            break;
          }
        }
      }

      // Se não encontrou, criar novo cliente
      if (cliente == null) {
        final endereco = customer['endereco'] as Map<String, dynamic>?;
        cliente = Cliente(
          nome: (customer['nome'] ?? '').toString(),
          telefone: telefone,
          instagram: '',
          email: email,
          endereco: (customer['enderecoFormatado'] ?? '').toString(),
          cep: endereco?['cep']?.toString() ?? '',
          cidade: endereco?['cidade']?.toString() ?? '',
          lojaId: lojaId,
        );
        await clienteBox.add(cliente);

        // Sincronizar novo cliente com Firestore
        try {
          await ClientesFirestoreService.syncCliente(cliente, lojaId: lojaId);
        } catch (e, st) {
          logE('⚠️ Erro ao sincronizar cliente com Firestore (type=${e.runtimeType})', error: e, st: st);
        }
      }

      // 3. Baixar estoque via transação Firestore (atômico) + criar vendaItens
      // Quando baixarEstoque=false (ex.: confirmação manual pre_pedido), a baixa é feita pelo PosPagamentoService.
      final produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
      final vendaItens = <VendaItem>[];

      if (baixarEstoque) {
        final itemsParaEstoque = _expandirItemsParaEstoque(
          items: items,
          produtosBox: produtosBox,
          lojaId: lojaId,
        );
        if (itemsParaEstoque.isEmpty) {
          throw Exception('Nenhum item válido para baixa de estoque');
        }

        final txResults = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
          lojaId: lojaId,
          itens: itemsParaEstoque,
        );

        await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(lojaId, txResults);

        for (final result in txResults) {
          await EstoqueTransactionService.atualizarHiveAposTransacao(
            produtosBox: produtosBox,
            lojaId: lojaId,
            result: result,
            tamanho: '',
            cor: '',
          );
        }

        final txResultsComboCap =
            await ComboKitStockService.aplicarTetoEstoqueComboAposBaixa(
          lojaId: lojaId,
          produtosBox: produtosBox,
          produtoIdsDebitadosNaVenda:
              ComboKitStockService.produtoIdsDeResultadosBaixa(txResults),
        );

        await CatalogoWebAposEstoqueService.sincronizarAposResultadosTransacao(
          lojaId: lojaId,
          produtosBox: produtosBox,
          resultadosPrincipais: txResults,
          resultadosComboExtra: txResultsComboCap,
        );
      }

      for (final item in items) {
        final nome = (item['nome'] ?? item['name'] ?? '').toString();
        final qtd = (item['quantidade'] as int?) ?? (item['qty'] as int?) ?? 1;
        final tamanho = (item['tamanho'] ?? item['size'] ?? '').toString().trim();
        final cor = (item['cor'] ?? item['color'] ?? '').toString().trim();
        final resumoExtra =
            (item['variacaoExtraResumo'] ?? '').toString().trim();
        final price = (item['preco'] as num?)?.toDouble() ?? (item['price'] as num?)?.toDouble() ?? 0.0;
        final pctPix = (item['percentualDescontoPix'] as num?)?.toDouble() ?? 0.0;
        final precoUnitario = (isPix && pctPix > 0) ? price * (1 - pctPix / 100) : price;
        final pid = (item['productId'] ?? item['id'] ?? '').toString().trim();

        vendaItens.add(VendaItem(
          produtoNome: nome,
          quantidade: qtd,
          precoUnitario: precoUnitario,
          tamanho: tamanho,
          cor: cor,
          lojaId: lojaId,
          productId: pid.isNotEmpty ? pid : null,
          variacaoExtraResumo: resumoExtra,
        ));
      }

      // 4. Definir valores de pagamento
      double pagamentoPix = 0.0;
      double pagamentoCartao = 0.0;
      double pagamentoDinheiro = 0.0;

      switch (pagamento.toUpperCase()) {
        case 'PIX':
          pagamentoPix = total;
          break;
        case 'CARTÃO':
        case 'CARTAO':
        case 'MERCADO PAGO':
          pagamentoCartao = total;
          break;
        case 'DINHEIRO':
          pagamentoDinheiro = total;
          break;
        default:
          // Padrão: PIX
          pagamentoPix = total;
      }

      // 5. Criar venda
      final venda = Venda(
        preco: subtotal,
        total: total,
        desconto: (desconto / subtotal * 100).clamp(0, 100), // Converter para %
        clienteNome: cliente.nome,
        produtosDescricao: gerarDescricaoProdutos(items),
        quantidade: items.fold<int>(0, (prev, item) => prev + ((item['quantidade'] as int?) ?? (item['qty'] as int?) ?? 1)),  // ✅ CORRIGIDO
        data: DateTime.now(),
        vendedor: 'Loja online',
        observacao: observacao,
        tamanho: '',
        frete: freteValor,
        lojaId: lojaId,
        itens: vendaItens,
        formasPagamento: pagamento, // Forma de pagamento como string
        pagamentoPix: pagamentoPix,
        pagamentoCartao: pagamentoCartao,
        pagamentoDinheiro: pagamentoDinheiro,
      );

      venda.custoProdutos = VendaCustoMercadoria.custoMercadoriaDesdeItensCatalogo(
        items: items,
        produtosBox: produtosBox,
        lojaId: lojaId,
        subtotalParaFallbackHeuristica: subtotal,
      );
      final uMerc = VendaCustoMercadoria.unidadesMercadoriaDesdeItensCatalogo(
        items: items,
        produtosBox: produtosBox,
        lojaId: lojaId,
      );
      venda.taxas = VendaCustoMercadoria.taxasLegadoVendaApk(
        custoMercadoria: venda.custoProdutos,
        unidadesMercadoria: uMerc > 0 ? uMerc : venda.quantidade,
      );

      // 6. Salvar venda no Hive
      final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
      await vendasBox.add(venda);

      // 6b. Denormalizar vendas no doc do produto (catálogo / "Mais vendidos") — não bloqueia o fluxo
      try {
        await ProdutoVendasCatalogoDenormService.incrementarAposVendaCatalogo(
          lojaId: lojaId,
          items: items,
          produtosBox: produtosBox,
        );
      } catch (e, st) {
        logE(
          '⚠️ [VENDAS_CATALOGO_DENORM] Não crítico após registrarVendaCatalogo (type=${e.runtimeType})',
          error: e,
          st: st,
        );
      }

      // 7. Adicionar venda ao histórico do cliente
      // ignore: experimental_member_use
      cliente.historico ??= HiveList(vendasBox);
      cliente.historico!.add(venda);
      await cliente.save();

      // 8. Sincronizar com Firestore
      logD('📤 [SYNC-DEBUG] CatalogoVendaService (pedido→venda) → lojaId=$lojaId | cliente=${venda.clienteNome} | total=R\$${venda.total.toStringAsFixed(2)}');
      try {
        final ok = await VendasFirestoreService.syncVenda(venda, lojaId: lojaId);
        if (!ok) {
          logW('⚠️ CatalogoVendaService: venda não sincronizada com Firestore (lojaId=$lojaId, key=${venda.key})');
        }
      } catch (e, st) {
        logE('⚠️ Erro inesperado ao sincronizar venda com Firestore (type=${e.runtimeType})', error: e, st: st);
        // Não falha a operação se a sincronização falhar
      }

      // 8. Salvar também em pedidos do Firestore (histórico completo)
      try {
        await _pedidoRepository.createPedido(
          flowType: PedidoFlowType.pedidos,
          lojaId: lojaId,
          data: {
          'tipo': 'catalogo_web',
          'lojaId': lojaId,
          'vendaId': venda.key.toString(),
          'cliente': {
            'nome': customer['nome'],
            'email': customer['email'],
            'telefone': customer['telefone'],
            'endereco': customer['endereco'],
          },
          'itens': items
              .map((item) {
                final price = (item['preco'] ?? item['price'] ?? 0.0) as num;
                final qty = (item['quantidade'] ?? item['qty'] ?? 1) as int;
                final pctPix = (item['percentualDescontoPix'] as num?)?.toDouble() ?? 0.0;
                final precoEfetivo = (isPix && pctPix > 0)
                    ? (price.toDouble() * (1 - pctPix / 100))
                    : price.toDouble();
                return {
                  'nome': item['nome'] ?? item['name'] ?? '',
                  'quantidade': qty,
                  'precoUnitario': precoEfetivo,
                  'tamanho': item['tamanho'] ?? item['size'] ?? '',
                  'cor': item['cor'] ?? item['color'] ?? '',
                  'imageUrl': item['imageUrl'] ?? item['url_foto'] ?? '',
                  'total': precoEfetivo * qty,
                };
              })
              .toList(),
          'subtotal': subtotal,
          'frete': {
            'nome': entrega['nome'],
            'valor': freteValor,
            'gratis': freteGratis,
            'tipo': entrega['tipo'],
          },
          'cupom': cupomCodigo != null
              ? {
                  'codigo': cupomCodigo,
                  'desconto': desconto,
                }
              : null,
          'cupomFrete': cupomFreteCodigo != null && cupomFreteCodigo.isNotEmpty
              ? {'codigo': cupomFreteCodigo}
              : null,
          'cupomRoleta': cupomRoletaCodigo != null
              ? {
                  'codigo': cupomRoletaCodigo,
                  'desconto': cupomRoletaDesconto,
                }
              : null,
          // ✅ Prêmio da roleta com estrutura completa
          'premioRoleta': premioRoletaDescricao != null || cupomRoletaCodigo != null
              ? {
                  'descricao': premioRoletaDescricao ?? '',
                  'tipo': determinarTipoPremio(premioRoletaDescricao, cupomRoletaCodigo, cupomRoletaDesconto),
                  'valor': cupomRoletaDesconto ?? 0.0,
                  'codigo': cupomRoletaCodigo,
                  'status': 'pendente', // pendente | ativo | usado
                  'dataGanho': FieldValue.serverTimestamp(),
                  'dataAtivacao': null, // será preenchido após confirmação de pagamento
                  'valido': false, // só fica true após confirmação de pagamento
                }
              : null,
          'total': total,
          'pagamento': pagamento,
          'observacao': observacao,
          'dataHora': FieldValue.serverTimestamp(),
          'status': 'concluido', // Venda local já está concluída
          // ✅ NOVO: Tracking de vendedor para comissão
          'origem': 'catalogo',
          'vendedorUid': vendedorUid,
          'vendedorEmail': vendedorEmail,
          'vendedorNome': vendedorNome,
          'trackingId': trackingId,
          },
        );
      } catch (e, st) {
        logE('⚠️ Erro ao salvar pedido no Firestore (type=${e.runtimeType})', error: e, st: st);
      }

      logD('✅ Venda do catálogo registrada com sucesso: ${venda.key}');
      if (vendedorUid != null) {
        logD('   📊 Tracking: vendedor=$vendedorNome ($vendedorUid)');
      }

      // 9. 🎯 Registrar número da sorte em campanha ativa (quando houver)
      try {
        final resultado = await CampaignEngineService.onVendaConcluida(
          lojaId: lojaId,
          venda: venda,
          vendaId: venda.key.toString(),
          clienteNome: cliente.nome,
          clienteId: cliente.key?.toString(),
          telefone: telefone,
          email: email,
          valorTotal: total,
          origem: 'catalogo',
          nomeLoja: lojaId,
        );

        if (resultado.sucesso) {
          logD('🎫 [CATÁLOGO] Número da sorte gerado: ${resultado.numero}');
        } else if (resultado.erro != null) {
          logD('ℹ️ [CATÁLOGO] Campanha: ${resultado.erro}');
        }
      } catch (e, st) {
        logE('⚠️ [CATÁLOGO] Erro ao registrar campanha (não crítico) (type=${e.runtimeType})', error: e, st: st);
      }

      // 10. 🎁 Cupom da roleta: salva em clientes_catalogo (USO ESPECÍFICO: cupons por email)
      if (cupomRoletaCodigo != null &&
          cupomRoletaCodigo.isNotEmpty &&
          email.isNotEmpty) {
        try {
          final emailNorm = email.trim().toLowerCase();
          final dataExpiracao = DateTime.now().add(const Duration(days: 60));
          final descricao = premioRoletaDescricao?.isNotEmpty == true
              ? premioRoletaDescricao!
              : '${(cupomRoletaDesconto ?? 0).toStringAsFixed(0)}% de desconto';

          await FirebaseFirestore.instance
              .collection('lojas')
              .doc(lojaId)
              .collection(FSPaths.clientesCatalogoCol)
              .doc(emailNorm)
              .collection('cupons')
              .doc(cupomRoletaCodigo)
              .set({
            'codigo': cupomRoletaCodigo,
            'descricao': descricao,
            'tipo': 'desconto',
            'valor': cupomRoletaDesconto ?? 0.0,
            'dataGanho': FieldValue.serverTimestamp(),
            'dataExpiracao': Timestamp.fromDate(dataExpiracao),
            'usado': false,
            'ativo': true,
            'origem': 'roleta_sorte',
          });
          logD('🎁 [CATÁLOGO] Cupom da roleta salvo no perfil (após confirmação da compra): $cupomRoletaCodigo');
        } catch (e, st) {
          logE('⚠️ [CATÁLOGO] Erro ao salvar cupom roleta no perfil (não crítico) (type=${e.runtimeType})', error: e, st: st);
        }
      }

      // 🎉 Notificar admin sobre o novo pedido (com entusiasmo!)
      await NotificacaoVendasService().notificarAdminNovaVenda(
        storeId: lojaId,
        pedidoId: venda.key.toString(),
        clienteNome: cliente.nome,
        valorTotal: total,
        origem: 'catalogo_web',
        vendedorNome: vendedorNome,
        pagamentoConfirmado: true, // Venda local já concluída
      );

      return venda.key.toString();
    } catch (e, st) {
      logE('❌ Erro ao registrar venda do catálogo (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  /// Atualiza o status de um pedido do catálogo
  ///
  /// [lojaId] - ID da loja
  /// [vendaId] - ID da venda
  /// [status] - Novo status (pago, cancelado, etc)
  static Future<void> atualizarStatusPedido({
    required String lojaId,
    required String vendaId,
    required String status,
  }) async {
    try {
      // Atualizar no Firestore
      final pedidoRef = await _pedidoRepository.findFirstRefByField(
        flowType: PedidoFlowType.pedidos,
        lojaId: lojaId,
        field: 'vendaId',
        value: vendaId,
      );

      if (pedidoRef != null) {
        await pedidoRef.update({
          'status': status,
          'dataAtualizacao': FieldValue.serverTimestamp(),
        });
      }

      logD('✅ Status do pedido $vendaId atualizado para: $status');
    } catch (e, st) {
      logE('❌ Erro ao atualizar status do pedido (type=${e.runtimeType})', error: e, st: st);
    }
  }

  /// Cancela uma venda do catálogo
  ///
  /// [lojaId] - ID da loja
  /// [vendaId] - Key da venda no Hive
  static Future<bool> cancelarVenda({
    required String lojaId,
    required String vendaId,
  }) async {
    try {
      final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
      final venda = vendasBox.get(vendaId);

      if (venda == null) {
        logE('❌ Venda não encontrada: $vendaId');
        return false;
      }

      // Marcar como cancelada
      await atualizarStatusPedido(
        lojaId: lojaId,
        vendaId: vendaId,
        status: 'cancelado',
      );

      // Remover da caixa de vendas (opcional - pode preferir manter com status)
      // await venda.delete();

      logD('✅ Venda $vendaId cancelada com sucesso');
      return true;
    } catch (e, st) {
      logE('❌ Erro ao cancelar venda (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Confirma pagamento de uma venda do catálogo (método legado)
  ///
  /// [lojaId] - ID da loja
  /// [vendaId] - Key da venda no Hive
  static Future<bool> confirmarPagamento({
    required String lojaId,
    required String vendaId,
  }) async {
    try {
      await atualizarStatusPedido(
        lojaId: lojaId,
        vendaId: vendaId,
        status: 'pago',
      );

      logD('✅ Pagamento da venda $vendaId confirmado');
      return true;
    } catch (e, st) {
      logE('❌ Erro ao confirmar pagamento (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// ✅ Finaliza um pedido pendente após confirmação do pagamento (gateway).
  ///
  /// **Legado / uso atual:** não há chamadas a este método nos fluxos Dart do
  /// catálogo público (checkout MP usa `processMpWebhook` + Hive sync interno).
  /// Mantido para consolidação manual, testes ou evolução futura sem perder a lógica
  /// de campanha (`CampaignEngineService`) já embutida abaixo.
  ///
  /// [lojaId] - ID da loja
  /// [pedidoId] - ID do pedido pendente no Firestore
  ///
  /// Retorna o ID da venda criada ou null se falhar
  static Future<String?> finalizarPedidoComPagamento({
    required String lojaId,
    required String pedidoId,
  }) async {
    try {
      // 1. Buscar pedido pendente
      final pedidoDoc = await _pedidoRepository.docRef(
        flowType: PedidoFlowType.pedidosPendentes,
        lojaId: lojaId,
        pedidoId: pedidoId,
      ).get();

      if (!pedidoDoc.exists) {
        logE('❌ Pedido pendente não encontrado: $pedidoId');
        return null;
      }

      final pedido = pedidoDoc.data()!;

      // Verificar se já foi processado
      if (pedido['vendaRegistrada'] == true) {
        logW('⚠️ Pedido já foi finalizado anteriormente: $pedidoId');
        return pedido['vendaId']?.toString();
      }

      final paymentIdStr = (pedido['paymentId'] ?? '').toString().trim();
      final paidAtRaw = pedido['paidAt'];

      // Webhook MP já criou estoque_vendas/mp_* — não baixar estoque de novo nem UUID paralelo
      if (paidAtRaw != null && paymentIdStr.isNotEmpty) {
        final canonicalId = mpVendaFirestoreDocumentId(
          orderId: pedidoId,
          paymentId: paymentIdStr,
        );
        final snap = await FirebaseFirestore.instance
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueVendasCol)
            .doc(canonicalId)
            .get();
        if (snap.exists && snap.data() != null) {
          logD(
            '[MP-WEBHOOK] consolidando Hive a partir de $canonicalId (sem segunda baixa de estoque)',
          );
          final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
          Venda? ja;
          for (final v in vendasBox.values) {
            if (v.lojaId != lojaId) continue;
            if (v.idFirebase == canonicalId) {
              ja = v;
              break;
            }
            if (v.paymentId == paymentIdStr &&
                (v.prePedidoId == pedidoId || v.orderId == pedidoId)) {
              ja = v;
              break;
            }
          }
          if (ja != null) {
            await pedidoDoc.reference.update({
              'vendaRegistrada': true,
              'vendaId': ja.key.toString(),
              'vendaFirestoreId': canonicalId,
              'dataFinalizacao': FieldValue.serverTimestamp(),
            });
            return ja.key.toString();
          }
          final nova = VendasFirestoreService.vendaFromFirestoreMap(
            Map<String, dynamic>.from(snap.data()!),
            canonicalId,
            lojaId,
          );
          await vendasBox.add(nova);
          final customer = pedido['cliente'] as Map<String, dynamic>;
          final itens = (pedido['itens'] as List).cast<Map<String, dynamic>>();
          final clienteBox = await Hive.openBox<Cliente>(HiveBoxNames.clientes(lojaId));
          Cliente? cliente;
          final telefone = (customer['telefone'] ?? '').toString().trim();
          final email = (customer['email'] ?? '').toString().trim();
          for (final c in clienteBox.values) {
            if (c.lojaId == lojaId) {
              if ((email.isNotEmpty && c.email == email) ||
                  (telefone.isNotEmpty && c.telefone == telefone)) {
                cliente = c;
                break;
              }
            }
          }
          if (cliente != null) {
            cliente.historico ??= HiveList(vendasBox); // ignore: experimental_member_use
            cliente.historico!.add(nova);
            await cliente.save();
          }
          final produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
          try {
            await ProdutoVendasCatalogoDenormService.incrementarAposVendaCatalogo(
              lojaId: lojaId,
              items: itens,
              produtosBox: produtosBox,
            );
          } catch (_) {}
          try {
            await _pedidoRepository.createPedido(
              flowType: PedidoFlowType.pedidos,
              lojaId: lojaId,
              data: {
                'tipo': 'catalogo_web',
                'lojaId': lojaId,
                'vendaId': nova.key.toString(),
                'cliente': customer,
                'itens': itens,
                'subtotal': pedido['subtotal'],
                'frete': pedido['frete'],
                'total': pedido['total'],
                'pagamento': pedido['pagamento'],
                'observacao': pedido['observacao'] ?? '',
                'dataHora': FieldValue.serverTimestamp(),
                'status': 'pago',
                'pedidoPendenteId': pedidoId,
              },
            );
          } catch (e, st) {
            logE('⚠️ Erro ao salvar pedido finalizado (webhook path) (type=${e.runtimeType})',
                error: e, st: st);
          }
          await pedidoDoc.reference.update({
            'status': 'pago',
            'vendaRegistrada': true,
            'estoqueBaixado': true,
            'vendaId': nova.key.toString(),
            'vendaFirestoreId': canonicalId,
            'dataFinalizacao': FieldValue.serverTimestamp(),
          });
          return nova.key.toString();
        }
      }

      // 2. Extrair dados do pedido
      final customer = pedido['cliente'] as Map<String, dynamic>;
      final itens = (pedido['itens'] as List).cast<Map<String, dynamic>>();
      final frete = pedido['frete'] as Map<String, dynamic>;
      final subtotal = (pedido['subtotal'] as num).toDouble();
      final total = (pedido['total'] as num).toDouble();
      final desconto = (pedido['desconto'] as num?)?.toDouble() ?? 0.0;
      final pagamento = pedido['pagamento'] as String;
      final observacao = (pedido['observacao'] ?? '') as String;
      final cupom = pedido['cupom'] as Map<String, dynamic>?;
      final cupomRoleta = pedido['cupomRoleta'] as Map<String, dynamic>?;
      final premioRoleta = pedido['premioRoleta'] as Map<String, dynamic>?;

      // 3. Criar/Buscar cliente
      final clienteBox = await Hive.openBox<Cliente>(HiveBoxNames.clientes(lojaId));
      Cliente? cliente;

      final telefone = (customer['telefone'] ?? '').toString().trim();
      final email = (customer['email'] ?? '').toString().trim();

      for (final c in clienteBox.values) {
        if (c.lojaId == lojaId) {
          if ((email.isNotEmpty && c.email == email) ||
              (telefone.isNotEmpty && c.telefone == telefone)) {
            cliente = c;
            break;
          }
        }
      }

      if (cliente == null) {
        cliente = Cliente(
          nome: (customer['nome'] ?? '').toString(),
          telefone: telefone,
          instagram: '',
          email: email,
          endereco: (customer['enderecoFormatado'] ?? '').toString(),
          cep: '',
          cidade: '',
          lojaId: lojaId,
        );
        await clienteBox.add(cliente);

        try {
          await ClientesFirestoreService.syncCliente(cliente, lojaId: lojaId);
        } catch (e, st) {
          logE('⚠️ Erro ao sincronizar cliente (type=${e.runtimeType})', error: e, st: st);
        }
      }

      // 4. AGORA SIM: Baixar estoque via transação Firestore (atômico)
      final produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
      final vendaItens = <VendaItem>[];

      final itemsParaEstoque = _expandirItemsParaEstoque(
        items: itens,
        produtosBox: produtosBox,
        lojaId: lojaId,
      );
      if (itemsParaEstoque.isEmpty) {
        throw Exception('Nenhum item válido para baixa de estoque');
      }

      final txResults = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: lojaId,
        itens: itemsParaEstoque,
      );

      await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(lojaId, txResults);

      for (final result in txResults) {
        await EstoqueTransactionService.atualizarHiveAposTransacao(
          produtosBox: produtosBox,
          lojaId: lojaId,
          result: result,
        );
      }

      final txResultsComboCapFinal =
          await ComboKitStockService.aplicarTetoEstoqueComboAposBaixa(
        lojaId: lojaId,
        produtosBox: produtosBox,
        produtoIdsDebitadosNaVenda:
            ComboKitStockService.produtoIdsDeResultadosBaixa(txResults),
      );

      await CatalogoWebAposEstoqueService.sincronizarAposResultadosTransacao(
        lojaId: lojaId,
        produtosBox: produtosBox,
        resultadosPrincipais: txResults,
        resultadosComboExtra: txResultsComboCapFinal,
      );

      for (final item in itens) {
        final nome = (item['nome'] ?? '').toString();
        final qtd = (item['quantidade'] as num).toInt();
        final tamanho = (item['tamanho'] ?? '').toString().trim();
        final cor = (item['cor'] ?? '').toString().trim();
        final resumoExtra =
            (item['variacaoExtraResumo'] ?? '').toString().trim();
        final pid = (item['productId'] ?? item['id'] ?? '').toString().trim();

        vendaItens.add(VendaItem(
          produtoNome: nome,
          quantidade: qtd,
          precoUnitario: (item['precoUnitario'] as num?)?.toDouble() ?? 0.0,
          tamanho: tamanho,
          cor: cor,
          lojaId: lojaId,
          productId: pid.isNotEmpty ? pid : null,
          variacaoExtraResumo: resumoExtra,
        ));
      }

      // 5. Definir valores de pagamento
      double pagamentoPix = 0.0;
      double pagamentoCartao = 0.0;
      double pagamentoDinheiro = 0.0;

      switch (pagamento.toUpperCase()) {
        case 'PIX':
          pagamentoPix = total;
          break;
        case 'CARTÃO':
        case 'CARTAO':
        case 'MERCADO PAGO':
          pagamentoCartao = total;
          break;
        case 'DINHEIRO':
          pagamentoDinheiro = total;
          break;
        default:
          pagamentoPix = total;
      }

      // 6. Criar venda
      final freteValor = (frete['valor'] as num?)?.toDouble() ?? 0.0;
      final venda = Venda(
        preco: subtotal,
        total: total,
        desconto: subtotal > 0 ? (desconto / subtotal * 100).clamp(0, 100) : 0,
        clienteNome: cliente.nome,
        produtosDescricao: gerarDescricaoProdutosFromItens(itens),
        quantidade: itens.fold<int>(0, (prev, item) => prev + ((item['quantidade'] as num?)?.toInt() ?? 1)),
        data: DateTime.now(),
        vendedor: 'Loja online',
        observacao: observacao,
        tamanho: '',
        frete: freteValor,
        lojaId: lojaId,
        itens: vendaItens,
        formasPagamento: pagamento,
        pagamentoPix: pagamentoPix,
        pagamentoCartao: pagamentoCartao,
        pagamentoDinheiro: pagamentoDinheiro,
      );

      venda.custoProdutos = VendaCustoMercadoria.custoMercadoriaDesdeItensCatalogo(
        items: itens,
        produtosBox: produtosBox,
        lojaId: lojaId,
        subtotalParaFallbackHeuristica: subtotal,
      );
      final uMercFin = VendaCustoMercadoria.unidadesMercadoriaDesdeItensCatalogo(
        items: itens,
        produtosBox: produtosBox,
        lojaId: lojaId,
      );
      venda.taxas = VendaCustoMercadoria.taxasLegadoVendaApk(
        custoMercadoria: venda.custoProdutos,
        unidadesMercadoria: uMercFin > 0 ? uMercFin : venda.quantidade,
      );
      venda.paymentId = paymentIdStr.isNotEmpty ? paymentIdStr : null;
      venda.prePedidoId = pedidoId;
      venda.orderId = pedidoId;
      venda.origemVenda = 'catalogo_web';
      venda.statusVenda = 'concluida';

      // 7. Salvar venda no Hive
      final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
      await vendasBox.add(venda);

      // 7b. Denormalizar vendas no doc do produto (catálogo / "Mais vendidos") — não bloqueia o fluxo
      try {
        await ProdutoVendasCatalogoDenormService.incrementarAposVendaCatalogo(
          lojaId: lojaId,
          items: itens,
          produtosBox: produtosBox,
        );
      } catch (e, st) {
        logE(
          '⚠️ [VENDAS_CATALOGO_DENORM] Não crítico após finalizarPedidoComPagamento (type=${e.runtimeType})',
          error: e,
          st: st,
        );
      }

      // 8. Adicionar ao histórico do cliente
      // ignore: experimental_member_use
      cliente.historico ??= HiveList(vendasBox);
      cliente.historico!.add(venda);
      await cliente.save();

      // 9. Sincronizar venda com Firestore
      logD('📤 [SYNC-DEBUG] CatalogoVendaService (confirmarPagamento) → lojaId=$lojaId | cliente=${venda.clienteNome} | total=R\$${venda.total.toStringAsFixed(2)}');
      try {
        final ok = await VendasFirestoreService.syncVenda(venda, lojaId: lojaId);
        if (!ok) {
          logW('⚠️ CatalogoVendaService(confirmarPagamento): venda não sincronizada com Firestore (lojaId=$lojaId, key=${venda.key})');
        }
      } catch (e, st) {
        logE('⚠️ Erro inesperado ao sincronizar venda (type=${e.runtimeType})', error: e, st: st);
      }

      // 10. Salvar em pedidos finalizados
      try {
        await _pedidoRepository.createPedido(
          flowType: PedidoFlowType.pedidos,
          lojaId: lojaId,
          data: {
          'tipo': 'catalogo_web',
          'lojaId': lojaId,
          'vendaId': venda.key.toString(),
          'cliente': customer,
          'itens': itens,
          'subtotal': subtotal,
          'frete': frete,
          'cupom': cupom,
          'cupomRoleta': cupomRoleta,
          'premioRoleta': premioRoleta != null
              ? {
                  ...premioRoleta,
                  'status': 'ativo',
                  'valido': true,
                  'dataAtivacao': FieldValue.serverTimestamp(),
                }
              : null,
          'total': total,
          'pagamento': pagamento,
          'observacao': observacao,
          'dataHora': FieldValue.serverTimestamp(),
          'status': 'pago', // ✅ Status confirmado
          'pedidoPendenteId': pedidoId,
          },
        );
      } catch (e, st) {
        logE('⚠️ Erro ao salvar pedido finalizado (type=${e.runtimeType})', error: e, st: st);
      }

      // 11. Atualizar pedido pendente como processado
      await pedidoDoc.reference.update({
        'status': 'pago',
        'vendaRegistrada': true,
        'estoqueBaixado': true,
        'vendaId': venda.key.toString(),
        'dataFinalizacao': FieldValue.serverTimestamp(),
      });

      // 12. 🎯 NOVO: Registrar participação em campanha de sorteio
      try {
        final nomeLoja = await _obterNomeLoja(lojaId);
        final resultado = await CampaignEngineService.onVendaConcluida(
          lojaId: lojaId,
          venda: venda,
          vendaId: venda.key.toString(),
          clienteNome: cliente.nome,
          clienteId: cliente.key?.toString(),
          telefone: telefone,
          email: email,
          valorTotal: total,
          origem: 'catalogo',
          nomeLoja: nomeLoja,
        );

        if (resultado.sucesso) {
          logD('🎫 [CATÁLOGO] Número da sorte gerado: ${resultado.numero}');
        } else if (resultado.erro != null) {
          logD('ℹ️ [CATÁLOGO] Campanha: ${resultado.erro}');
        }
      } catch (e, st) {
        logE('⚠️ [CATÁLOGO] Erro ao registrar campanha (não crítico) (type=${e.runtimeType})', error: e, st: st);
        // Não quebra o fluxo se falhar
      }

      logD('✅ Pedido finalizado com sucesso: $pedidoId -> Venda: ${venda.key}');

      // 🎉 Notificar admin sobre pedido PAGO (com entusiasmo!)
      final clienteNome = (customer['nome'] ?? '').toString();
      await NotificacaoVendasService().notificarAdminNovaVenda(
        storeId: lojaId,
        pedidoId: pedidoId,
        clienteNome: clienteNome.isNotEmpty ? clienteNome : 'Cliente',
        valorTotal: total,
        origem: 'catalogo_web',
        vendedorNome: (pedido['vendedorNome'] ?? '').toString().isEmpty ? null : (pedido['vendedorNome'] as String?),
        pagamentoConfirmado: true,
      );

      return venda.key.toString();
    } catch (e, st) {
      logE('❌ Erro ao finalizar pedido com pagamento (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  /// Cancela um pedido pendente (não baixa estoque pois nunca foi baixado)
  ///
  /// [lojaId] - ID da loja
  /// [pedidoId] - ID do pedido pendente
  static Future<bool> cancelarPedidoPendente({
    required String lojaId,
    required String pedidoId,
  }) async {
    try {
      await _pedidoRepository.updatePedido(
        flowType: PedidoFlowType.pedidosPendentes,
        lojaId: lojaId,
        pedidoId: pedidoId,
        data: {
        'status': 'cancelado',
        'dataCancelamento': FieldValue.serverTimestamp(),
        },
      );

      logD('✅ Pedido pendente cancelado: $pedidoId');
      return true;
    } catch (e, st) {
      logE('❌ Erro ao cancelar pedido pendente (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Lista pedidos pendentes de uma loja
  static Future<List<Map<String, dynamic>>> listarPedidosPendentes({
    required String lojaId,
  }) async {
    try {
      final snapshot = await _pedidoRepository.querySnapshot(
        flowType: PedidoFlowType.pedidosPendentes,
        lojaId: lojaId,
        buildQuery: (query) => query
            .where('status', isEqualTo: 'aguardando_pagamento')
            .orderBy('dataHora', descending: true),
      );

      return snapshot.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
    } catch (e, st) {
      logE('❌ Erro ao listar pedidos pendentes (type=${e.runtimeType})', error: e, st: st);
      return [];
    }
  }

  /// Busca o nome amigável da loja no Firestore.
  /// Ordem: lojas/{lojaId}, lojas/{lojaId}/config/config.
  static Future<String> _obterNomeLoja(String lojaId) async {
    try {
      final db = FirebaseFirestore.instance;
      final lojaDoc = await db.collection('lojas').doc(lojaId).get();
      if (lojaDoc.exists) {
        final d = lojaDoc.data() ?? {};
        final nome = (d['nome_loja'] ?? d['nomeLoja'] ?? d['nome'] ?? d['name'] ?? '').toString().trim();
        if (nome.isNotEmpty) return nome;
      }
      final configDoc = await db.collection('lojas').doc(lojaId).collection('config').doc('config').get();
      if (configDoc.exists) {
        final d = configDoc.data() ?? {};
        final nome = (d['nome_loja'] ?? d['nomeLoja'] ?? d['nome'] ?? d['name'] ?? '').toString().trim();
        if (nome.isNotEmpty) return nome;
      }
    } catch (e, st) {
      logE('⚠️ Erro ao buscar nome da loja (type=${e.runtimeType})', error: e, st: st);
    }
    return lojaId;
  }

}
