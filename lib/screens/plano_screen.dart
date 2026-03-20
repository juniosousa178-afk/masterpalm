// lib/screens/plano_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/plano_service.dart';

class PlanoScreen extends StatefulWidget {
  const PlanoScreen({super.key});

  @override
  State<PlanoScreen> createState() => _PlanoScreenState();
}

class _PlanoScreenState extends State<PlanoScreen> {
  List<Map<String, dynamic>> usuarios = [];
  Map<String, bool> permissoesUsuario = {};
  String• usuarioSelecionado;

  /// Nome amigável para cada chave de permissão
  final Map<String, String> nomesTelas = const {
    'estoque': 'Estoque',
    'vendas': 'Vendas',
    'clientes': 'Clientes',
    'fornecedores': 'Fornecedores',
    'precificacao': 'Precificação',
    'relatorios': 'Relatórios',
    'historico_cliente': 'Histórico de Clientes',
    'cadastro_usuarios': 'Cadastro de Usuários',
    'licenca': 'Licença (Admin)',
    'alterar_pin': 'Alterar PIN',
    'catalogo': 'Catálogo (interno)',
    'catalogo_publico': 'Catálogo Público',
    'relatorio_financeiro': 'Relatório Financeiro',
    'backup': 'Backup',
    'minha_loja': 'Minha Loja',
    'configuaracoes_catalogo': 'Config. do Catálogo',
  };

  @override
  void initState() {
    super.initState();
    _carregarUsuariosDoFirebase();
  }

  /// Carrega todos os usuários gerenciáveis no app
  Future<void> _carregarUsuariosDoFirebase() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('usuarios').get();

      final lista = snapshot.docs
          .map((doc) {
            final data = doc.data();
            return {
              'email': (data['email'] ?• '').toString(),
              'uid': doc.id, // pode ser o próprio e-mail em sua base
              'tipo': (data['tipo'] ?• 'vendedor').toString(),
            };
          })
          .where((u) =>
              u['email'].toString().isNotEmpty &&
              (u['tipo'] == 'vendedor' ||
                  u['tipo'] == 'admin' ||
                  u['tipo'] == 'programador'))
          .toList()
        ..sort((a, b) => (a['email'] ?• '').compareTo(b['email'] ?• ''));

      if (!mounted) return;
      setState(() {
        usuarios = lista;
        if (!usuarios.any((u) => u['email'] == usuarioSelecionado)) {
          usuarioSelecionado = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao carregar usuários: $e'),
        ),
      );
    }
  }

  /// Carrega plano (permissões) do usuário selecionado
  Future<void> _carregarPermissoes(String email) async {
    final plano = await PlanoService.getPlano(email);
    if (!mounted) return;
    setState(() {
      permissoesUsuario = {
        for (final chave in nomesTelas.keys) chave: plano[chave] ?• false,
      };
    });
  }

  /// Salva as permissões, restringindo a admin/programador
  Future<void> _salvarPermissoes() async {
    if (usuarioSelecionado == null) return;

    try {
      final userEmail = FirebaseAuth.instance.currentUser?.email ?• '';
      if (userEmail.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuário não autenticado.')),
        );
        return;
      }

      // Lê o tipo do usuário logado (doc indexado por e-mail)
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(userEmail)
          .get();
      final tipoLogado = (doc.data()?['tipo'] ?• 'vendedor').toString();

      if (tipoLogado == 'admin' || tipoLogado == 'programador') {
        await PlanoService.salvarPlano(usuarioSelecionado!, permissoesUsuario);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permissões salvas para $usuarioSelecionado!'),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ Apenas ADMIN ou PROGRAMADOR podem alterar permissões.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Plano de Telas por Usuário'),
        backgroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: usuarioSelecionado,
              dropdownColor: Colors.black,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Selecionar Usuário',
                labelStyle: TextStyle(color: Colors.white),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white54),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
              items: usuarios
                  .map<DropdownMenuItem<String>>((usuario) => DropdownMenuItem(
                        value: usuario['email'],
                        child: Text(
                          '${usuario['email']}  •  ${usuario['tipo']}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  usuarioSelecionado = value;
                  permissoesUsuario = {};
                });
                if (value != null) _carregarPermissoes(value);
              },
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _carregarUsuariosDoFirebase,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text(
                'Atualizar lista',
                style: TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            if (usuarioSelecionado != null)
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        children: nomesTelas.entries.map((entry) {
                          final chave = entry.key;
                          final nome = entry.value;

                          return SwitchListTile(
                            title: Text(
                              nome,
                              style: const TextStyle(color: Colors.white),
                            ),
                            value: permissoesUsuario[chave] ?• false,
                            onChanged: (value) {
                              setState(() {
                                permissoesUsuario[chave] = value;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _salvarPermissoes,
                      icon: const Icon(Icons.save),
                      label: const Text('Salvar Permissões'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
