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

  /// idFirebase do produto quando conhecido (Fase 2+).
  @HiveField(3)
  String? productId;

  CompraFornecedorItem({
    required this.produtoNome,
    required this.quantidade,
    required this.custoUnitario,
    this.productId,
  });

  double get subtotal =>
      quantidade.clamp(0, 1 << 30) * custoUnitario;
}
