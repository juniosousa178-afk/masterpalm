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
  });

  double get subtotal =>
      quantidade.clamp(0, 1 << 30) * custoUnitario;

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
    );
  }
}
