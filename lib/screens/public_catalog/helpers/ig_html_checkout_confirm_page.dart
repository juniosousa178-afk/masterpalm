import 'package:flutter/material.dart';

/// Tela intermediária após o formulário HTML (Instagram) devolver `igCheckoutReady=1`.
class IgHtmlCheckoutConfirmPage extends StatelessWidget {
  const IgHtmlCheckoutConfirmPage({
    super.key,
    required this.lojaNome,
    required this.customer,
    required this.entrega,
    required this.pagamento,
    required this.observacao,
    required this.cupomCodigo,
    required this.cupomFreteCodigo,
    required this.cupomRoletaCodigo,
    required this.cupomRoletaDesconto,
    required this.premioRoletaDescricao,
    required this.mercadoPagoAtivo,
    required this.checkoutGateway,
    required this.onMercadoPago,
    required this.onWhatsapp,
  });

  final String lojaNome;
  final Map<String, dynamic> customer;
  final Map<String, dynamic> entrega;
  final String pagamento;
  final String observacao;
  final String? cupomCodigo;
  final String? cupomFreteCodigo;
  final String? cupomRoletaCodigo;
  final double? cupomRoletaDesconto;
  final String? premioRoletaDescricao;
  final bool mercadoPagoAtivo;
  final String checkoutGateway;
  final Future<bool> Function() onMercadoPago;
  final Future<bool> Function() onWhatsapp;

  String _nome() => (customer['nome'] ?? '').toString().trim();
  String _email() => (customer['email'] ?? '').toString().trim();
  String _tel() =>
      (customer['telefone'] ?? customer['tel'] ?? '').toString().trim();
  String _freteNome() =>
      (entrega['nome'] ?? entrega['label'] ?? 'Entrega').toString();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showMp = mercadoPagoAtivo &&
        checkoutGateway != 'whatsapp' &&
        pagamento.toUpperCase() != 'DINHEIRO';
    final showWa = checkoutGateway == 'whatsapp' ||
        checkoutGateway == 'pix' ||
        checkoutGateway.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirmar pedido'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            lojaNome.isNotEmpty ? lojaNome : 'Sua loja',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text('Dados', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text('Nome: ${_nome()}'),
          if (_email().isNotEmpty) Text('E-mail: ${_email()}'),
          if (_tel().isNotEmpty) Text('Telefone: ${_tel()}'),
          const SizedBox(height: 16),
          Text('Entrega', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(_freteNome()),
          const SizedBox(height: 16),
          Text('Pagamento: $pagamento', style: theme.textTheme.titleSmall),
          if (observacao.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Obs.: ${observacao.trim()}'),
          ],
          if ((cupomCodigo ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Cupom: ${cupomCodigo!.trim()}'),
          ],
          if ((cupomFreteCodigo ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Cupom frete: ${cupomFreteCodigo!.trim()}'),
          ],
          if ((cupomRoletaCodigo ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Roleta: ${cupomRoletaCodigo!.trim()}'
              '${cupomRoletaDesconto != null && cupomRoletaDesconto! > 0 ? ' (−$cupomRoletaDesconto%)' : ''}'
              '${(premioRoletaDescricao ?? '').trim().isNotEmpty ? ' — ${(premioRoletaDescricao ?? '').trim()}' : ''}',
            ),
          ],
          const SizedBox(height: 28),
          if (showMp) ...[
            FilledButton.icon(
              onPressed: () async {
                final ok = await onMercadoPago();
                if (ok && context.mounted) Navigator.of(context).pop(true);
              },
              icon: const Icon(Icons.payment),
              label: Text(
                pagamento.toUpperCase() == 'PIX'
                    ? 'Pagar com PIX'
                    : 'Pagar com Mercado Pago',
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (showWa)
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await onWhatsapp();
                if (ok && context.mounted) Navigator.of(context).pop(true);
              },
              icon: const Icon(Icons.chat),
              label: const Text('Finalizar pelo WhatsApp'),
            ),
        ],
      ),
    );
  }
}
