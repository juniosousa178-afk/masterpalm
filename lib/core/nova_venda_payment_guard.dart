/// Guard de pagamento da Nova Venda — bloqueia persistência sem chamar o backend.

const kNovaVendaPagamentoIncompletoMensagem =
    'Informe a forma de pagamento e complete o valor total da venda antes de salvar.';

/// True quando o PDV não deve chamar o backend de venda.
bool novaVendaPagamentoImpedeSalvar({
  required double total,
  required double allocated,
  required bool isFiado,
}) {
  if (isFiado) return allocated > total + 0.01;
  return (allocated - total).abs() > 0.01;
}
