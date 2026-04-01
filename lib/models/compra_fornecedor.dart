import 'package:hive/hive.dart';

import 'compra_fornecedor_constants.dart';
import 'compra_fornecedor_item.dart';

part 'compra_fornecedor.g.dart';

@HiveType(typeId: 32)
class CompraFornecedor extends HiveObject {
  /// UUID estável (chave Hive e futura idempotência Firestore).
  @HiveField(0)
  String id;

  @HiveField(1)
  String lojaId;

  @HiveField(2)
  int fornecedorHiveKey;

  @HiveField(3)
  String fornecedorNome;

  @HiveField(4)
  String referenciaInterna;

  @HiveField(5)
  DateTime dataCompra;

  @HiveField(6)
  DateTime? dataVencimento;

  @HiveField(7)
  String statusCompra;

  @HiveField(8)
  String statusPagamento;

  @HiveField(9)
  String observacao;

  @HiveField(10)
  double frete;

  @HiveField(11)
  double desconto;

  @HiveField(12)
  double valorPago;

  @HiveField(13)
  List<CompraFornecedorItem>? itens;

  /// Fase 2: evita segunda entrada no estoque.
  @HiveField(14, defaultValue: false)
  bool estoqueIntegrado;

  /// Fase 3: id do documento em `lancamentos_financeiros` (vazio = ainda não vinculado).
  @HiveField(15, defaultValue: '')
  String idLancamentoFinanceiro;

  @HiveField(16)
  DateTime? confirmadoEm;

  @HiveField(17)
  DateTime criadoEm;

  @HiveField(18)
  DateTime atualizadoEm;

  CompraFornecedor({
    required this.id,
    required this.lojaId,
    required this.fornecedorHiveKey,
    required this.fornecedorNome,
    this.referenciaInterna = '',
    required this.dataCompra,
    this.dataVencimento,
    this.statusCompra = CompraFornecedorStatusCompra.rascunho,
    this.statusPagamento = CompraFornecedorStatusPagamento.pendente,
    this.observacao = '',
    this.frete = 0,
    this.desconto = 0,
    this.valorPago = 0,
    this.itens,
    this.estoqueIntegrado = false,
    this.idLancamentoFinanceiro = '',
    this.confirmadoEm,
    DateTime? criadoEm,
    DateTime? atualizadoEm,
  })  : criadoEm = criadoEm ?? DateTime.now(),
        atualizadoEm = atualizadoEm ?? DateTime.now();

  List<CompraFornecedorItem> get itensOuVazio =>
      itens ?? const <CompraFornecedorItem>[];

  double get subtotalItens {
    var t = 0.0;
    for (final it in itensOuVazio) {
      t += it.subtotal;
    }
    return t;
  }

  double get valorTotal => (subtotalItens + frete - desconto).clamp(0.0, 1e15);

  double get valorEmAberto =>
      (valorTotal - valorPago).clamp(0.0, 1e15);

  bool get podeEditarValoresPagamento =>
      statusCompra == CompraFornecedorStatusCompra.confirmada;

  CompraFornecedor copyWith({
    String? id,
    String? lojaId,
    int? fornecedorHiveKey,
    String? fornecedorNome,
    String? referenciaInterna,
    DateTime? dataCompra,
    DateTime? dataVencimento,
    String? statusCompra,
    String? statusPagamento,
    String? observacao,
    double? frete,
    double? desconto,
    double? valorPago,
    List<CompraFornecedorItem>? itens,
    bool? estoqueIntegrado,
    String? idLancamentoFinanceiro,
    DateTime? confirmadoEm,
    DateTime? criadoEm,
    DateTime? atualizadoEm,
  }) {
    return CompraFornecedor(
      id: id ?? this.id,
      lojaId: lojaId ?? this.lojaId,
      fornecedorHiveKey: fornecedorHiveKey ?? this.fornecedorHiveKey,
      fornecedorNome: fornecedorNome ?? this.fornecedorNome,
      referenciaInterna: referenciaInterna ?? this.referenciaInterna,
      dataCompra: dataCompra ?? this.dataCompra,
      dataVencimento: dataVencimento ?? this.dataVencimento,
      statusCompra: statusCompra ?? this.statusCompra,
      statusPagamento: statusPagamento ?? this.statusPagamento,
      observacao: observacao ?? this.observacao,
      frete: frete ?? this.frete,
      desconto: desconto ?? this.desconto,
      valorPago: valorPago ?? this.valorPago,
      itens: itens ?? this.itens,
      estoqueIntegrado: estoqueIntegrado ?? this.estoqueIntegrado,
      idLancamentoFinanceiro:
          idLancamentoFinanceiro ?? this.idLancamentoFinanceiro,
      confirmadoEm: confirmadoEm ?? this.confirmadoEm,
      criadoEm: criadoEm ?? this.criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
    );
  }
}
