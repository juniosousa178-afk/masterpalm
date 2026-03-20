import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VisualizarPermissoesScreen extends StatefulWidget {
  const VisualizarPermissoesScreen({super.key});

  @override
  State<VisualizarPermissoesScreen> createState() =>
      _VisualizarPermissoesScreenState();
}

class _VisualizarPermissoesScreenState
    extends State<VisualizarPermissoesScreen> {
  final TextEditingController _uidController = TextEditingController();
  Map<String, bool> permissoes = {};
  bool carregando = false;

  final Map<String, String> nomes = {
    'estoque': 'Estoque',
    'clientes': 'Clientes',
    'relatorios': 'Relatórios',
    'vendas': 'Vendas',
    'precificacao': 'Precificação',
    'fornecedores': 'Fornecedores',
    'historico': 'Histórico de Clientes',
    'cadastro_usuarios': 'Cadastro de Usuários',
    'licenca': 'Licença (Admin)',
    'backup': 'Backup',
    'configuracoes': 'Configurações',
    'alterar_pin': 'Alterar PIN',
  };

  Future<void> carregarPermissoes() async {
    final uid = _uidController.text.trim();
    if (uid.isEmpty) return;

    setState(() => carregando = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();

      if (doc.exists && doc.data()!.containsKey('permissoes')) {
        final dados = Map<String, dynamic>.from(doc['permissoes']);
        setState(() {
          permissoes = dados.map((k, v) => MapEntry(k, v == true));
        });
      } else {
        setState(() => permissoes = {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permissões não encontradas.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar permissões: $e')),
        );
      }
    }

    setState(() => carregando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Visualizar Permissões'),
        backgroundColor: Colors.black,
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _uidController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'UID do Vendedor',
                labelStyle: const TextStyle(color: Colors.white),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search, color: Colors.white),
                  onPressed: carregarPermissoes,
                ),
                enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white38)),
                focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white)),
              ),
              onSubmitted: (_) => carregarPermissoes(),
            ),
          ),
          const SizedBox(height: 20),
          if (carregando)
            const CircularProgressIndicator()
          else if (permissoes.isNotEmpty)
            Expanded(
              child: ListView(
                children: permissoes.entries.map((entry) {
                  return ListTile(
                    title: Text(
                      nomes[entry.key] ?? entry.key,
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: Icon(
                      entry.value ? Icons.check_circle : Icons.cancel_outlined,
                      color: entry.value ? Colors.green : Colors.red,
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
