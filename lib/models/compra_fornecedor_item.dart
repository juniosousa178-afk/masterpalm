import 'package:hive/hive.dart';

part 'compra_fornecedor_item.g.dart';

@HiveType(typeId: 33)
class CompraFornecedorItem {
  @HiveField(0)
  String produtoNome;

  @HiveField(1)
  int quantidade;

  @HiveField(2)
  double custoUnitario;

  /// idFirebase do produto quando conhecido (vínculo opcional).
  @HiveField(3)
  String? productId;

  /// UUID estável por linha — chave de idempotência com [compraId].
  @HiveField(4, defaultValue: '')
  String itemCompraId;

  @HiveField(5, defaultValue: '')
  String codigoInterno;

  @HiveField(6, defaultValue: '')
  String codigoBarras;

  @HiveField(7, defaultValue: '')
  String observacaoItem;

  @HiveField(8, defaultValue: '')
  String unidade;

  @HiveField(9, defaultValue: 0.0)
  double subtotalBase;

  @HiveField(10, defaultValue: 0.0)
  double percentualParticipacao;

  @HiveField(11, defaultValue: 0.0)
  double freteRateado;

  @HiveField(12, defaultValue: 0.0)
  double descontoRateado;

  @HiveField(13, defaultValue: 0.0)
  double outrasDespesasRateadas;

  @HiveField(14, defaultValue: 0.0)
  double custoUnitarioFinal;

  @HiveField(15, defaultValue: 0.0)
  double subtotalFinal;

  /// Entrada de estoque já aplicada (detalhamento revenda / futuro pipeline).
  @HiveField(16, defaultValue: false)
  bool estoqueEntradaRegistrada;

  /// Snapshot válido para estorno automático.
  @HiveField(17, defaultValue: false)
  bool estoqueSnapshotOk;

  @HiveField(18, defaultValue: 0)
  int estoqueAnterior;

  @HiveField(19, defaultValue: 0.0)
  double custoAnterior;

  @HiveField(20, defaultValue: '')
  String tamanhoEntrada;

  @HiveField(21, defaultValue: '')
  String corEntrada;

  /// Produto criado no detalhamento revenda (tratamento especial no cancelamento).
  @HiveField(22, defaultValue: false)
  bool produtoNovoNaCompra;

  /// Custo aplicado na entrada desta compra (para restauração segura).
  @HiveField(23, defaultValue: 0.0)
  double custoEntradaRegistrado;

  CompraFornecedorItem({
    required this.produtoNome,
    required this.quantidade,
    required this.custoUnitario,
    this.productId,
    this.itemCompraId = '',
    this.codigoInterno = '',
    this.codigoBarras = '',
    this.observacaoItem = '',
    this.unidade = '',
    this.subtotalBase = 0,
    this.percentualParticipacao = 0,
    this.freteRateado = 0,
    this.descontoRateado = 0,
    this.outrasDespesasRateadas = 0,
    this.custoUnitarioFinal = 0,
    this.subtotalFinal = 0,
    this.estoqueEntradaRegistrada = false,
    this.estoqueSnapshotOk = false,
    this.estoqueAnterior = 0,
    this.custoAnterior = 0,
    this.tamanhoEntrada = '',
    this.corEntrada = '',
    this.produtoNovoNaCompra = false,
    this.custoEntradaRegistrado = 0,
  });

  /// Custo efetivo gravado na entrada (prioriza [custoEntradaRegistrado]).
  double get custoEntradaEfetivo {
    if (custoEntradaRegistrado > 0) return custoEntradaRegistrado;
    if (custoUnitarioFinal > 0) return custoUnitarioFinal;
    return custoUnitario;
  }

  double get subtotal =>
      quantidade.clamp(0, 1 << 30) * custoUnitario;

  /// Custo unitário após rateio (pipeline, precificação, estoque). Fallback no custo base.
  double get custoUnitarioParaEstoquePrecificacao {
    final q = quantidade.clamp(0, 1 << 30);
    if (q <= 0) return custoUnitario;
    if (subtotalFinal > 0) {
      return custoUnitarioFinal > 0 ? custoUnitarioFinal : subtotalFinal / q;
    }
    return custoUnitario;
  }

  CompraFornecedorItem copyWith({
    String? produtoNome,
    int? quantidade,
    double? custoUnitario,
    String? productId,
    String? itemCompraId,
    String? codigoInterno,
    String? codigoBarras,
    String? observacaoItem,
    String? unidade,
    double? subtotalBase,
    double? percentualParticipacao,
    double? freteRateado,
    double? descontoRateado,
    double? outrasDespesasRateadas,
    double? custoUnitarioFinal,
    double? subtotalFinal,
    bool? estoqueEntradaRegistrada,
    bool? estoqueSnapshotOk,
    int? estoqueAnterior,
    double? custoAnterior,
    String? tamanhoEntrada,
    String? corEntrada,
    bool? produtoNovoNaCompra,
    double? custoEntradaRegistrado,
  }) {
    return CompraFornecedorItem(
      produtoNome: produtoNome ?? this.produtoNome,
      quantidade: quantidade ?? this.quantidade,
      custoUnitario: custoUnitario ?? this.custoUnitario,
      productId: productId ?? this.productId,
      itemCompraId: itemCompraId ?? this.itemCompraId,
      codigoInterno: codigoInterno ?? this.codigoInterno,
      codigoBarras: codigoBarras ?? this.codigoBarras,
      observacaoItem: observacaoItem ?? this.observacaoItem,
      unidade: unidade ?? this.unidade,
      subtotalBase: subtotalBase ?? this.subtotalBase,
      percentualParticipacao:
          percentualParticipacao ?? this.percentualParticipacao,
      freteRateado: freteRateado ?? this.freteRateado,
      descontoRateado: descontoRateado ?? this.descontoRateado,
      outrasDespesasRateadas:
          outrasDespesasRateadas ?? this.outrasDespesasRateadas,
      custoUnitarioFinal: custoUnitarioFinal ?? this.custoUnitarioFinal,
      subtotalFinal: subtotalFinal ?? this.subtotalFinal,
      estoqueEntradaRegistrada:
          estoqueEntradaRegistrada ?? this.estoqueEntradaRegistrada,
      estoqueSnapshotOk: estoqueSnapshotOk ?? this.estoqueSnapshotOk,
      estoqueAnterior: estoqueAnterior ?? this.estoqueAnterior,
      custoAnterior: custoAnterior ?? this.custoAnterior,
      tamanhoEntrada: tamanhoEntrada ?? this.tamanhoEntrada,
      corEntrada: corEntrada ?? this.corEntrada,
      produtoNovoNaCompra: produtoNovoNaCompra ?? this.produtoNovoNaCompra,
      custoEntradaRegistrado:
          custoEntradaRegistrado ?? this.custoEntradaRegistrado,
    );
  }
}
