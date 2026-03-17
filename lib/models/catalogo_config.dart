import 'package:hive/hive.dart';

part 'catalogo_config.g.dart';

@HiveType(typeId: 6)
class CatalogoConfig extends HiveObject {
  @HiveField(0)
  String corFundo;

  @HiveField(1)
  String corTexto;

  @HiveField(2)
  String corBotao;

  @HiveField(3)
  String fonte;

  @HiveField(4)
  double tamanhoFonte;

  @HiveField(5)
  String corCabecalho;

  CatalogoConfig({
    required this.corFundo,
    required this.corTexto,
    required this.corBotao,
    required this.fonte,
    required this.tamanhoFonte,
    this.corCabecalho = '',
  });
}
