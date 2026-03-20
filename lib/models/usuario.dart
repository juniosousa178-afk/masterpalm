// lib/models/usuario.dart
import 'package:hive/hive.dart';

part 'usuario.g.dart';

@HiveType(typeId: 4)
class Usuario extends HiveObject {
  @HiveField(0)
  String nome;

  @HiveField(1)
  String senha;

  @HiveField(2)
  String tipo; // 'programador' | 'admin' | 'vendedor'

  @HiveField(3)
  Map<String, bool> permissoes;

  @HiveField(4)
  String email;

  @HiveField(5)
  String telefone;

  Usuario({
    required this.nome,
    required this.senha,
    required this.tipo,
    Map<String, bool>? permissoes,
    required this.email,
    required this.telefone,
  }) : permissoes = permissoes ?? defaultPermissoes(tipo);

  /// Permissões padrão por tipo
  static Map<String, bool> defaultPermissoes(String tipo) {
    switch (tipo) {
      case 'programador':
        return {
          'estoque': true,
          'clientes': true,
          'relatorios': true,
          'vendas': true,
          'precificacao': true,
          'fornecedores': true,
          'historico': true,
          'cadastro_usuarios': true,
          'licenca': true,
          'backup': true,
          'configuracoes': true,
          'alterar_pin': true,
        };
      case 'admin':
        return {
          'estoque': true,
          'clientes': true,
          'relatorios': true,
          'vendas': true,
          'precificacao': true,
          'fornecedores': true,
          'historico': true,
          'cadastro_usuarios': true,
          'licenca': false, // só programador
          'backup': true,
          'configuracoes': true,
          'alterar_pin': true,
        };
      default: // vendedor
        return {
          'estoque': false,
          'clientes': false,
          'relatorios': false,
          'vendas': true,
          'precificacao': false,
          'fornecedores': false,
          'historico': false,
          'cadastro_usuarios': false,
          'licenca': false,
          'backup': false,
          'configuracoes': false,
          'alterar_pin': false,
        };
    }
  }
}
