import 'package:hive/hive.dart';

part 'fornecedor.g.dart';

@HiveType(typeId: 3)
class Fornecedor extends HiveObject {
  @HiveField(0)
  String nome;

  @HiveField(1)
  String telefone;

  @HiveField(2)
  String email;

  @HiveField(3)
  DateTime dataCadastro;

  @HiveField(4)
  String instagram;

  @HiveField(5)
  String whatsapp;

  @HiveField(6)
  String linkInstagram;

  @HiveField(7)
  String linkWhatsapp;

  /// 🔹 Multi-loja: identifica a loja dona deste fornecedor
  @HiveField(8)
  String lojaId;

  Fornecedor({
    required this.nome,
    required this.telefone,
    required this.email,
    DateTime? dataCadastro,
    this.instagram = '',
    this.whatsapp = '',
    this.linkInstagram = '',
    this.linkWhatsapp = '',
    this.lojaId = 'padrao',
  }) : dataCadastro = dataCadastro ?? DateTime.now();

  String get descricaoFornecedor =>
      'Nome: $nome, Telefone: $telefone, E-mail: $email';

  static bool validarEmail(String email) {
    final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    return regex.hasMatch(email);
  }
}