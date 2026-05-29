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

  @HiveField(19, defaultValue: 0.0)
  double outrasDespesas;

  /// Espelho Firestore: true após gravação local até sync bem-sucedido.
  @HiveField(20, defaultValue: true)
  bool syncPendente;

  /// Valores típicos: pendente | ok | erro (somente informativo).
  @HiveField(21, defaultValue: 'pendente')
  String syncStatus;

  /// [CompraFornecedorTipo.produtosEstoque] ou [CompraFornecedorTipo.financeira].
  @HiveField(22, defaultValue: CompraFornecedorTipo.produtosEstoque)
  String tipoCompra;

  /// Valor base informado (compras financeiras / revenda sem itens na confirmação).
  @HiveField(23, defaultValue: 0.0)
  double valorInformado;

  /// [CompraFornecedorStatusDetalhamento]
  @HiveField(24, defaultValue: CompraFornecedorStatusDetalhamento.naoAplicavel)
  String statusDetalhamentoProdutos;

  @HiveField(25)
  DateTime? detalhamentoProdutosAt;

  @HiveField(26)
  DateTime? detalhamentoProdutosConferidoAt;

  @HiveField(27, defaultValue: 0.0)
  double valorProdutosDetalhados;

  @HiveField(28, defaultValue: 0.0)
  double diferencaDetalhamento;

  @HiveField(29, defaultValue: 0)
  int quantidadeItensDetalhados;

  @HiveField(30, defaultValue: '')
  String observacaoDetalhamento;

  @HiveField(31)
  DateTime? canceladaEm;

  @HiveField(32, defaultValue: '')
  String canceladaMotivo;

  @HiveField(33, defaultValue: false)
  bool cancelamentoEstoqueAplicado;

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
    this.outrasDespesas = 0,
    this.syncPendente = true,
    this.syncStatus = 'pendente',
    this.tipoCompra = CompraFornecedorTipo.produtosEstoque,
    this.valorInformado = 0,
    this.statusDetalhamentoProdutos =
        CompraFornecedorStatusDetalhamento.naoAplicavel,
    this.detalhamentoProdutosAt,
    this.detalhamentoProdutosConferidoAt,
    this.valorProdutosDetalhados = 0,
    this.diferencaDetalhamento = 0,
    this.quantidadeItensDetalhados = 0,
    this.observacaoDetalhamento = '',
    this.canceladaEm,
    this.canceladaMotivo = '',
    this.cancelamentoEstoqueAplicado = false,
  })  : criadoEm = criadoEm ?? DateTime.now(),
        atualizadoEm = atualizadoEm ?? DateTime.now();

  bool get estaCancelada =>
      statusCompra == CompraFornecedorStatusCompra.cancelada;

  bool get movimentaEstoque => CompraFornecedorTipo.movimentaEstoque(tipoCompra);

  bool get ehCompraFinanceira =>
      CompraFornecedorTipo.ouPadrao(tipoCompra) == CompraFornecedorTipo.financeira;

  bool get ehCompraRevendaDetalharDepois =>
      CompraFornecedorTipo.ehRevendaDetalharDepois(tipoCompra);

  bool get aguardaDetalhamentoProdutos =>
      ehCompraRevendaDetalharDepois &&
      CompraFornecedorStatusDetalhamento.pendente(statusDetalhamentoProdutos);

  List<CompraFornecedorItem> get itensOuVazio =>
      itens ?? const <CompraFornecedorItem>[];

  double get subtotalItens {
    var t = 0.0;
    for (final it in itensOuVazio) {
      t += it.subtotal;
    }
    return t;
  }

  /// Soma dos subtotais base (quantidade × custo unitário base).
  double get subtotalItensBase => subtotalItens;

  /// Total financeiro da compra (origem do evento; uma linha no futuro financeiro).
  double get valorTotalFinanceiro {
    final base = CompraFornecedorTipo.usaItensNoTotal(tipoCompra)
        ? subtotalItens
        : valorInformado;
    return (base + frete + outrasDespesas - desconto).clamp(0.0, 1e15);
  }

  double get valorCompraParaConferenciaDetalhamento => valorTotalFinanceiro;

  /// Alias legado — mesmo que [valorTotalFinanceiro].
  double get valorTotal => valorTotalFinanceiro;

  double get valorEmAberto =>
      (valorTotalFinanceiro - valorPago).clamp(0.0, 1e15);

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
    double? outrasDespesas,
    bool? syncPendente,
    String? syncStatus,
    String? tipoCompra,
    double? valorInformado,
    String? statusDetalhamentoProdutos,
    DateTime? detalhamentoProdutosAt,
    DateTime? detalhamentoProdutosConferidoAt,
    double? valorProdutosDetalhados,
    double? diferencaDetalhamento,
    int? quantidadeItensDetalhados,
    String? observacaoDetalhamento,
    DateTime? canceladaEm,
    String? canceladaMotivo,
    bool? cancelamentoEstoqueAplicado,
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
      outrasDespesas: outrasDespesas ?? this.outrasDespesas,
      syncPendente: syncPendente ?? this.syncPendente,
      syncStatus: syncStatus ?? this.syncStatus,
      tipoCompra: tipoCompra ?? this.tipoCompra,
      valorInformado: valorInformado ?? this.valorInformado,
      statusDetalhamentoProdutos:
          statusDetalhamentoProdutos ?? this.statusDetalhamentoProdutos,
      detalhamentoProdutosAt:
          detalhamentoProdutosAt ?? this.detalhamentoProdutosAt,
      detalhamentoProdutosConferidoAt: detalhamentoProdutosConferidoAt ??
          this.detalhamentoProdutosConferidoAt,
      valorProdutosDetalhados:
          valorProdutosDetalhados ?? this.valorProdutosDetalhados,
      diferencaDetalhamento:
          diferencaDetalhamento ?? this.diferencaDetalhamento,
      quantidadeItensDetalhados:
          quantidadeItensDetalhados ?? this.quantidadeItensDetalhados,
      observacaoDetalhamento:
          observacaoDetalhamento ?? this.observacaoDetalhamento,
      canceladaEm: canceladaEm ?? this.canceladaEm,
      canceladaMotivo: canceladaMotivo ?? this.canceladaMotivo,
      cancelamentoEstoqueAplicado:
          cancelamentoEstoqueAplicado ?? this.cancelamentoEstoqueAplicado,
    );
  }
}
