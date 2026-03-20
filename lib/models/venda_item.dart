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
  String• productId;

  VendaItem({
    required this.produtoNome,
    required this.quantidade,
    required this.precoUnitario,
    this.tamanho = '',
    this.lojaId = '',
    this.cor = '',
    this.productId,
  });
}
