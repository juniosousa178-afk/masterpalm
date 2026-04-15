// lib/screens/gerenciar_vendedores_screen.dart
// Tela para admin gerenciar vendedores e suas permissões

import 'package:flutter/material.dart';
import '../services/store_resolver_facade.dart';
import '../services/vendedor_service.dart';

/// Tela de gerenciamento de vendedores (apenas admin/programador)
class GerenciarVendedoresScreen extends StatefulWidget {
  const GerenciarVendedoresScreen({super.key});

  @override
  State<GerenciarVendedoresScreen> createState() => _GerenciarVendedoresScreenState();
}

class _GerenciarVendedoresScreenState extends State<GerenciarVendedoresScreen> {
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _warningColor = Color(0xFFF59E0B);

  final _vendedorService = VendedorService();
  List<VendedorPerfil> _vendedores = [];
  bool _carregando = true;
  String? _storeId;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _carregando = true);

    try {
      _storeId = (await StoreResolverFacade.resolveForAdminApp())?.trim();

      if (_storeId == null || _storeId!.isEmpty) {
        _snack('Loja não identificada', isError: true);
        return;
      }

      _vendedores = await _vendedorService.listarVendedores(_storeId!);
    } catch (e) {
      _snack('Erro ao carregar vendedores: $e', isError: true);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _snack(String msg, {bool isError = false, bool isWarning = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _errorColor : isWarning ? _warningColor : _successColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Gerenciar Vendedores'),
        centerTitle: true,
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _vendedores.isEmpty
              ? _buildEmptyState()
              : _buildLista(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirCadastroVendedor(),
        backgroundColor: _primaryColor,
        icon: const Icon(Icons.person_add),
        label: const Text('Novo Vendedor'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum vendedor cadastrado',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Adicione vendedores para sua equipe',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLista() {
    return RefreshIndicator(
      onRefresh: _carregarDados,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _vendedores.length,
        itemBuilder: (context, index) {
          final vendedor = _vendedores[index];
          return _buildVendedorCard(vendedor);
        },
      ),
    );
  }

  Widget _buildVendedorCard(VendedorPerfil vendedor) {
    final permissoesAtivas = vendedor.permissoes.entries
        .where((e) => e.value == true && !['meu_perfil', 'minhas_comissoes', 'meu_link'].contains(e.key))
        .map((e) => e.key)
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _abrirPermissoes(vendedor),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    backgroundColor: vendedor.ativo ? _primaryColor : Colors.grey,
                    child: Text(
                      vendedor.nome.isNotEmpty ? vendedor.nome[0].toUpperCase() : 'V',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vendedor.nome,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          vendedor.email,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: vendedor.ativo ? _successColor.withOpacity(0.1) : _errorColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      vendedor.ativo ? 'Ativo' : 'Inativo',
                      style: TextStyle(
                        color: vendedor.ativo ? _successColor : _errorColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Permissões
              if (permissoesAtivas.isEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _warningColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber, color: _warningColor, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Nenhuma permissão liberada',
                        style: TextStyle(color: _warningColor, fontSize: 12),
                      ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: permissoesAtivas.map((p) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _traduzirPermissao(p),
                        style: const TextStyle(
                          color: _primaryColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 12),
              // Ações
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _abrirPermissoes(vendedor),
                    icon: const Icon(Icons.security, size: 18),
                    label: const Text('Permissões'),
                    style: TextButton.styleFrom(foregroundColor: _primaryColor),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _alterarStatus(vendedor),
                    icon: Icon(
                      vendedor.ativo ? Icons.block : Icons.check_circle,
                      size: 18,
                    ),
                    label: Text(vendedor.ativo ? 'Desativar' : 'Ativar'),
                    style: TextButton.styleFrom(
                      foregroundColor: vendedor.ativo ? _errorColor : _successColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _traduzirPermissao(String key) {
    const traducoes = {
      'catalogo': 'Catálogo',
      'vendas': 'Vendas',
      'estoque': 'Estoque',
      'clientes': 'Clientes',
      'historico_cliente': 'Histórico',
    };
    return traducoes[key] ?? key;
  }

  Future<void> _abrirPermissoes(VendedorPerfil vendedor) async {
    final permissoesAtuais = Map<String, bool>.from(vendedor.permissoes);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PermissoesSheet(
        vendedor: vendedor,
        permissoes: permissoesAtuais,
        onSalvar: (novasPermissoes) async {
          final ok = await _vendedorService.atualizarPermissoes(
            vendedor.uid,
            _storeId!,
            novasPermissoes,
          );

          if (ok) {
            _snack('Permissões atualizadas!');
            await _carregarDados();
          } else {
            _snack('Erro ao atualizar permissões', isError: true);
          }
        },
      ),
    );
  }

  Future<void> _alterarStatus(VendedorPerfil vendedor) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(vendedor.ativo ? 'Desativar vendedor?' : 'Ativar vendedor?'),
        content: Text(
          vendedor.ativo
              ? 'O vendedor não poderá mais acessar o sistema.'
              : 'O vendedor poderá acessar o sistema novamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: vendedor.ativo ? _errorColor : _successColor,
            ),
            child: Text(vendedor.ativo ? 'Desativar' : 'Ativar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final ok = await _vendedorService.alterarStatus(
      vendedor.uid,
      _storeId!,
      !vendedor.ativo,
    );

    if (ok) {
      _snack(vendedor.ativo ? 'Vendedor desativado' : 'Vendedor ativado');
      await _carregarDados();
    } else {
      _snack('Erro ao alterar status', isError: true);
    }
  }

  void _abrirCadastroVendedor() {
    Navigator.pushNamed(context, '/cadastro_usuario').then((_) => _carregarDados());
  }
}

/// Sheet para editar permissões
class _PermissoesSheet extends StatefulWidget {
  final VendedorPerfil vendedor;
  final Map<String, bool> permissoes;
  final Function(Map<String, bool>) onSalvar;

  const _PermissoesSheet({
    required this.vendedor,
    required this.permissoes,
    required this.onSalvar,
  });

  @override
  State<_PermissoesSheet> createState() => _PermissoesSheetState();
}

class _PermissoesSheetState extends State<_PermissoesSheet> {
  late Map<String, bool> _permissoes;

  static const _permissoesLiberaveis = [
    {'key': 'catalogo', 'label': 'Catálogo', 'desc': 'Ver catálogo de produtos'},
    {'key': 'vendas', 'label': 'Vendas', 'desc': 'Registrar vendas'},
    {'key': 'estoque', 'label': 'Estoque', 'desc': 'Gerenciar estoque'},
    {'key': 'clientes', 'label': 'Clientes', 'desc': 'Gerenciar clientes'},
    {'key': 'historico_cliente', 'label': 'Histórico', 'desc': 'Ver histórico de clientes'},
  ];

  @override
  void initState() {
    super.initState();
    _permissoes = Map<String, bool>.from(widget.permissoes);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF6366F1),
                child: Text(
                  widget.vendedor.nome.isNotEmpty ? widget.vendedor.nome[0].toUpperCase() : 'V',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.vendedor.nome,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Text(
                      'Gerenciar permissões',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Lista de permissões
          ..._permissoesLiberaveis.map((p) {
            final key = p['key'] as String;
            return SwitchListTile(
              value: _permissoes[key] ?? false,
              onChanged: (v) => setState(() => _permissoes[key] = v),
              title: Text(p['label'] as String),
              subtitle: Text(
                p['desc'] as String,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              contentPadding: EdgeInsets.zero,
            );
          }),

          const SizedBox(height: 16),

          // Info bloqueadas
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Vendedores nunca têm acesso a: pré-pedidos, confirmação de compra, relatórios financeiros, configurações.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Botão salvar
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                widget.onSalvar(_permissoes);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Salvar Permissões', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

