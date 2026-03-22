// lib/screens/pagamento_resultado_screen.dart
// Tela exibida após retorno do Mercado Pago (sucesso, falha ou pendente)

import 'package:flutter/material.dart';

class PagamentoResultadoScreen extends StatelessWidget {
  final String status; // 'sucesso' | 'falha' | 'pendente'
  final String? orderId;
  final String? lojaId;
  final String? planoId;

  /// Query do MP (quando presente): approved / pending / etc.
  final String? collectionStatus;

  /// Query genérica `status` do retorno (ex.: approved).
  final String? paymentStatusQuery;

  /// `external_reference` do pagamento (ex.: id do pré-pedido).
  final String? externalReference;

  const PagamentoResultadoScreen({
    super.key,
    required this.status,
    this.orderId,
    this.lojaId,
    this.planoId,
    this.collectionStatus,
    this.paymentStatusQuery,
    this.externalReference,
  });

  @override
  Widget build(BuildContext context) {
    final isSuccess = status == 'sucesso';
    final isPending = status == 'pendente';
    final isPlano = planoId != null && planoId!.isNotEmpty;

    final cs = collectionStatus?.toLowerCase().trim();
    final ps = paymentStatusQuery?.toLowerCase().trim();
    final mpApproved = cs == 'approved' || ps == 'approved';
    final mpPending = cs == 'pending' ||
        cs == 'in_process' ||
        cs == 'in_mediation' ||
        ps == 'pending';

    final successExplicitPending = isSuccess && mpPending;
    final successExplicitApproved = isSuccess && mpApproved;

    final refPedido = (externalReference?.trim().isNotEmpty == true)
        ? externalReference!.trim()
        : (orderId?.trim().isNotEmpty == true)
            ? orderId!.trim()
            : null;

    final icon = isSuccess
        ? (successExplicitPending ? Icons.schedule : Icons.check_circle)
        : isPending
            ? Icons.schedule
            : Icons.error;
    final color = isSuccess
        ? (successExplicitPending ? Colors.orange : Colors.green)
        : isPending
            ? Colors.orange
            : Colors.red;

    final String title;
    if (isPlano) {
      title = isSuccess
          ? 'Assinatura confirmada!'
          : isPending
              ? 'Pagamento pendente'
              : 'Pagamento não realizado';
    } else if (isSuccess) {
      if (successExplicitPending) {
        title = 'Pagamento pendente';
      } else if (successExplicitApproved) {
        title = 'Pagamento aprovado!';
      } else {
        title = 'Pagamento recebido';
      }
    } else if (isPending) {
      title = 'Pagamento pendente';
    } else {
      title = 'Pagamento não realizado';
    }

    final String message;
    if (isPlano) {
      message = isSuccess
          ? 'Seu plano foi ativado com sucesso! O webhook irá confirmar em instantes. Você já pode usar todos os recursos.'
          : isPending
              ? 'Seu pagamento está em análise. O plano será ativado automaticamente quando for aprovado.'
              : 'O prazo para pagar pode ter expirado, o pagamento pode ter sido recusado ou reembolsado. Tente novamente ou escolha outra forma de pagamento.';
    } else if (isSuccess) {
      if (successExplicitPending) {
        message =
            'Seu pagamento está em análise. Você receberá a confirmação quando for aprovado. Acompanhe seu pedido na aba "Meus Pedidos" do seu perfil.';
      } else if (successExplicitApproved) {
        message =
            'Obrigado pela sua compra! Seu pagamento foi confirmado. Você receberá a confirmação por e-mail ou WhatsApp. Acompanhe seu pedido na aba "Meus Pedidos" do seu perfil.';
      } else {
        message =
            'Obrigado! Recebemos o retorno do pagamento. Se a cobrança foi aprovada, você receberá a confirmação em instantes. Acompanhe seu pedido na aba "Meus Pedidos" do seu perfil.';
      }
    } else if (isPending) {
      message =
          'Seu pagamento está em análise. Você receberá a confirmação quando for aprovado.';
    } else {
      message =
          'O prazo para pagar pode ter expirado, o pagamento pode ter sido recusado ou reembolsado. Tente novamente ou escolha outra forma de pagamento.';
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 80, color: color),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                if (refPedido != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Referência: $refPedido',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
                if (isPlano)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                      '/home',
                      (route) => false,
                    ),
                    icon: const Icon(Icons.home),
                    label: const Text('Ir para o app'),
                  )
                else if (lojaId != null && lojaId!.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                      '/loja/${lojaId!}',
                      (route) => false,
                    ),
                    icon: const Icon(Icons.storefront),
                    label: const Text('Voltar ao catálogo'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
