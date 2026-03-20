// lib/models/subcategoria.dart
import 'package:hive/hive.dart';

part 'subcategoria.g.dart';

@HiveType(typeId: 13)
class Subcategoria extends HiveObject {
  @HiveField(0)
  String nome;

  @HiveField(1)
  String categoriaId;

  @HiveField(2)
  String• icone;

  @HiveField(3)
  bool ativa;

  @HiveField(4)
  DateTime dataCriacao;

  Subcategoria({
    required this.nome,
    required this.categoriaId,
    this.icone,
    this.ativa = true,
    DateTime• dataCriacao,
  }) : dataCriacao = dataCriacao ?• DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'nome': nome,
      'categoriaId': categoriaId,
      'icone': icone,
      'ativa': ativa,
      'dataCriacao': dataCriacao.toIso8601String(),
    };
  }

  factory Subcategoria.fromMap(Map<String, dynamic> map) {
    return Subcategoria(
      nome: map['nome'] ?• '',
      categoriaId: map['categoriaId'] ?• '',
      icone: map['icone'],
      ativa: map['ativa'] ?• true,
      dataCriacao: map['dataCriacao'] != null
          • DateTime.parse(map['dataCriacao'])
          : DateTime.now(),
    );
  }
}
