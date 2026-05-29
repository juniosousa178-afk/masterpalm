import 'package:hive/hive.dart';

import 'conta_pagar_constants.dart';

part 'conta_pagar.g.dart';

@HiveType(typeId: 35)
class ContaPagar extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String lojaId;

  /// Chave Hive do fornecedor (0 = desconhecido).
  @HiveField(2)
  int fornecedorId;

  @HiveField(3)
  String fornecedorNome;

  @HiveField(4)
  String compraId;

  @HiveField(5)
  String descricao;

  @HiveField(6)
  double valorTotalCompra;

  @HiveField(7)
  double valorParcela;

  @HiveField(8)
  int parcelaNumero;

  @HiveField(9)
  int parcelaTotal;

  @HiveField(10)
  DateTime dataVencimento;

  @HiveField(11)
  DateTime? dataPagamento;

  /// [ContaPagarStatus]
  @HiveField(12)
  String status;

  @HiveField(13)
  String formaPagamento;

  @HiveField(14)
  String observacao;

  @HiveField(15, defaultValue: '')
  String lancamentoFinanceiroId;

  @HiveField(16)
  DateTime criadoEm;

  @HiveField(17)
  DateTime atualizadoEm;

  /// Data da compra (competência gerencial).
  @HiveField(18)
  DateTime dataCompra;

  /// Sync Firestore opcional.
  @HiveField(19, defaultValue: '')
  String idFirebase;

  ContaPagar({
    required this.id,
    required this.lojaId,
    required this.fornecedorId,
    required this.fornecedorNome,
    required this.compraId,
    required this.descricao,
    required this.valorTotalCompra,
    required this.valorParcela,
    required this.parcelaNumero,
    required this.parcelaTotal,
    required this.dataVencimento,
    this.dataPagamento,
    this.status = ContaPagarStatus.pendente,
    this.formaPagamento = '',
    this.observacao = '',
    this.lancamentoFinanceiroId = '',
    DateTime? criadoEm,
    DateTime? atualizadoEm,
    required this.dataCompra,
    this.idFirebase = '',
  })  : criadoEm = criadoEm ?? DateTime.now(),
        atualizadoEm = atualizadoEm ?? DateTime.now();

  /// Status efetivo para UI (pendente + vencimento passado → vencido).
  String get statusEfetivo {
    if (status == ContaPagarStatus.pago ||
        status == ContaPagarStatus.cancelado) {
      return status;
    }
    final hoje = DateTime.now();
    final venc = DateTime(
      dataVencimento.year,
      dataVencimento.month,
      dataVencimento.day,
    );
    final h = DateTime(hoje.year, hoje.month, hoje.day);
    if (!h.isAfter(venc)) return ContaPagarStatus.pendente;
    return ContaPagarStatus.vencido;
  }

  bool get estaAberta =>
      status != ContaPagarStatus.pago &&
      status != ContaPagarStatus.cancelado;

  ContaPagar copyWith({
    String? id,
    String? lojaId,
    int? fornecedorId,
    String? fornecedorNome,
    String? compraId,
    String? descricao,
    double? valorTotalCompra,
    double? valorParcela,
    int? parcelaNumero,
    int? parcelaTotal,
    DateTime? dataVencimento,
    DateTime? dataPagamento,
    String? status,
    String? formaPagamento,
    String? observacao,
    String? lancamentoFinanceiroId,
    DateTime? criadoEm,
    DateTime? atualizadoEm,
    DateTime? dataCompra,
    String? idFirebase,
  }) {
    return ContaPagar(
      id: id ?? this.id,
      lojaId: lojaId ?? this.lojaId,
      fornecedorId: fornecedorId ?? this.fornecedorId,
      fornecedorNome: fornecedorNome ?? this.fornecedorNome,
      compraId: compraId ?? this.compraId,
      descricao: descricao ?? this.descricao,
      valorTotalCompra: valorTotalCompra ?? this.valorTotalCompra,
      valorParcela: valorParcela ?? this.valorParcela,
      parcelaNumero: parcelaNumero ?? this.parcelaNumero,
      parcelaTotal: parcelaTotal ?? this.parcelaTotal,
      dataVencimento: dataVencimento ?? this.dataVencimento,
      dataPagamento: dataPagamento ?? this.dataPagamento,
      status: status ?? this.status,
      formaPagamento: formaPagamento ?? this.formaPagamento,
      observacao: observacao ?? this.observacao,
      lancamentoFinanceiroId:
          lancamentoFinanceiroId ?? this.lancamentoFinanceiroId,
      criadoEm: criadoEm ?? this.criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
      dataCompra: dataCompra ?? this.dataCompra,
      idFirebase: idFirebase ?? this.idFirebase,
    );
  }
}
