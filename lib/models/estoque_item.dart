import 'package:hive/hive.dart';

part 'estoque_item.g.dart';

@HiveType(typeId: 18)
class EstoqueItem extends HiveObject {
  @HiveField(0)
  late String nome;

  @HiveField(1)
  late int quantidade;

  @HiveField(2)
  late double precoUnitario;

  @HiveField(3)
  late String categoria;

  @HiveField(4)
  late String codigoBarras;

  @HiveField(5)
  late DateTime dataEntrada;

  EstoqueItem({
    required this.nome,
    required this.quantidade,
    required this.precoUnitario,
    required this.categoria,
    required this.codigoBarras,
    required this.dataEntrada,
  });

  double get valorTotalEstoque => quantidade * precoUnitario;
}
