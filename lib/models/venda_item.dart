import 'package:hive/hive.dart';

part 'venda_item.g.dart';

@HiveType(typeId: 7) // use um ID LIVRE que não conflite com os seus
class VendaItem {
  @HiveField(0)
  String produtoNome;

  @HiveField(1)
  int quantidade;

  @HiveField(2)
  double precoUnitario;

  @HiveField(3)
  String tamanho;

  @HiveField(4)
  String lojaId;

  @HiveField(5)
  String cor;

  /// ID do produto no Firestore (idFirebase). Opcional para compatibilidade com vendas antigas.
  /// Quando preenchido, fluxos de duplicação e devolução usam este ID primeiro.
  @HiveField(6)
  String? productId;

  /// Ex.: "Letra: A" ou "Estampa: Floral" (catálogo web / pré-pedido).
  @HiveField(7, defaultValue: '')
  String variacaoExtraResumo;

  /// Personalização (ex.: letra) quando a grade usa mapa extra→qtd na célula. Usado na baixa Firestore.
  @HiveField(8, defaultValue: '')
  String extraValor;

  /// Custo unitário efetivo aplicado ao item na venda (congelado para relatório/lucro).
  @HiveField(9)
  double? custoUnitario;

  /// Rastreio: [VendaOrigemCusto] — opcional (vendas antigas).
  @HiveField(10)
  String? origemCustoItem;

  VendaItem({
    required this.produtoNome,
    required this.quantidade,
    required this.precoUnitario,
    this.tamanho = '',
    this.lojaId = '',
    this.cor = '',
    this.productId,
    this.variacaoExtraResumo = '',
    this.extraValor = '',
    this.custoUnitario,
    this.origemCustoItem,
  });
}
