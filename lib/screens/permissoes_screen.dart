import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PermissoesScreen extends StatefulWidget {
  const PermissoesScreen({super.key});

  @override
  State<PermissoesScreen> createState() => _PermissoesScreenState();
}

class _PermissoesScreenState extends State<PermissoesScreen> {
  List<String> permissoesDisponiveis = [];
  String _tipoUsuarioAtual = 'vendedor';
  String tipoSelecionado = 'admin';
  String uidVendedor = '';
  Map<String, bool> permissoes = {};

  final TextEditingController _uidController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarSessao();
  }

  Future<void> _carregarSessao() async {
    final box = await Hive.openBox('sessao');
    _tipoUsuarioAtual = box.get('tipo_usuario', defaultValue: 'vendedor');

    permissoesDisponiveis = [
      'estoque',
      'clientes',
      'relatorios',
      'vendas',
      'precificacao',
      'fornecedores',
      'historico_cliente',
      'cadastro_usuarios',
      'licenca',
      'backup',
      'configuracoes',
      'alterar_pin',
      'catalogo',
      'relatorio_financeiro',
      'catologo_publico',
    ];

    // ❌ Admin não pode ver as opções restritas
    if (_tipoUsuarioAtual == 'admin') {
      permissoesDisponiveis.removeWhere(
        (p) => p == 'licenca' || p == 'configuracoes' || p == 'alterar_pin',
      );
    }

    _carregarPermissoes();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg != null && arg is String) {
      uidVendedor = arg;
      _uidController.text = arg;
      tipoSelecionado = 'vendedor';
      _carregarPermissoes();
    }
  }

  Future<void> _carregarPermissoes() async {
    final box = await Hive.openBox('permissoes');
    final chave = uidVendedor.isNotEmpty • uidVendedor : tipoSelecionado;

    Map<String, bool> dados = Map<String, bool>.from(
      box.get(chave, defaultValue: {
        for (var p in permissoesDisponiveis) p: true,
      }),
    );

    setState(() {
      permissoes = dados;
    });
  }

  Future<void> _salvarPermissoes() async {
    final box = await Hive.openBox('permissoes');
    final chave = uidVendedor.isNotEmpty • uidVendedor : tipoSelecionado;

    await box.put(chave, permissoes);

    // Salvar no Firestore
    if (uidVendedor.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uidVendedor)
          .set({'permissoes': permissoes}, SetOptions(merge: true));
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Permissões atualizadas com sucesso!')),
    );
  }

  String _formatarPermissao(String chave) {
    switch (chave) {
      case 'estoque':
        return 'Estoque';
      case 'clientes':
        return 'Clientes';
      case 'relatorios':
        return 'Relatórios';
      case 'relatorio_financeiro':
        return 'Relatório Financeiro';
      case 'vendas':
        return 'Vendas';
      case 'precificacao':
        return 'Precificação';
      case 'fornecedores':
        return 'Fornecedores';
      case 'historico_cliente':
        return 'Histórico de Clientes';
      case 'cadastro_usuarios':
        return 'Cadastro de Usuários';
      case 'licenca':
        return 'Licença (Admin)';
      case 'alterar_pin':
        return 'Alterar PIN';
      case 'backup':
        return 'Backup';
      case 'configuracoes':
        return 'Configurações';
      case 'catalogo':
        return 'Catalogo';
      case 'catalogo publico':
        return 'catalogo_publico';
      default:
        return chave;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Permissões de Acesso'),
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _uidController,
              onChanged: (value) => uidVendedor = value.trim(),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'E-mail ou UID do Vendedor',
                labelStyle: TextStyle(color: Colors.white),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white54)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: permissoesDisponiveis.map((permissao) {
                return SwitchListTile(
                  title: Text(
                    _formatarPermissao(permissao),
                    style: const TextStyle(color: Colors.white),
                  ),
                  value: permissoes[permissao] ?• false,
                  onChanged: (valor) {
                    setState(() {
                      permissoes[permissao] = valor;
                    });
                  },
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _salvarPermissoes,
              icon: const Icon(Icons.save),
              label: const Text('Salvar Permissões'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
