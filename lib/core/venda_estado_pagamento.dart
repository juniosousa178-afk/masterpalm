// Estado de pagamento de uma venda na edição (fiado × Pix/Dinheiro/Cartão).

import 'dart:math' as math;

import '../models/venda.dart';
import 'conta_receber_venda_vinculo.dart';

const double _eps = 0.01;

double _centavos(double v) => (v * 100).roundToDouble() / 100;

/// Mesmas regras de `storedPaymentState` / `editedPaymentState`
/// (functions/src/stockCatalogSaleEditReceivable.js).
class EstadoPagamentoVenda {
  final bool fiado;
  final double dinheiro;
  final double pix;
  final double cartao;

  const EstadoPagamentoVenda({
    required this.fiado,
    this.dinheiro = 0,
    this.pix = 0,
    this.cartao = 0,
  });

  /// Estado salvo: fiado só enquanto há valor em aberto E a venda está marcada como fiado.
  factory EstadoPagamentoVenda.daVenda(Venda v) => EstadoPagamentoVenda(
        fiado: valorAReceberDaVenda(v) > _eps &&
            v.formasPagamento.toLowerCase().contains('fiado'),
        dinheiro: v.pagamentoDinheiro,
        pix: v.pagamentoPix,
        cartao: v.pagamentoCartao,
      );

  /// Estado que a edição grava, já com a normalização de `editarVendaMulti`
  /// (venda não fiada sem pagamento informado vira Dinheiro = total).
  factory EstadoPagamentoVenda.daEdicao({
    required bool isFiado,
    required double total,
    double dinheiro = 0,
    double pix = 0,
    double cartao = 0,
  }) {
    if (!isFiado && dinheiro == 0 && pix == 0 && cartao == 0) dinheiro = total;
    return EstadoPagamentoVenda(
      fiado: total - (dinheiro + pix + cartao) > _eps,
      dinheiro: dinheiro,
      pix: pix,
      cartao: cartao,
    );
  }

  bool equivalente(EstadoPagamentoVenda o) =>
      fiado == o.fiado &&
      (dinheiro - o.dinheiro).abs() <= _eps &&
      (pix - o.pix).abs() <= _eps &&
      (cartao - o.cartao).abs() <= _eps;

  Map<String, Object> toJson() => {
        'fiado': fiado,
        'dinheiro': _centavos(dinheiro),
        'pix': _centavos(pix),
        'cartao': _centavos(cartao),
      };

  @override
  String toString() =>
      'EstadoPagamentoVenda(fiado: $fiado, dinheiro: $dinheiro, pix: $pix, cartao: $cartao)';
}

/// Formulário de pagamento do editor preenchido a partir da venda salva.
class PagamentoEdicaoHidratado {
  final List<Map<String, dynamic>> pagamentos;
  final bool fiado;
  final DateTime? vencimentoFiado;
  final int diasVencimento;
  final int quantidadeParcelas;
  final int intervaloDias;

  const PagamentoEdicaoHidratado({
    required this.pagamentos,
    required this.fiado,
    this.vencimentoFiado,
    this.diasVencimento = 30,
    this.quantidadeParcelas = 1,
    this.intervaloDias = 30,
  });
}

/// Venda fiada abre fiada, com o que já foi pago e sem completar o saldo com Pix.
PagamentoEdicaoHidratado hidratarPagamentoEdicao(Venda v, {DateTime? hoje}) {
  final pagamentos = <Map<String, dynamic>>[
    if (v.pagamentoDinheiro > 0) {'forma': 'Dinheiro', 'valor': v.pagamentoDinheiro},
    if (v.pagamentoPix > 0) {'forma': 'Pix', 'valor': v.pagamentoPix},
    if (v.pagamentoCartao > 0) {'forma': 'Cartão', 'valor': v.pagamentoCartao},
  ];
  final estado = EstadoPagamentoVenda.daVenda(v);
  if (!estado.fiado) {
    // Venda legada sem campos de pagamento e sem saldo fiado: mantém o comportamento anterior.
    if (pagamentos.isEmpty) pagamentos.add({'forma': 'Pix', 'valor': v.total});
    return PagamentoEdicaoHidratado(pagamentos: pagamentos, fiado: false);
  }
  if (pagamentos.isEmpty) pagamentos.add({'forma': 'Pix', 'valor': 0.0});
  final meta = parseFiadoMetadataFromFormasPagamento(v.formasPagamento);
  final base = hoje ?? DateTime.now();
  final dia = DateTime(base.year, base.month, base.day);
  final venc = meta.dataVencimento;
  final dias = venc == null ? 30 : math.max(1, venc.difference(dia).inDays);
  return PagamentoEdicaoHidratado(
    pagamentos: pagamentos,
    fiado: true,
    vencimentoFiado: venc,
    diasVencimento: math.min(dias, 365),
    quantidadeParcelas: meta.quantidadeParcelas,
    intervaloDias: meta.intervaloDias,
  );
}

/// Venda fiada editada sem decisão explícita do usuário sobre o pagamento.
class AlteracaoPagamentoNaoConfirmadaException implements Exception {
  static const mensagem =
      'Esta venda é fiada e a forma de pagamento mudou sem confirmação. '
      'Abra o campo de pagamento, confirme a mudança e salve novamente. Nenhuma alteração foi feita.';

  @override
  String toString() => mensagem;
}
