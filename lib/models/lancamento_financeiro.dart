import 'package:hive/hive.dart';

import '../financeiro/financeiro_constants.dart';

part 'lancamento_financeiro.g.dart';

@HiveType(typeId: 30)
class LancamentoFinanceiro extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String lojaId;

  @HiveField(2)
  String descricao;

  @HiveField(3)
  double valor;

  /// [FinanceiroTipoLancamento]
  @HiveField(4)
  String tipo;

  @HiveField(5)
  String categoria;

  @HiveField(6)
  String subcategoria;

  /// [FinanceiroStatusLancamento]
  @HiveField(7)
  String status;

  @HiveField(8)
  String formaPagamento;

  @HiveField(9)
  String fornecedor;

  @HiveField(10)
  String observacao;

  @HiveField(11)
  DateTime dataLancamento;

  @HiveField(12)
  DateTime? dataPagamento;

  @HiveField(13)
  int competenciaMes;

  @HiveField(14)
  int competenciaAno;

  @HiveField(15)
  bool recorrente;

  @HiveField(16)
  String origem;

  @HiveField(17)
  String usuarioId;

  @HiveField(18)
  String usuarioNome;

  @HiveField(19)
  String centroCusto;

  /// URL ou caminho local — uso futuro
  @HiveField(20)
  String anexoComprovante;

  /// Nota, NF, código interno — rastreio manual; não vincula compra automaticamente.
  @HiveField(21, defaultValue: '')
  String referenciaExterna;

  /// Só relevante para [FinanceiroTipoLancamento.compraMercadoria]: intenção de refletir no estoque (não automático sem módulo de compras).
  @HiveField(22, defaultValue: false)
  bool solicitarAtualizacaoEstoque;

  LancamentoFinanceiro({
    required this.id,
    required this.lojaId,
    required this.descricao,
    required this.valor,
    this.tipo = FinanceiroTipoLancamento.despesaOperacional,
    this.categoria = '',
    this.subcategoria = '',
    this.status = FinanceiroStatusLancamento.pago,
    this.formaPagamento = '',
    this.fornecedor = '',
    this.observacao = '',
    required this.dataLancamento,
    this.dataPagamento,
    int? competenciaMes,
    int? competenciaAno,
    this.recorrente = false,
    this.origem = FinanceiroOrigemLancamento.manual,
    this.usuarioId = '',
    this.usuarioNome = '',
    this.centroCusto = '',
    this.anexoComprovante = '',
    this.referenciaExterna = '',
    this.solicitarAtualizacaoEstoque = false,
  })  : competenciaMes = competenciaMes ?? dataLancamento.month,
        competenciaAno = competenciaAno ?? dataLancamento.year;

  DateTime get dataEfetivaPagamentoOuLancamento =>
      dataPagamento ?? dataLancamento;

  LancamentoFinanceiro copyWith({
    String? id,
    String? lojaId,
    String? descricao,
    double? valor,
    String? tipo,
    String? categoria,
    String? subcategoria,
    String? status,
    String? formaPagamento,
    String? fornecedor,
    String? observacao,
    DateTime? dataLancamento,
    DateTime? dataPagamento,
    int? competenciaMes,
    int? competenciaAno,
    bool? recorrente,
    String? origem,
    String? usuarioId,
    String? usuarioNome,
    String? centroCusto,
    String? anexoComprovante,
    String? referenciaExterna,
    bool? solicitarAtualizacaoEstoque,
  }) {
    return LancamentoFinanceiro(
      id: id ?? this.id,
      lojaId: lojaId ?? this.lojaId,
      descricao: descricao ?? this.descricao,
      valor: valor ?? this.valor,
      tipo: tipo ?? this.tipo,
      categoria: categoria ?? this.categoria,
      subcategoria: subcategoria ?? this.subcategoria,
      status: status ?? this.status,
      formaPagamento: formaPagamento ?? this.formaPagamento,
      fornecedor: fornecedor ?? this.fornecedor,
      observacao: observacao ?? this.observacao,
      dataLancamento: dataLancamento ?? this.dataLancamento,
      dataPagamento: dataPagamento ?? this.dataPagamento,
      competenciaMes: competenciaMes ?? this.competenciaMes,
      competenciaAno: competenciaAno ?? this.competenciaAno,
      recorrente: recorrente ?? this.recorrente,
      origem: origem ?? this.origem,
      usuarioId: usuarioId ?? this.usuarioId,
      usuarioNome: usuarioNome ?? this.usuarioNome,
      centroCusto: centroCusto ?? this.centroCusto,
      anexoComprovante: anexoComprovante ?? this.anexoComprovante,
      referenciaExterna: referenciaExterna ?? this.referenciaExterna,
      solicitarAtualizacaoEstoque:
          solicitarAtualizacaoEstoque ?? this.solicitarAtualizacaoEstoque,
    );
  }
}
