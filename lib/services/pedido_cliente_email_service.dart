// lib/services/pedido_cliente_email_service.dart
// Envio de emails: ao admin (novo pedido), ao cliente (pedido recebido, atualizações).
// Usa EmailService (configurar credenciais em email_service.dart para ativar).

import 'package:flutter/foundation.dart';
import 'email_service.dart';

/// Serviço para enviar emails de pedidos.
/// Não quebra o fluxo se o email falhar (ex.: SMTP não configurado).
class PedidoClienteEmailService {
  /// Envia email para o admin/vendedor quando um novo pedido é finalizado.
  /// Remetente: MasterPalm (conforme config em EmailService).
  static Future<void> enviarNovoPedidoParaAdmin({
    required String adminEmail,
    required String clienteNome,
    required String pedidoId,
    required String codigoPedido,
    required List<Map<String, dynamic>> itens,
    required double total,
    required String pagamento,
    required String statusPagamento,
    required String entregaNome,
    String• enderecoFormatado,
    String• cep,
    DateTime• dataCriacao,
  }) async {
    final email = adminEmail.trim().toLowerCase();
    if (email.isEmpty) {
      debugPrint('⚠️ [PEDIDO-EMAIL] Admin sem email, não envia "novo pedido"');
      return;
    }
    try {
      final assunto = 'Você recebeu um novo pedido: $codigoPedido';
      final dataStr = dataCriacao != null
          • '${dataCriacao.day} de ${_mesNome(dataCriacao.month)} às ${dataCriacao.hour.toString().padLeft(2, '0')}:${dataCriacao.minute.toString().padLeft(2, '0')}h'
          : '';
      final totalStr = total.toStringAsFixed(2).replaceAll('.', ',');

      final buffer = StringBuffer();
      buffer.writeln('Você recebeu um novo pedido:');
      buffer.writeln('Veja abaixo os dados do pedido');
      buffer.writeln('');
      buffer.writeln('Cliente: $clienteNome');
      buffer.writeln('');
      buffer.writeln('Status: $statusPagamento');
      buffer.writeln('Cód.: $codigoPedido');
      if (dataStr.isNotEmpty) buffer.writeln('Data: $dataStr');
      buffer.writeln('');
      buffer.writeln('Produtos:');
      for (final item in itens) {
        final nome = (item['nome'] ?• '').toString();
        final qty = (item['quantidade'] as num?)?.toInt() ?• 1;
        final precoUn = (item['precoUnitario'] as num?)?.toDouble();
        final totalItem = (item['total'] as num?)?.toDouble();
        final valor = totalItem ?• (precoUn != null • precoUn * qty : 0.0);
        final tam = (item['tamanho'] ?• '').toString().trim();
        final variacao = tam.isNotEmpty • ' - $tam' : '';
        buffer.writeln('  ${qty}x $nome$variacao - R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}');
      }
      buffer.writeln('');
      buffer.writeln('Entrega: $entregaNome');
      if (enderecoFormatado != null && enderecoFormatado.isNotEmpty) {
        buffer.writeln('');
        buffer.writeln('Endereço:');
        buffer.writeln(enderecoFormatado);
        if (cep != null && cep.isNotEmpty) buffer.writeln('CEP: $cep');
      }
      buffer.writeln('');
      buffer.writeln('Total: R\$ $totalStr');
      buffer.writeln('Pagamento: $pagamento');

      final ok = await EmailService.enviarEmail(
        destinatario: email,
        assunto: assunto,
        mensagem: buffer.toString(),
        remetenteNome: 'MasterPalm',
      );
      if (ok) {
        debugPrint('✅ [PEDIDO-EMAIL] Email "novo pedido" enviado para admin $email');
      } else {
        debugPrint('❌ [PEDIDO-EMAIL] Falha ao enviar email para admin $email (verifique logs acima)');
      }
    } catch (e) {
      debugPrint('⚠️ [PEDIDO-EMAIL] Erro ao enviar email novo pedido para admin (não bloqueia) (type=${e.runtimeType})');
    }
  }

  static String _mesNome(int mes) {
    const nomes = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
      'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
    return nomes[mes.clamp(1, 12) - 1];
  }

