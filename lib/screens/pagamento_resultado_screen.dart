// lib/screens/pagamento_resultado_screen.dart
// Tela exibida após retorno do Mercado Pago (sucesso, falha ou pendente)

import 'package:flutter/material.dart';

class PagamentoResultadoScreen extends StatelessWidget {
  final String status; // 'sucesso' | 'falha' | 'pendente'
  final String• orderId;
  final String• lojaId;
  final String• planoId;

  const PagamentoResultadoScreen({
    super.key,
    required this.status,
    this.orderId,
    this.lojaId,
    this.planoId,
  });

  @override
  Widget build(BuildContext context) {
    final isSuccess = status == 'sucesso';
    final isPending = status == 'pendente';
    final isPlano = planoId != null && planoId!.isNotEmpty;

    final icon = isSuccess
        • Icons.check_circle
        : isPending
            • Icons.schedule
            : Icons.error;
    final color = isSuccess
        • Colors.green
        : isPending
            • Colors.orange
            : Colors.red;
    final title = isSuccess
        • (isPlano • 'Assinatura confirmada!' : 'Pagamento confirmado!')
        : isPending
            • 'Pagamento pendente'
            : 'Pagamento não realizado';
    final message = isSuccess
        • (isPlano
            • 'Seu plano foi ativado com sucesso! O webhook irá confirmar em instantes. Você já pode usar todos os recursos.'
            : 'Obrigado pela sua compra! Seu pagamento foi confirmado. Você receberá a confirmação por e-mail ou WhatsApp. Acompanhe seu pedido na aba "Meus Pedidos" do seu perfil.')
        : isPending
            • (isPlano
                • 'Seu pagamento está em análise. O plano será ativado automaticamente quando for aprovado.'
                : 'Seu pagamento está em análise. Você receberá a confirmação quando for aprovado.')
            : 'O prazo para pagar pode ter expirado, o pagamento pode ter sido recusado ou reembolsado. Tente novamente ou escolha outra forma de pagamento.';

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
