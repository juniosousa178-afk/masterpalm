// lib/models/conta_receber.dart
// Contas a receber (vendas fiadas ou títulos). Melhoria financeira.

import 'dart:convert';

import 'package:hive/hive.dart';

part 'conta_receber.g.dart';

/// Status da conta a receber.
abstract final class ContaReceberStatus {
  static const pendente = 'pendente';
  static const parcial = 'parcial';
  static const paga = 'paga';
}

@HiveType(typeId: 29)
class ContaReceber extends HiveObject {
  @HiveField(0)
  String lojaId;

  @HiveField(1)
  String clienteNome;

  /// Saldo em aberto (restante a receber).
  @HiveField(2)
  double valor;

  @HiveField(3)
  DateTime dataVencimento;

  @HiveField(4)
  DateTime dataVenda;

  @HiveField(5)
  bool pago;

  @HiveField(6)
  String observacao;

  /// Chave Hive da venda vinculada (opcional). 0 = não vinculado.
  @HiveField(7)
  int vendaKey;

  @HiveField(8)
  String? idFirebase;

  @HiveField(9)
  int parcelaNumero;

  @HiveField(10)
  int parcelaTotal;

  @HiveField(11)
  bool lembrete2DiasEnviado;

  /// Valor original do título (antes de baixas parciais).
  @HiveField(12)
  double valorOriginal;

  /// Total já recebido neste título.
  @HiveField(13)
  double valorPago;

  /// [ContaReceberStatus]: pendente | parcial | paga
  @HiveField(14)
  String status;

  /// JSON array de recebimentos: [{valor, data, forma}]
  @HiveField(15)
  String historicoPagamentosJson;

  /// ID estável da venda (idFirebase) para vínculo quando [vendaKey] Hive falha no Web.
  @HiveField(16)
  String vendaIdFirebase;

  ContaReceber({
    required this.lojaId,
    required this.clienteNome,
    required this.valor,
    required this.dataVencimento,
    required this.dataVenda,
    this.pago = false,
    this.observacao = '',
    this.vendaKey = 0,
    this.idFirebase,
    this.parcelaNumero = 1,
    this.parcelaTotal = 1,
    this.lembrete2DiasEnviado = false,
    double? valorOriginal,
    this.valorPago = 0,
    String? status,
    this.historicoPagamentosJson = '[]',
    this.vendaIdFirebase = '',
  })  : valorOriginal = valorOriginal ?? valor,
        status = status ?? ContaReceberStatus.pendente {
    normalizarCamposFinanceiros();
  }

  double get saldoRestante => valor;

  /// Compatibilidade com registros antigos (só [valor] e [pago]).
  void normalizarCamposFinanceiros() {
    if (valorOriginal <= 1e-9) {
      valorOriginal = valor + valorPago;
    }
    if (valorOriginal + 1e-9 < valorPago + valor) {
      valorOriginal = valorPago + valor;
    }
    recalcularStatus();
  }

  void recalcularStatus() {
    if (pago || valor < 0.01) {
      pago = true;
      valor = 0;
      status = ContaReceberStatus.paga;
      return;
    }
    pago = false;
    if (valorPago > 0.01) {
      status = ContaReceberStatus.parcial;
    } else {
      status = ContaReceberStatus.pendente;
    }
  }

  List<Map<String, dynamic>> historicoPagamentos() {
    try {
      final decoded = jsonDecode(historicoPagamentosJson);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void adicionarPagamentoHistorico({
    required double valorRecebido,
    required DateTime data,
    required String formaPagamento,
  }) {
    final hist = historicoPagamentos();
    hist.add({
      'valor': valorRecebido,
      'data': data.toIso8601String(),
      'forma': formaPagamento.trim(),
    });
    historicoPagamentosJson = jsonEncode(hist);
  }
}