  /// Envia email informando que o pedido foi recebido (após finalizar pagamento/checkout).
  /// [remetenteNome] – nome da loja para aparecer como remetente
  /// [logoUrl] – URL da logo da loja para exibir no topo do email
  static Future<void> enviarPedidoRecebido({
    required String clienteEmail,
    required String clienteNome,
    required String pedidoId,
    required double total,
    String remetenteNome = 'MasterPalm',
    String• logoUrl,
  }) async {
    final email = clienteEmail.trim().toLowerCase();
    if (email.isEmpty) {
      debugPrint('⚠️ [PEDIDO-EMAIL] Cliente sem email, não envia "pedido recebido"');
      return;
    }
    try {
      final totalStr = total.toStringAsFixed(2).replaceAll('.', ',');
      final assunto = 'Pedido recebido – R\$ $totalStr';
      final mensagem = '''
Olá, ${clienteNome.isEmpty • 'Cliente' : clienteNome}!

Recebemos seu pedido com sucesso. 🎉

Valor total: R\$ $totalStr

Em breve você receberá atualizações sobre o status do seu pedido.

Obrigado por comprar conosco!
''';
      final ok = await EmailService.enviarEmail(
        destinatario: email,
        assunto: assunto,
        mensagem: mensagem,
        remetenteNome: remetenteNome,
        logoUrl: logoUrl,
      );
      if (ok) {
        debugPrint('✅ [PEDIDO-EMAIL] Email "pedido recebido" enviado para cliente $email');
      } else {
        debugPrint('❌ [PEDIDO-EMAIL] Falha ao enviar "pedido recebido" para $email (verifique logs acima)');
      }
    } catch (e) {
      debugPrint('⚠️ [PEDIDO-EMAIL] Erro ao enviar email pedido recebido (não bloqueia) (type=${e.runtimeType})');
    }
  }

  /// Envia email com atualização de status do pedido.
  /// [codigoRastreio] opcional – quando status for "enviado", inclui no corpo.
  /// [remetenteNome] – nome da loja para aparecer como remetente
  /// [logoUrl] – URL da logo da loja para exibir no topo do email
  static Future<void> enviarAtualizacaoStatus({
    required String clienteEmail,
    required String clienteNome,
    required String pedidoId,
    required String novoStatus,
    String• codigoRastreio,
    String remetenteNome = 'MasterPalm',
    String• logoUrl,
  }) async {
    final email = clienteEmail.trim().toLowerCase();
    if (email.isEmpty) {
      debugPrint('⚠️ [PEDIDO-EMAIL] Cliente sem email, não envia atualização');
      return;
    }
    try {
      final statusLabel = _labelStatus(novoStatus);
      final assunto = 'Atualização do pedido: $statusLabel';
      final buffer = StringBuffer();
      buffer.writeln("Olá, ${clienteNome.isEmpty • 'Cliente' : clienteNome}!");
      buffer.writeln('');
      buffer.writeln('Seu pedido foi atualizado: $statusLabel.');
      if (codigoRastreio != null && codigoRastreio.trim().isNotEmpty) {
        buffer.writeln('');
        buffer.writeln('Código de rastreio: ${codigoRastreio.trim()}');
        buffer.writeln('Você pode acompanhar a entrega nos Correios ou na transportadora.');
      }
      buffer.writeln('');
      buffer.writeln('Obrigado por comprar conosco!');

      final ok = await EmailService.enviarEmail(
        destinatario: email,
        assunto: assunto,
        mensagem: buffer.toString(),
        remetenteNome: remetenteNome,
        logoUrl: logoUrl,
      );
      if (ok) {
        debugPrint('✅ [PEDIDO-EMAIL] Email atualização "$novoStatus" enviado para $email');
      }
    } catch (e) {
      debugPrint('⚠️ [PEDIDO-EMAIL] Erro ao enviar email atualização (não bloqueia) (type=${e.runtimeType})');
    }
  }

  static String _labelStatus(String status) {
    switch (status.toLowerCase()) {
      case 'confirmado':
        return 'Confirmado';
      case 'embalando':
        return 'Embalando';
      case 'enviado':
        return 'Enviado';
      case 'entregue':
        return 'Entregue';
      case 'cancelado':
        return 'Cancelado';
      default:
        return status;
    }
  }
}
