import 'package:hive/hive.dart';

part 'categoria.g.dart';

@HiveType(typeId: 17)
class Categoria extends HiveObject {
  @HiveField(0)
  late String nome;

  Categoria({required this.nome});
}
