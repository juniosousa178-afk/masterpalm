/// Helpers puros de texto/formatação usados por `PrePedidoService`.
/// Não fazem I/O nem acessam Firestore/Hive.
library;

/// Determina o status interno do pagamento a partir do método informado.
/// - dinheiro/pix_manual/boleto: 'aprovado'
/// - mercadopago/pix_gateway/cartão/gateway: 'pendente'
String determinarStatusPagamento(String metodoPagamento) {
  final metodo = metodoPagamento.toLowerCase().trim();

  // Métodos que precisam confirmação da gateway
  if (metodo.contains('mercadopago') ||
      metodo.contains('mercado pago') ||
      metodo.contains('mp') ||
      metodo.contains('gateway') ||
      metodo.contains('cartao') ||
      metodo.contains('cartão') ||
      metodo == 'pix') {
    // PIX via gateway
    return 'pendente';
  }

  // Métodos manuais (confirmação imediata pelo vendedor)
  return 'aprovado';
}

/// Formata valor monetário em formato brasileiro (2 casas, vírgula).
String formatarValor(double valor) {
  return valor.toStringAsFixed(2).replaceAll('.', ',');
}

/// Determina o tipo de prêmio da roleta a partir da descrição/código/desconto.
String determinarTipoPremio(String• descricao, String• codigo, double• desconto) {
  if (descricao == null && codigo == null) return 'nenhum';

  final desc = (descricao ?• '').toLowerCase();

  // Verificar se é brinde
  if (desc.contains('brinde') ||
      desc.contains('mimo') ||
      desc.contains('chaveiro') ||
      desc.contains('presente') ||
      desc.contains('adesivo')) {
    return 'brinde';
  }

  // Verificar se é frete grátis
  if (desc.contains('frete') && desc.contains('gr')) {
    return 'frete_gratis';
  }

  // Verificar se é desconto
  if (codigo != null && desconto != null && desconto > 0) {
    return 'desconto';
  }

  // Se tem cupom mas não identificou o tipo, assume desconto
  if (codigo != null) {
    return 'desconto';
  }

  return 'nenhum';
}

