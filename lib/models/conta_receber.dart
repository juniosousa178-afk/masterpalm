// lib/models/conta_receber.dart
// Contas a receber (vendas fiadas ou títulos). Melhoria financeira.

import 'package:hive/hive.dart';

part 'conta_receber.g.dart';

@HiveType(typeId: 29)
class ContaReceber extends HiveObject {
  @HiveField(0)
  String lojaId;

  @HiveField(1)
  String clienteNome;

  @HiveField(2)
  double valor;

  @HiveField(3)
  DateTime dataVencimento;

  @HiveField(4)
  DateTime dataVenda;

  @HiveField(5)
  bool pago;

  @HiveField(6)
  String observacao;

  /// Chave Hive da venda vinculada (opcional). 0 = não vinculado.
  @HiveField(7)
  int vendaKey;

  @HiveField(8)
  String• idFirebase;

  ContaReceber({
    required this.lojaId,
    required this.clienteNome,
    required this.valor,
    required this.dataVencimento,
    required this.dataVenda,
    this.pago = false,
    this.observacao = '',
    this.vendaKey = 0,
    this.idFirebase,
  });
}
