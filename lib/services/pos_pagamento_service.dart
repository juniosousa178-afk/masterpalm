// lib/services/pos_pagamento_service.dart

import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../repositories/pedido_repository.dart';
import '../core/hive_box_names.dart';
import '../models/venda.dart';
import '../models/produto.dart';
import 'catalogo_venda_service.dart';
import 'estoque_transaction_service.dart';
import 'firestore_paths.dart';
import 'pedido_collection_resolver.dart';
import 'sorteio_numero_service.dart';

/// Serviço para processar ações após confirmação de pagamento
///
/// Funcionalidades:
/// - Baixa de estoque
/// - Atualização de status da venda
/// - Geração de número da sorte
/// - Envio de notificações (Email e WhatsApp)
/// - Integração com cupom da roleta
class PosPagamentoService {
  static final PedidoRepository _pedidoRepository = PedidoRepository();

  /// Processa todas as ações após confirmação de pagamento
  ///
  /// Este método deve ser chamado quando:
  /// - Webhook do Mercado Pago confirma pagamento (status: approved)
  /// - Webhook de outras gateways confirma pagamento
  /// - Admin confirma pagamento manual
  ///
  /// [lojaId] - ID da loja
  /// [vendaId] - Key da venda no Hive
  /// [customer] - Dados do cliente (nome, email, telefone)
  /// [items] - Lista de itens vendidos
  /// [valorTotal] - Valor total da compra
  /// [formaPagamento] - Forma de pagamento (PIX, CARTÃO, etc)
  /// [cupomRoletaCodigo] - Código do cupom ganho na roleta (se houver)
  /// [cupomRoletaDesconto] - Desconto do cupom da roleta (%)
  static Future<bool> processarConfirmacaoPagamento({
    required String lojaId,
    required String vendaId,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> items,
    required double valorTotal,
    required String formaPagamento,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
  }) async {
    try {
      debugPrint(
        '🎯 [PÓS-PAGAMENTO] Iniciando processamento para venda: $vendaId | lojaId=$lojaId | valorTotal=$valorTotal',
      );

      final firestore = FirebaseFirestore.instance;
      final baixaRef = firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_baixa_pagamento')
          .doc(vendaId);

      final baixaSnap = await baixaRef.get();
      final data = baixaSnap.data();
      final baixaJaAplicada = baixaSnap.exists && (data?['baixaAplicada'] == true);
      final efeitosJaProcessados = baixaSnap.exists && (data?['posPagamentoProcessado'] == true);

      if (baixaJaAplicada && efeitosJaProcessados) {
        debugPrint(
          'ℹ️ [PÓS-PAGAMENTO] Requisição idempotente detectada; baixa e efeitos já processados. '
          'lojaId=$lojaId, vendaId=$vendaId',
        );
        return true;
      }

      if (baixaJaAplicada) {
        debugPrint(
          'ℹ️ [ESTOQUE_BAIXA] Baixa já aplicada anteriormente; pulando nova baixa. lojaId=$lojaId, vendaId=$vendaId',
        );
      } else {
        debugPrint(
          '🔁 [ESTOQUE_BAIXA] Iniciando baixa transacional de estoque via pós-pagamento. lojaId=$lojaId, vendaId=$vendaId, itens=${items.length}',
        );

        // 1. Baixar estoque dos produtos (regra: baixa antes de marcar como pago)
        await _baixarEstoque(lojaId, items);

        await baixaRef.set({
          'baixaAplicada': true,
          'lojaId': lojaId,
          'vendaId': vendaId,
          'origem': 'pos_pagamento',
          'valorTotal': valorTotal,
          'quantidadeItens': items.length,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        debugPrint(
          '✅ [ESTOQUE_BAIXA] Baixa registrada como aplicada. lojaId=$lojaId, vendaId=$vendaId',
        );
      }

      // 2. Atualizar status da venda para "pago"
      await _atualizarStatusVenda(lojaId, vendaId);

      // 3. Gerar número da sorte
      final numeroSorte = _gerarNumeroSorte();
      await _salvarNumeroSorte(
        lojaId: lojaId,
        vendaId: vendaId,
        numeroSorte: numeroSorte,
        customer: customer,
        valorTotal: valorTotal,
      );

      // 3.1. Registrar número na campanha ativa (mesmo fluxo da nova venda)
      await SorteioNumeroService.registrarNumeroEmCampanhas(
        lojaId: lojaId,
        clienteNome: customer['nome']?.toString() ?? 'Cliente',
        clienteId: customer['id']?.toString() ?? customer['clienteId']?.toString(),
        valorCompra: valorTotal,
        dataCompra: DateTime.now(),
        numeroSorte: numeroSorte,
      );

      // 4. Ativar prêmio da roleta (se houver)
      await _ativarPremioRoleta(
        lojaId: lojaId,
        vendaId: vendaId,
      );

      // 5. Enviar notificações (Email e WhatsApp)
      await _enviarNotificacoes(
        lojaId: lojaId,
        vendaId: vendaId,
        customer: customer,
        numeroSorte: numeroSorte,
        cupomRoletaCodigo: cupomRoletaCodigo,
        cupomRoletaDesconto: cupomRoletaDesconto,
        valorTotal: valorTotal,
      );

      try {
        await baixaRef.set({
          'posPagamentoProcessado': true,
          'posPagamentoProcessadoAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint(
          '✅ [PÓS-PAGAMENTO] Marcado posPagamentoProcessado=true para vendaId=$vendaId | lojaId=$lojaId',
        );
      } catch (e) {
        debugPrint(
          '⚠️ [PÓS-PAGAMENTO] Falha ao marcar posPagamentoProcessado (type=${e.runtimeType}) '
          '| lojaId=$lojaId | vendaId=$vendaId',
        );
      }

      debugPrint('✅ [PÓS-PAGAMENTO] Processamento concluído com sucesso!');
      return true;
    } catch (e) {
      debugPrint(
        '❌ [PÓS-PAGAMENTO] Erro ao processar (type=${e.runtimeType}) | lojaId=$lojaId | vendaId=$vendaId',
      );
      return false;
    }
  }

  /// Envia apenas as notificações de número da sorte (Email e WhatsApp) ao cliente.
  /// Usado após nova venda no APK, quando o número já foi gerado e registrado na campanha.
  /// [vendaId] pode ser o key da venda no Hive ou um identificador (ex: 'nova-venda').
  static Future<void> enviarNotificacaoNumeroSorte({
    required String lojaId,
    required String vendaId,
    required Map<String, dynamic> customer,
    required String numeroSorte,
    required double valorTotal,
  }) async {
    await _enviarNotificacoes(
      lojaId: lojaId,
      vendaId: vendaId,
      customer: customer,
      numeroSorte: numeroSorte,
      cupomRoletaCodigo: null,
      cupomRoletaDesconto: null,
      valorTotal: valorTotal,
    );
  }

  /// Atualiza o status da venda para "pago"
  static Future<void> _atualizarStatusVenda(String lojaId, String vendaId) async {
    try {
      // Atualizar no serviço de catálogo
      await CatalogoVendaService.atualizarStatusPedido(
        lojaId: lojaId,
        vendaId: vendaId,
        status: 'pago',
      );

      // FASE 3: Box por loja (HiveBoxNames.vendas(lojaId)) — lojaId já recebido no fluxo
      final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
      final key = int.tryParse(vendaId);
      final venda = key != null ? vendasBox.get(key) : vendasBox.get(vendaId);
      if (venda != null) {
        venda.observacao = '${venda.observacao}\n[PAGO em ${DateTime.now()}]';
        await venda.save();
      }
      if (kDebugMode) debugPrint('📌 [HIVE_BOX] pos_pagamento vendasBox lojaId=$lojaId');

      debugPrint('✅ Status da venda atualizado para: pago');
    } catch (e) {
      debugPrint('❌ Erro ao atualizar status da venda (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// Baixa o estoque dos produtos vendidos via transação Firestore (atômico)
  static Future<void> _baixarEstoque(String lojaId, List<Map<String, dynamic>> items) async {
    final txItems = <Map<String, dynamic>>[];
    for (final item in items) {
      final productId = item['productId']?.toString();
      final qty = (item['qty'] as int?) ?? (item['quantidade'] as int?) ?? 1;

      if (productId == null || productId.isEmpty) {
        debugPrint(
          '⚠️ [ESTOQUE_BAIXA] Item sem productId, pulando baixa de estoque. lojaId=$lojaId, nome=${item['name'] ?? item['nome']}',
        );
        continue;
      }
      if (qty <= 0) continue;

      txItems.add({
        'productId': productId,
        'nome': item['name'] ?? item['nome'] ?? '',
        'quantidade': qty,
        'tamanho': (item['tamanho'] ?? item['size'] ?? '').toString().trim(),
        'cor': (item['cor'] ?? item['color'] ?? '').toString().trim(),
      });
    }

    if (txItems.isEmpty) {
      debugPrint(
        '⚠️ [ESTOQUE_BAIXA] Nenhum item válido para baixa de estoque. lojaId=$lojaId',
      );
      throw Exception(
        'Nenhum item válido para baixa de estoque (productId ausente ou quantidade inválida). '
        'Não é possível confirmar o pagamento sem baixar o estoque.',
      );
    }

    final txResults = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
      lojaId: lojaId,
      itens: txItems,
    );

    await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(lojaId, txResults);

    try {
      final produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
      for (final result in txResults) {
        await EstoqueTransactionService.atualizarHiveAposTransacao(
          produtosBox: produtosBox,
          lojaId: lojaId,
          result: result,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ [HIVE_BOX] pos_pagamento: Hive indisponível ao atualizar após transação (type=${e.runtimeType}) | lojaId=$lojaId',
        );
      }
    }

    debugPrint(
      '✅ [ESTOQUE_BAIXA] Estoque baixado com sucesso para todos os produtos. lojaId=$lojaId, itens=${txResults.length}',
    );
  }

  /// Gera um número da sorte aleatório de 5 dígitos
  static String _gerarNumeroSorte() {
    final random = Random();
    final numero = random.nextInt(90000) + 10000; // Gera entre 10000 e 99999
    return numero.toString();
  }

  /// Salva o número da sorte no Firestore
  static Future<void> _salvarNumeroSorte({
    required String lojaId,
    required String vendaId,
    required String numeroSorte,
    required Map<String, dynamic> customer,
    required double valorTotal,
  }) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Salvar número da sorte
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('numerosSorte')
          .add({
        'numero': numeroSorte,
        'vendaId': vendaId,
        'cliente': {
          'nome': customer['nome'],
          'email': customer['email'],
          'telefone': customer['telefone'],
        },
        'valorCompra': valorTotal,
        'dataGeracao': FieldValue.serverTimestamp(),
        'ativo': true,
      });

      // Atualizar o pedido com o número da sorte
      final pedidoRef = await _pedidoRepository.findFirstRefByField(
        flowType: PedidoFlowType.pedidos,
        lojaId: lojaId,
        field: 'vendaId',
        value: vendaId,
      );

      if (pedidoRef != null) {
        await pedidoRef.update({
          'numeroSorte': numeroSorte,
        });
      }

      debugPrint('🎲 Número da sorte gerado e salvo: $numeroSorte');
    } catch (e) {
      debugPrint('❌ Erro ao salvar número da sorte (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// Envia notificações por Email e WhatsApp
  static Future<void> _enviarNotificacoes({
    required String lojaId,
    required String vendaId,
    required Map<String, dynamic> customer,
    required String numeroSorte,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    required double valorTotal,
  }) async {
    try {
      final email = customer['email']?.toString();
      final telefone = customer['telefone']?.toString();
      final nome = customer['nome']?.toString() ?? 'Cliente';

      // Buscar configurações da loja
      final lojaDoc = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .get();

      if (!lojaDoc.exists) {
        debugPrint('⚠️ Loja não encontrada, pulando notificações');
        return;
      }

      final lojaData = lojaDoc.data()!;
      final lojaNome = lojaData['nome']?.toString() ?? 'Loja';

      // Enviar Email
      if (email != null && email.isNotEmpty) {
        await _enviarEmail(
          destinatario: email,
          assunto: '🎉 Parabéns! Você está concorrendo - $lojaNome',
          nome: nome,
          lojaNome: lojaNome,
          numeroSorte: numeroSorte,
          cupomRoletaCodigo: cupomRoletaCodigo,
          cupomRoletaDesconto: cupomRoletaDesconto,
          valorTotal: valorTotal,
        );
      }

      // Enviar WhatsApp (usa Cloud Function + config Canais Meta)
      if (telefone != null && telefone.isNotEmpty) {
        await _enviarWhatsApp(
          lojaId: lojaId,
          vendaId: vendaId,
          telefone: telefone,
          nome: nome,
          lojaNome: lojaNome,
          numeroSorte: numeroSorte,
          cupomRoletaCodigo: cupomRoletaCodigo,
          cupomRoletaDesconto: cupomRoletaDesconto,
          valorTotal: valorTotal,
        );
      }

      debugPrint('✅ Notificações enviadas com sucesso!');
    } catch (e) {
      debugPrint('❌ Erro ao enviar notificações (type=${e.runtimeType})');
      // Não lança exceção para não bloquear o fluxo
    }
  }

  /// Envia email com número da sorte
  static Future<void> _enviarEmail({
    required String destinatario,
    required String assunto,
    required String nome,
    required String lojaNome,
    required String numeroSorte,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    required double valorTotal,
  }) async {
    try {
      // Montar HTML do email
      final htmlBody = _montarEmailHtml(
        nome: nome,
        lojaNome: lojaNome,
        numeroSorte: numeroSorte,
        cupomRoletaCodigo: cupomRoletaCodigo,
        cupomRoletaDesconto: cupomRoletaDesconto,
        valorTotal: valorTotal,
      );

      // Enviar via Cloud Function ou serviço de email
      final projectId = Firebase.app().options.projectId;
      final response = await http.post(
        Uri.parse('https://southamerica-east1-$projectId.cloudfunctions.net/sendEmail'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'to': destinatario,
          'subject': assunto,
          'html': htmlBody,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('📧 Email enviado para: $destinatario');
      } else {
        debugPrint('❌ Erro ao enviar email: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Exceção ao enviar email (type=${e.runtimeType})');
    }
  }

  /// Monta o HTML do email
  static String _montarEmailHtml({
    required String nome,
    required String lojaNome,
    required String numeroSorte,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    required double valorTotal,
  }) {
    final temCupom = cupomRoletaCodigo != null && cupomRoletaCodigo.isNotEmpty;

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: Arial, sans-serif; background-color: #f4f4f4; margin: 0; padding: 20px; }
    .container { max-width: 600px; margin: 0 auto; background-color: #ffffff; border-radius: 10px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; }
    .header h1 { margin: 0; font-size: 28px; }
    .content { padding: 30px; }
    .numero-sorte { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); color: white; padding: 20px; border-radius: 10px; text-align: center; margin: 20px 0; }
    .numero-sorte h2 { margin: 0 0 10px 0; font-size: 18px; }
    .numero-sorte .numero { font-size: 48px; font-weight: bold; letter-spacing: 5px; }
    .cupom { background: #fff3cd; border: 2px dashed #ffc107; padding: 20px; border-radius: 10px; margin: 20px 0; text-align: center; }
    .cupom-codigo { font-size: 24px; font-weight: bold; color: #856404; letter-spacing: 2px; }
    .footer { background-color: #f8f9fa; padding: 20px; text-align: center; font-size: 12px; color: #6c757d; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🎉 Parabéns, $nome!</h1>
    </div>
    <div class="content">
      <p>Obrigado por sua compra de <strong>R\$ ${valorTotal.toStringAsFixed(2)}</strong> na <strong>$lojaNome</strong>!</p>

      <div class="numero-sorte">
        <h2>🎲 Seu Número da Sorte:</h2>
        <div class="numero">$numeroSorte</div>
      </div>

      <p style="text-align: center; color: #28a745; font-weight: bold;">
        ✅ Você está participando da nossa promoção!
      </p>

      <p>Seu número da sorte foi registrado e você está concorrendo a prêmios incríveis. Fique de olho no sorteio!</p>

      ${temCupom ? '''
      <div class="cupom">
        <h3 style="margin: 0 0 10px 0; color: #856404;">🎁 Você também ganhou na Roleta da Sorte!</h3>
        <p style="margin: 5px 0; color: #856404;">Cupom de desconto de <strong>${cupomRoletaDesconto?.toStringAsFixed(0)}%</strong> para sua próxima compra:</p>
        <div class="cupom-codigo">$cupomRoletaCodigo</div>
        <p style="margin: 10px 0 0 0; font-size: 12px; color: #856404;">
          📅 Válido por 60 dias | 🔄 Use na próxima compra
        </p>
      </div>
      ''' : ''}

      <p style="margin-top: 30px; text-align: center;">
        Obrigado por comprar conosco! 💜
      </p>
    </div>
    <div class="footer">
      <p>$lojaNome - Todos os direitos reservados</p>
      <p>Este é um email automático, por favor não responda.</p>
    </div>
  </div>
</body>
</html>
''';
  }

  /// Envia mensagem via WhatsApp (Cloud Function + config Canais Meta).
  /// Se existir pedido no Firestore (por vendaId), envia confirmação completa no formato
  /// tipo DELIGELI: saudação, nº pedido, itens, forma de pagamento, tempo de entrega, endereço, total e número da sorte.
  static Future<void> _enviarWhatsApp({
    required String lojaId,
    required String vendaId,
    required String telefone,
    required String nome,
    required String lojaNome,
    required String numeroSorte,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    required double valorTotal,
  }) async {
    try {
      final temCupom = cupomRoletaCodigo != null && cupomRoletaCodigo.isNotEmpty;

      // Tentar buscar pedido para montar mensagem de confirmação completa (formato tipo DELIGELI)
      String mensagem = '';
      try {
        final pedido = await _pedidoRepository.findFirstByField(
          flowType: PedidoFlowType.pedidos,
          lojaId: lojaId,
          field: 'vendaId',
          value: vendaId,
        );

        if (pedido != null) {
          final numeroPedido = pedido['id'].toString();
          final cliente = pedido['cliente'] as Map<String, dynamic>? ?? {};
          final itens = (pedido['itens'] as List<dynamic>?) ?? [];
          final formaPagamento = (pedido['pagamento'] ?? '') as String;
          final total = (pedido['total'] as num?)?.toDouble() ?? valorTotal;
          final endereco = (cliente['enderecoFormatado'] ?? cliente['endereco'] ?? '') as String;

          final itensLinhas = itens.map<String>((e) {
            final map = e as Map<String, dynamic>;
            final qtd = (map['quantidade'] as num?)?.toInt() ?? 1;
            final nomeItem = (map['nome'] ?? map['name'] ?? '') as String;
            return '➡ ${qtd}x $nomeItem';
          }).join('\n');

          const tempoEntregaPadrao = '45 - 60min';
          final formaPagamentoExibir = formaPagamento.isEmpty ? 'Não informado' : formaPagamento;

          mensagem = '''
Olá $nome, aqui é o atendente virtual da *${lojaNome.toUpperCase()}*.

Vim te avisar que seu pedido foi realizado com sucesso e já está em preparo. 😊
Fique tranquilo(a) que vou enviar as atualizações do status do seu pedido por aqui.

*Nº do pedido* $numeroPedido

*Itens:*
$itensLinhas

*Forma de pagamento:* $formaPagamentoExibir

*Tempo de entrega:* $tempoEntregaPadrao

*Local de entrega:* ${endereco.isEmpty ? 'Não informado' : endereco}

*Total do pedido:* R\$ ${total.toStringAsFixed(2).replaceAll('.', ',')}

---
🎲 *Seu Número da Sorte:* *$numeroSorte*
✅ Você está participando da nossa promoção!
${temCupom ? '''
🎁 *Cupom da Roleta:* *$cupomRoletaCodigo* (${cupomRoletaDesconto?.toStringAsFixed(0)}% OFF) - Válido por 60 dias.
''' : ''}
Obrigado por comprar conosco! 💜
''';
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('pos_pagamento: erro ao buscar pedido para mensagem (type=${e.runtimeType})');
        }
      }

      if (mensagem.isEmpty) {
        // Fallback: mensagem apenas com número da sorte (comportamento anterior)
        mensagem = '''
🎉 *Parabéns, $nome!*

Obrigado por sua compra na *$lojaNome*!

🎲 *Seu Número da Sorte:*
*$numeroSorte*

✅ Você está participando da nossa promoção!

${temCupom ? '''
🎁 *Você também ganhou na Roleta da Sorte!*

Cupom de *${cupomRoletaDesconto?.toStringAsFixed(0)}% OFF* para sua próxima compra:

*$cupomRoletaCodigo*

📅 Válido por 60 dias
🔄 Use na próxima compra
''' : ''}

Obrigado por comprar conosco! 💜
''';
      }

      // Enviar via Cloud Function que usa canais/whatsapp (WhatsApp Cloud API)
      final projectId = Firebase.app().options.projectId;
      final response = await http.post(
        Uri.parse('https://southamerica-east1-$projectId.cloudfunctions.net/sendWhatsAppOrderConfirmation'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'lojaId': lojaId,
          'phone': telefone,
          'message': mensagem,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('📱 WhatsApp enviado para: $telefone');
      } else {
        debugPrint('❌ Erro ao enviar WhatsApp: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Exceção ao enviar WhatsApp (type=${e.runtimeType})');
    }
  }

  /// ✅ Ativa o prêmio da roleta após confirmação de pagamento
  ///
  /// Esta função é chamada automaticamente após o pagamento ser confirmado.
  /// Ela marca o prêmio como "ativo" e "válido", permitindo seu uso na próxima compra.
  ///
  /// Para brindes: não há ativação, o brinde é entregue junto com o pedido
  /// Para cupons/frete grátis: são ativados e ficam válidos para próxima compra
  static Future<void> _ativarPremioRoleta({
    required String lojaId,
    required String vendaId,
  }) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Buscar o pedido
      final pedidoRef = await _pedidoRepository.findFirstRefByField(
        flowType: PedidoFlowType.pedidos,
        lojaId: lojaId,
        field: 'vendaId',
        value: vendaId,
      );

      if (pedidoRef == null) {
        debugPrint('⚠️ Pedido não encontrado, não há prêmio para ativar');
        return;
      }

      final pedidoData = (await pedidoRef.get()).data() ?? {};
      final premioRoleta = pedidoData['premioRoleta'] as Map<String, dynamic>?;

      if (premioRoleta == null) {
        debugPrint('ℹ️ Pedido não tem prêmio da roleta');
        return;
      }

      final tipo = premioRoleta['tipo']?.toString() ?? 'nenhum';

      if (tipo == 'nenhum') {
        debugPrint('ℹ️ Prêmio é do tipo "nenhum", não requer ativação');
        return;
      }

      // ✅ Ativar prêmio
      await pedidoRef.update({
        'premioRoleta.status': 'ativo',
        'premioRoleta.valido': true,
        'premioRoleta.dataAtivacao': FieldValue.serverTimestamp(),
      });

      // ✅ Se for cupom ou frete grátis, salvar no estoque_clientes (por telefone) e no perfil do catálogo (por email)
      if (tipo == 'desconto' || tipo == 'frete_gratis') {
        final clienteData = pedidoData['cliente'] as Map<String, dynamic>?;
        final telefone = (clienteData?['telefone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
        final email = (clienteData?['email'] ?? '').toString().trim().toLowerCase();

        if (telefone.isNotEmpty) {
          // 1) estoque_clientes (por telefone)
          final clienteRef = firestore
              .collection('lojas')
              .doc(lojaId)
              .collection('estoque_clientes')
              .doc(telefone);

          final clienteDoc = await clienteRef.get();

          if (clienteDoc.exists) {
            await clienteRef.update({
              'cuponsRoleta': FieldValue.arrayUnion([
                {
                  'codigo': premioRoleta['codigo'],
                  'tipo': tipo,
                  'valor': premioRoleta['valor'] ?? 0.0,
                  'descricao': premioRoleta['descricao'],
                  'dataGanho': premioRoleta['dataGanho'],
                  'dataAtivacao': FieldValue.serverTimestamp(),
                  'vendaOrigem': vendaId,
                  'usado': false,
                  'dataUso': null,
                }
              ]),
            });
            debugPrint('🎁 Cupom da roleta ativado (estoque_clientes): ${premioRoleta['codigo']}');
          }
        }

        // 2) Perfil do cliente no catálogo (clientes_catalogo por email) – para aparecer em "Meus Cupons"
        if (email.isNotEmpty) {
          final codigo = (premioRoleta['codigo'] ?? '').toString();
          if (codigo.isNotEmpty) {
            final dataExpiracao = DateTime.now().add(const Duration(days: 60));
            await firestore
                .collection('lojas')
                .doc(lojaId)
                .collection(FSPaths.clientesCatalogoCol)
                .doc(email)
                .collection('cupons')
                .doc(codigo)
                .set({
              'codigo': codigo,
              'descricao': premioRoleta['descricao'] ?? '',
              'tipo': tipo,
              'valor': (premioRoleta['valor'] as num?)?.toDouble() ?? 0.0,
              'dataGanho': premioRoleta['dataGanho'],
              'dataExpiracao': Timestamp.fromDate(dataExpiracao),
              'usado': false,
              'ativo': true,
              'origem': 'roleta_sorte',
            });
            debugPrint('🎁 Cupom da roleta salvo no perfil do cliente (catálogo): $codigo');
          }
        }
      }

      debugPrint('✅ Prêmio da roleta ativado: tipo=$tipo, código=${premioRoleta['codigo']}');
    } catch (e) {
      debugPrint('❌ Erro ao ativar prêmio da roleta (type=${e.runtimeType})');
      // Não lança exceção para não bloquear o fluxo principal
    }
  }
}
