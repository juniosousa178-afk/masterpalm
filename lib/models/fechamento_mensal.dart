import 'package:hive/hive.dart';

part 'fechamento_mensal.g.dart';

@HiveType(typeId: 8)
class FechamentoMensal extends HiveObject {
  @HiveField(0)
  int ano;

  @HiveField(1)
  int mes;

  @HiveField(2)
  double totalDinheiro;

  @HiveField(3)
  double totalPix;

  @HiveField(4)
  double totalCartao;

  @HiveField(5)
  double vendaTotal;

  @HiveField(6)
  double custoTotal;

  @HiveField(7)
  double taxasTotal;

  @HiveField(8)
  double lucroTotal;

  @HiveField(9)
  DateTime fechadoEm;

  /// 🔥 MULTI-LOJA
  @HiveField(10)
  String lojaId;

  FechamentoMensal({
    required this.ano,
    required this.mes,
    required this.totalDinheiro,
    required this.totalPix,
    required this.totalCartao,
    required this.vendaTotal,
    required this.custoTotal,
    required this.taxasTotal,
    required this.lucroTotal,
    required this.fechadoEm,
    required this.lojaId, // 🔥 AGORA OBRIGATÓRIO
  });
}