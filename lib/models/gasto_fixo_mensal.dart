import 'package:hive/hive.dart';

part 'gasto_fixo_mensal.g.dart';

@HiveType(typeId: 31)
class GastoFixoMensal extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String lojaId;

  @HiveField(2)
  String descricao;

  @HiveField(3)
  double valorPadrao;

  @HiveField(4)
  String categoria;

  @HiveField(5)
  String subcategoria;

  @HiveField(6)
  int diaVencimento;

  @HiveField(7)
  bool ativo;

  @HiveField(8)
  String formaPagamentoPadrao;

  @HiveField(9)
  String fornecedor;

  @HiveField(10)
  String observacao;

  @HiveField(11)
  String centroCusto;

  GastoFixoMensal({
    required this.id,
    required this.lojaId,
    required this.descricao,
    this.valorPadrao = 0,
    this.categoria = '',
    this.subcategoria = '',
    this.diaVencimento = 1,
    this.ativo = true,
    this.formaPagamentoPadrao = '',
    this.fornecedor = '',
    this.observacao = '',
    this.centroCusto = '',
  });

  GastoFixoMensal copyWith({
    String? id,
    String? lojaId,
    String? descricao,
    double? valorPadrao,
    String? categoria,
    String? subcategoria,
    int? diaVencimento,
    bool? ativo,
    String? formaPagamentoPadrao,
    String? fornecedor,
    String? observacao,
    String? centroCusto,
  }) {
    return GastoFixoMensal(
      id: id ?? this.id,
      lojaId: lojaId ?? this.lojaId,
      descricao: descricao ?? this.descricao,
      valorPadrao: valorPadrao ?? this.valorPadrao,
      categoria: categoria ?? this.categoria,
      subcategoria: subcategoria ?? this.subcategoria,
      diaVencimento: diaVencimento ?? this.diaVencimento,
      ativo: ativo ?? this.ativo,
      formaPagamentoPadrao: formaPagamentoPadrao ?? this.formaPagamentoPadrao,
      fornecedor: fornecedor ?? this.fornecedor,
      observacao: observacao ?? this.observacao,
      centroCusto: centroCusto ?? this.centroCusto,
    );
  }
}
